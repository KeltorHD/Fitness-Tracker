using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.IdentityModel.Tokens;
using Npgsql;
using FitnessTracker.ServerLogging;

namespace FitnessTracker.Backend;

public partial class Program
{
    public static async Task Main(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);
        var config = builder.Configuration;
        builder.Logging.AddFilter("Microsoft.AspNetCore", LogLevel.Warning);
        builder.Logging.AddFilter("Microsoft.EntityFrameworkCore", LogLevel.Warning);
        builder.Logging.AddNtfy("Backend");
        builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = BackupStorage.MaximumBytes);
        builder.Services.AddProblemDetails();
        builder.Services.AddOpenApi();
        builder.Services.AddDbContext<BackupDbContext>(options => options.UseNpgsql(
            config.GetConnectionString("Database") ?? "Host=localhost;Database=fitnesstracker_backend;Username=fitnesstracker_backend"));
        builder.Services.AddSingleton(TimeProvider.System);
        builder.Services.AddScoped<BackupStorage>();
        builder.Services.AddOptions<IntrospectionOptions>()
            .BindConfiguration("Auth")
            .Validate(options => Uri.TryCreate(options.Issuer, UriKind.Absolute, out var uri) &&
                uri.Scheme == Uri.UriSchemeHttps && uri.AbsolutePath == "/" &&
                uri.UserInfo.Length == 0 && uri.Query.Length == 0 && uri.Fragment.Length == 0,
                "Auth:Issuer must be a root HTTPS URL without credentials, query or fragment.")
            .Validate(options => !string.IsNullOrWhiteSpace(options.IntrospectionClientSecret) &&
                options.IntrospectionClientSecret.Length >= 32, "Auth:IntrospectionClientSecret must have at least 32 characters.")
            .ValidateOnStart();
        builder.Services.AddHttpClient<TokenIntrospection>(client => client.Timeout = TimeSpan.FromSeconds(5))
            .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
            {
                AllowAutoRedirect = false,
                UseCookies = false,
                PooledConnectionLifetime = TimeSpan.FromMinutes(5)
            })
            .RemoveAllLoggers();
        builder.Services.AddScoped<DependencyAwareJwtBearerEvents>();
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
        {
            options.EventsType = typeof(DependencyAwareJwtBearerEvents);
            options.IncludeErrorDetails = false;
            options.BackchannelTimeout = TimeSpan.FromSeconds(5);
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
        // Права Backend задаются здесь; OAuth scopes не определяют доступ к функциям сервиса.
        builder.Services.AddAuthorization(options => options.AddPolicy("backend", policy =>
            policy.RequireAuthenticatedUser().RequireAssertion(context =>
                Guid.TryParse(context.User.FindFirst("sub")?.Value, out _))));
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
        var protection = builder.Services.AddDataProtection().SetApplicationName("FitnessTracker.Backend");
        if (config["DataProtection:Path"] is { Length: > 0 } keyPath)
            protection.PersistKeysToFileSystem(new DirectoryInfo(keyPath));
        else if (builder.Environment.IsProduction())
            throw new InvalidOperationException("Missing DataProtection:Path.");
        if (builder.Environment.IsProduction())
            protection.ProtectKeysWithCertificate(X509CertificateLoader.LoadPkcs12FromFile(
                config["Certificates:Encryption:Path"] ?? throw new InvalidOperationException("Missing Backend encryption certificate."),
                config["Certificates:Encryption:Password"]));
        await using var app = builder.Build();
        await using var ntfy = app.Services.StartNtfyLogging();
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
        var backups = app.MapGroup("/v1/backups")
            .RequireAuthorization("backend")
            .RequireRateLimiting("backups")
            .AddEndpointFilter<ActiveSessionFilter>();
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
        try
        {
            if (!app.Environment.IsEnvironment("Testing"))
            {
                await using var scope = app.Services.CreateAsyncScope();
                var database = scope.ServiceProvider.GetRequiredService<BackupDbContext>();
                var cancellationToken = app.Lifetime.ApplicationStopping;
                // Отдельное непулируемое соединение удерживает блокировку до конца startup.
                var startupSettings = new NpgsqlConnectionStringBuilder(database.Database.GetConnectionString())
                {
                    Pooling = false,
                    ApplicationName = "FitnessTracker startup"
                };
                await using var startupConnection = new NpgsqlConnection(startupSettings.ConnectionString);
                await startupConnection.OpenAsync(cancellationToken);
                await using var startupLock = new NpgsqlCommand("SELECT pg_advisory_lock(447295635001)", startupConnection);
                await startupLock.ExecuteNonQueryAsync(cancellationToken);
                await database.GetService<IHistoryRepository>().CreateIfNotExistsAsync(cancellationToken);
                await database.Database.MigrateAsync(cancellationToken);
                if (args.Contains("--migrate")) return;
            }
        }
        catch (Exception exception)
        {
            app.Logger.LogCritical(exception, "Backend database startup failed.");
            throw;
        }
        await app.RunAsync();
    }

    private static string Owner(HttpContext context) => context.User.FindFirst("sub")!.Value;

    private static async Task<IResult> Upload(Guid id, HttpContext context, BackupStorage storage, CancellationToken ct)
    {
        if (id == Guid.Empty) return Results.BadRequest(new { code = "invalid_id" });
        if (!MediaTypeHeaderValue.TryParse(context.Request.ContentType, out var contentType) ||
            (!string.Equals(contentType.MediaType, "application/vnd.fitnesstracker+json", StringComparison.OrdinalIgnoreCase) &&
             !string.Equals(contentType.MediaType, "application/json", StringComparison.OrdinalIgnoreCase)))
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
