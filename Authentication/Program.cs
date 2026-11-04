using System.Net;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using OpenIddict.Abstractions;
using OpenIddict.Validation.AspNetCore;

namespace FitnessTracker.Authentication;

public partial class Program
{
    public static async Task Main(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);
        var config = builder.Configuration;
        builder.Logging.AddFilter("OpenIddict", LogLevel.Warning);
        builder.Logging.AddFilter("Microsoft.AspNetCore", LogLevel.Warning);
        builder.Logging.AddFilter("Microsoft.EntityFrameworkCore", LogLevel.Warning);
        builder.Services.AddProblemDetails();
        builder.Services.AddControllersWithViews(options =>
            options.Filters.Add(new Microsoft.AspNetCore.Mvc.AutoValidateAntiforgeryTokenAttribute()));
        builder.Services.AddOpenApi();
        builder.Services.AddDbContext<AuthDbContext>(options =>
        {
            options.UseNpgsql(config.GetConnectionString("Database") ??
                "Host=localhost;Database=fitnesstracker_auth;Username=fitnesstracker_auth");
            options.UseOpenIddict();
        });
        builder.Services.AddIdentity<ApplicationUser, IdentityRole>(options =>
        {
            options.User.RequireUniqueEmail = false;
            options.Lockout.MaxFailedAccessAttempts = 5;
        }).AddEntityFrameworkStores<AuthDbContext>().AddDefaultTokenProviders();
        builder.Services.ConfigureApplicationCookie(options =>
        {
            options.Cookie.Name = "__Host-FitnessTrackerAuth";
            options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
            options.Cookie.HttpOnly = true;
            options.Cookie.SameSite = SameSiteMode.Lax;
            options.LoginPath = "/login";
            options.ExpireTimeSpan = TimeSpan.FromHours(1);
            options.SlidingExpiration = false;
        });
        builder.Services.Configure<SecurityStampValidatorOptions>(options =>
            options.ValidationInterval = TimeSpan.Zero);
        var protection = builder.Services.AddDataProtection().SetApplicationName("FitnessTracker.Authentication");
        if (config["DataProtection:Path"] is { Length: > 0 } keyPath)
            protection.PersistKeysToFileSystem(new DirectoryInfo(keyPath));
        if (builder.Environment.IsProduction())
            protection.ProtectKeysWithCertificate(AuthConfiguration.Certificate(config, "Encryption"));
        builder.Services.AddOpenIddict()
            .AddCore(options => options.UseEntityFrameworkCore().UseDbContext<AuthDbContext>())
            .AddClient(options =>
            {
                options.AllowAuthorizationCodeFlow();
                options.SetRedirectionEndpointUris("callback/login/google", "callback/login/apple", "callback/login/yandex");
                if (builder.Environment.IsEnvironment("Testing"))
                    options.AddEphemeralEncryptionKey().AddEphemeralSigningKey();
                else if (builder.Environment.IsDevelopment())
                    options.AddDevelopmentEncryptionCertificate().AddDevelopmentSigningCertificate();
                else
                    options.AddEncryptionCertificate(AuthConfiguration.Certificate(config, "Encryption"))
                        .AddSigningCertificate(AuthConfiguration.Certificate(config, "Signing"));
                options.UseAspNetCore().EnableRedirectionEndpointPassthrough();
                options.UseSystemNetHttp();
                AuthConfiguration.AddProviders(options, config);
            })
            .AddServer(options =>
            {
                options.SetIssuer(new Uri(config["Auth:Issuer"] ?? "https://localhost:5001/"));
                options.SetAuthorizationEndpointUris("connect/authorize")
                    .SetTokenEndpointUris("connect/token").SetRevocationEndpointUris("connect/revoke");
                options.AllowAuthorizationCodeFlow().AllowRefreshTokenFlow();
                options.RequireProofKeyForCodeExchange();
                options.Configure(server => server.CodeChallengeMethods.Remove(OpenIddictConstants.CodeChallengeMethods.Plain));
                options.RegisterScopes("openid", "profile", AuthConfiguration.Scope);
                options.SetAccessTokenLifetime(TimeSpan.FromMinutes(10));
                options.SetRefreshTokenLifetime(TimeSpan.FromDays(30));
                options.SetRefreshTokenReuseLeeway(TimeSpan.Zero);
                options.DisableAccessTokenEncryption();
                if (builder.Environment.IsEnvironment("Testing"))
                    options.AddEphemeralEncryptionKey().AddEphemeralSigningKey();
                else if (builder.Environment.IsDevelopment())
                    options.AddDevelopmentEncryptionCertificate().AddDevelopmentSigningCertificate();
                else
                    options.AddEncryptionCertificate(AuthConfiguration.Certificate(config, "Encryption"))
                        .AddSigningCertificate(AuthConfiguration.Certificate(config, "Signing"));
                options.UseAspNetCore().EnableAuthorizationEndpointPassthrough().EnableTokenEndpointPassthrough();
            })
            .AddValidation(options =>
            {
                options.UseLocalServer();
                options.EnableTokenEntryValidation();
                options.EnableAuthorizationEntryValidation();
                options.UseAspNetCore();
            });
        builder.Services.AddAuthorization(options => options.AddPolicy("account", policy =>
            policy.AddAuthenticationSchemes(OpenIddictValidationAspNetCoreDefaults.AuthenticationScheme)
                .RequireAuthenticatedUser().RequireAssertion(context => context.User.HasScope(AuthConfiguration.Scope))));
        builder.Services.AddScoped<ExternalAccounts>();
        builder.Services.AddHttpClient<BackupCleanup>(client => client.Timeout = TimeSpan.FromSeconds(30));
        builder.Services.Configure<ForwardedHeadersOptions>(options =>
        {
            options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            if (config["ReverseProxy:Address"] is { Length: > 0 } address)
                options.KnownProxies.Add(IPAddress.Parse(address));
        });
        builder.Services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
                RateLimitPartition.GetFixedWindowLimiter(context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    _ => new FixedWindowRateLimiterOptions { PermitLimit = 120, Window = TimeSpan.FromMinutes(1) }));
        });
        var app = builder.Build();
        app.UseForwardedHeaders();
        app.UseExceptionHandler();
        if (!app.Environment.IsDevelopment()) app.UseHsts();
        app.Use(async (context, next) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            context.Response.Headers["Referrer-Policy"] = "no-referrer";
            context.Response.Headers["X-Content-Type-Options"] = "nosniff";
            context.Response.Headers.ContentSecurityPolicy = "default-src 'none'; style-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'";
            await next();
        });
        app.UseStaticFiles();
        app.UseRouting();
        // OpenIddict может завершить запрос внутри authentication middleware.
        // IP-лимит должен применяться до разбора OAuth и проверки токенов.
        app.UseRateLimiter();
        app.UseAuthentication();
        app.UseAuthorization();
        app.MapControllers();
        app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
        if (app.Environment.IsDevelopment()) app.MapOpenApi();
        if (!app.Environment.IsEnvironment("Testing"))
        {
            await using var scope = app.Services.CreateAsyncScope();
            if (args.Contains("--migrate"))
            {
                await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Database.MigrateAsync();
                await AuthConfiguration.RegisterClient(scope.ServiceProvider, config);
                return;
            }
        }
        await app.RunAsync();
    }
}
