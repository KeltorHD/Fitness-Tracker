using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

namespace FitnessTracker.Backend;

public partial class Program
{
    public static async Task Main(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);
        var config = builder.Configuration;
        builder.Logging.AddFilter("Microsoft.AspNetCore", LogLevel.Warning);
        builder.Logging.AddFilter("Microsoft.EntityFrameworkCore", LogLevel.Warning);
        builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = BackupStorage.MaximumBytes);
        builder.Services.AddProblemDetails();
        builder.Services.AddOpenApi();
        builder.Services.AddDbContext<BackupDbContext>(options => options.UseNpgsql(
            config.GetConnectionString("Database") ?? "Host=localhost;Database=fitnesstracker_backups;Username=fitnesstracker_backups"));
        builder.Services.AddSingleton(TimeProvider.System);
        builder.Services.AddScoped<BackupStorage>();
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
        {
            options.Authority = config["Auth:Issuer"] ?? "https://localhost:5001/";
            options.Audience = "fitnesstracker-api";
            options.RequireHttpsMetadata = true;
            options.MapInboundClaims = false;
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidateAudience = true,
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                ClockSkew = TimeSpan.FromSeconds(30),
                ValidTypes = ["at+jwt"],
                ValidAlgorithms = [SecurityAlgorithms.RsaSha256]
            };
        });
        builder.Services.AddAuthorization(options => options.AddPolicy("backups", policy =>
            policy.RequireAuthenticatedUser().RequireAssertion(context =>
                Guid.TryParse(context.User.FindFirst("sub")?.Value, out _) &&
                context.User.FindAll("scope").Any(claim => claim.Value.Split(' ').Contains("backups")))));
        builder.Services.Configure<ForwardedHeadersOptions>(options =>
        {
            options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            if (config["ReverseProxy:Address"] is { Length: > 0 } address)
                options.KnownProxies.Add(IPAddress.Parse(address));
        });
        builder.Services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.AddPolicy("backups", context => RateLimitPartition.GetFixedWindowLimiter(
                context.User.FindFirst("sub")?.Value ?? context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                _ => new FixedWindowRateLimiterOptions { PermitLimit = 30, Window = TimeSpan.FromMinutes(1) }));
        });
        var app = builder.Build();
        app.UseForwardedHeaders();
        app.UseExceptionHandler();
        if (!app.Environment.IsDevelopment()) app.UseHsts();
        app.Use(async (context, next) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            context.Response.Headers["X-Content-Type-Options"] = "nosniff";
            await next();
        });
        app.UseAuthentication();
        app.UseAuthorization();
        app.UseRateLimiter();
        var backups = app.MapGroup("/v1/backups").RequireAuthorization("backups").RequireRateLimiting("backups");
        backups.MapGet("/", async (HttpContext context, BackupDbContext database, CancellationToken ct) =>
            Results.Ok(await database.Backups.AsNoTracking().Where(item => item.OwnerId == Owner(context))
                .OrderByDescending(item => item.CreatedAtMilliseconds).Select(item => new BackupInfo(
                    item.Id, DateTimeOffset.FromUnixTimeMilliseconds(item.CreatedAtMilliseconds), item.ArchiveVersion, item.Size, item.Sha256)).ToListAsync(ct)));
        backups.MapPut("/{id:guid}", Upload);
        backups.MapGet("/{id:guid}", async (Guid id, HttpContext context, BackupDbContext database, CancellationToken ct) =>
        {
            var backup = await database.Backups.AsNoTracking().SingleOrDefaultAsync(
                item => item.OwnerId == Owner(context) && item.Id == id, ct);
            if (backup is null) return Results.NotFound();
            context.Response.Headers.ETag = $"\"{backup.Sha256}\"";
            return Results.File(backup.Payload, "application/vnd.fitnesstracker+json", $"{backup.Id}.fitnesstracker");
        });
        backups.MapDelete("/{id:guid}", async (Guid id, HttpContext context, BackupDbContext database, CancellationToken ct) =>
        {
            var count = await database.Backups.Where(item => item.OwnerId == Owner(context) && item.Id == id).ExecuteDeleteAsync(ct);
            return count == 0 ? Results.NotFound() : Results.NoContent();
        });
        app.MapDelete("/internal/users/{id:guid}/backups", async (Guid id, HttpContext context,
            BackupStorage storage, CancellationToken ct) =>
        {
            var expected = config["Backend:ServiceKey"];
            var supplied = context.Request.Headers["X-Service-Key"].ToString();
            if (expected is not { Length: >= 32 } || !CryptographicOperations.FixedTimeEquals(
                SHA256.HashData(Encoding.UTF8.GetBytes(expected)), SHA256.HashData(Encoding.UTF8.GetBytes(supplied))))
                return Results.Unauthorized();
            await storage.DeleteAccount(id.ToString(), ct);
            return Results.NoContent();
        });
        app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
        if (app.Environment.IsDevelopment()) app.MapOpenApi();
        if (args.Contains("--migrate") && !app.Environment.IsEnvironment("Testing"))
        {
            await using var scope = app.Services.CreateAsyncScope();
            await scope.ServiceProvider.GetRequiredService<BackupDbContext>().Database.MigrateAsync();
            return;
        }
        await app.RunAsync();
    }

    private static string Owner(HttpContext context) => context.User.FindFirst("sub")!.Value;

    private static async Task<IResult> Upload(Guid id, HttpContext context, BackupStorage storage, CancellationToken ct)
    {
        if (id == Guid.Empty) return Results.BadRequest(new { code = "invalid_id" });
        if (context.Request.ContentType?.Split(';')[0] is not ("application/vnd.fitnesstracker+json" or "application/json"))
            return Results.StatusCode(415);
        if (context.Request.ContentLength > BackupStorage.MaximumBytes) return Results.StatusCode(413);
        using var data = new MemoryStream();
        var buffer = new byte[81920];
        while (true)
        {
            var read = await context.Request.Body.ReadAsync(buffer.AsMemory(0,
                (int)Math.Min(buffer.Length, BackupStorage.MaximumBytes + 1 - data.Length)), ct);
            if (read == 0) break;
            await data.WriteAsync(buffer.AsMemory(0, read), ct);
            if (data.Length > BackupStorage.MaximumBytes) return Results.StatusCode(413);
        }
        try
        {
            var (info, created) = await storage.Put(Owner(context), id, data.ToArray(), ct);
            return created ? Results.Created($"/v1/backups/{id}", info) : Results.Ok(info);
        }
        catch (BackupException error) { return Results.Json(new { code = error.Code }, statusCode: error.Status); }
    }
}
