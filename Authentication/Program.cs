using System.Net;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using FitLife.ServerLogging;
using OpenIddict.Abstractions;
using OpenIddict.Validation.AspNetCore;

namespace FitLife.Authentication;

public partial class Program
{
    public static async Task Main(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);
        var config = builder.Configuration;
        builder.Logging.AddFilter("OpenIddict", LogLevel.Warning);
        builder.Logging.AddFilter("Microsoft.AspNetCore", LogLevel.Warning);
        builder.Logging.AddFilter("Microsoft.EntityFrameworkCore", LogLevel.Warning);
        builder.Logging.AddNtfy("Authentication");
        builder.Services.AddProblemDetails();
        builder.Services.AddControllersWithViews(options =>
        {
            options.Filters.Add(new Microsoft.AspNetCore.Mvc.AutoValidateAntiforgeryTokenAttribute());
            options.Filters.Add<Controllers.AuthenticationExceptionFilter>();
        });
        builder.Services.AddSingleton(Controllers.AuthenticationMapping.Create());
        builder.Services.AddScoped<MapsterMapper.IMapper, MapsterMapper.Mapper>();
        builder.Services.AddScoped<BrowserNavigation>();
        builder.Services.AddScoped<AccountService>();
        builder.Services.AddScoped<PasswordService>();
        builder.Services.AddOptions<SmtpOptions>()
            .BindConfiguration("Smtp")
            .Validate(options => options.Validate())
            .ValidateOnStart();
        builder.Services.AddScoped<MailKit.Net.Smtp.ISmtpClient>(_ => new MailKit.Net.Smtp.SmtpClient());
        builder.Services.AddScoped<IAccountEmailSender, SmtpEmailSender>();
        builder.Services.AddScoped<EmailConfirmationService>();
        builder.Services.AddSingleton<EmailConfirmationThrottle>();
        builder.Services.TryAddSingleton(TimeProvider.System);
        builder.Services.AddScoped<PendingRegistrationCleanup>();
        // HTTP fixtures управляют временем и очисткой явно; обычный запуск начинает её после миграций.
        if (!builder.Environment.IsEnvironment("Testing"))
            builder.Services.AddHostedService<PendingRegistrationCleanupWorker>();
        builder.Services.AddScoped<PasskeyService>();
        builder.Services.AddScoped<ExternalLoginService>();
        builder.Services.AddScoped<HealthConnectionService>();
        builder.Services.AddSingleton<IHealthConnectionLocks, HealthConnectionLocks>();
        builder.Services.AddHttpClient("xiaomi-health-revoke", client => client.Timeout = TimeSpan.FromSeconds(15))
            .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { AllowAutoRedirect = false, UseCookies = false })
            .RemoveAllLoggers();
        builder.Services.AddScoped<AuthorizationService>();
        builder.Services.AddScoped<AppAssociationService>();
        builder.Services.AddOpenApi();
        builder.Services.AddDbContext<AuthDbContext>(options =>
        {
            options.UseNpgsql(config.GetConnectionString("Database") ??
                "Host=localhost;Database=authentication;Username=authentication");
            options.UseOpenIddict();
        });
        builder.Services.AddIdentity<ApplicationUser, IdentityRole>(options =>
        {
            options.User.RequireUniqueEmail = false;
            options.Lockout.MaxFailedAccessAttempts = 5;
            options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(15);
            options.SignIn.RequireConfirmedEmail = false;
            options.SignIn.RequireConfirmedAccount = true;
            options.Password.RequiredLength = 12;
            options.Password.RequiredUniqueChars = 4;
            options.Password.RequireDigit = false;
            options.Password.RequireLowercase = false;
            options.Password.RequireUppercase = false;
            options.Password.RequireNonAlphanumeric = false;
        }).AddEntityFrameworkStores<AuthDbContext>().AddDefaultTokenProviders();
        builder.Services.AddScoped<IUserConfirmation<ApplicationUser>, EmailAccountConfirmation>();
        builder.Services.Configure<DataProtectionTokenProviderOptions>(options => options.TokenLifespan = PendingRegistrationCleanup.Lifetime);
        builder.Services.Configure<PasswordHasherOptions>(options => options.IterationCount = 210_000);
        builder.Services.AddScoped<EmailAccounts>();
        builder.Services.AddSingleton<UnknownPasswordCheck>();
        builder.Services.AddSingleton<PasskeyChallenges>();
        builder.Services.Configure<IdentityPasskeyOptions>(options =>
        {
            var issuer = new Uri(config["Auth:Issuer"] ?? "https://localhost:5001/");
            if (issuer.Scheme != Uri.UriSchemeHttps)
                throw new InvalidOperationException("Passkeys require an HTTPS issuer.");
            options.ServerDomain = issuer.Host;
            options.UserVerificationRequirement = "required";
            options.ResidentKeyRequirement = "required";
            options.AttestationConveyancePreference = "none";
            options.AuthenticatorTimeout = TimeSpan.FromMinutes(3);
            options.ValidateOrigin = context => ValueTask.FromResult(
                !context.CrossOrigin && context.Origin == issuer.GetLeftPart(UriPartial.Authority));
        });
        builder.Services.Configure<Microsoft.AspNetCore.Authentication.Cookies.CookieAuthenticationOptions>(
            IdentityConstants.TwoFactorUserIdScheme, options =>
            {
                options.Cookie.Name = "__Host-FitLifePasskey";
                options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
                options.Cookie.HttpOnly = true;
                options.Cookie.SameSite = SameSiteMode.Strict;
                options.ExpireTimeSpan = TimeSpan.FromMinutes(5);
                options.SlidingExpiration = false;
            });
        builder.Services.AddAntiforgery(options => options.Cookie.SecurePolicy = CookieSecurePolicy.Always);
        builder.Services.ConfigureApplicationCookie(options =>
        {
            options.Cookie.Name = "__Host-FitLifeAuth";
            options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
            options.Cookie.HttpOnly = true;
            options.Cookie.SameSite = SameSiteMode.Lax;
            options.LoginPath = "/login";
            options.ExpireTimeSpan = TimeSpan.FromHours(1);
            options.SlidingExpiration = false;
        });
        builder.Services.Configure<SecurityStampValidatorOptions>(options =>
            options.ValidationInterval = TimeSpan.Zero);
        var protection = builder.Services.AddDataProtection().SetApplicationName("FitLife.Authentication");
        if (config["DataProtection:Path"] is { Length: > 0 } keyPath)
            protection.PersistKeysToFileSystem(new DirectoryInfo(keyPath));
        if (builder.Environment.IsProduction())
            protection.ProtectKeysWithCertificate(AuthConfiguration.Certificate(config, "Encryption"));
        builder.Services.AddOpenIddict()
            .AddCore(options => options.UseEntityFrameworkCore().UseDbContext<AuthDbContext>())
            .AddClient(options =>
            {
                options.AllowAuthorizationCodeFlow();
                options.SetRedirectionEndpointUris("callback/login/google", "callback/login/apple", "callback/login/yandex", XiaomiHealthOAuth.CallbackPath);
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
                XiaomiHealthOAuth.Configure(options, config);
            })
            .AddServer(options =>
            {
                options.SetIssuer(new Uri(config["Auth:Issuer"] ?? "https://localhost:5001/"));
                options.SetAuthorizationEndpointUris("connect/authorize")
                    .SetTokenEndpointUris("connect/token")
                    .SetRevocationEndpointUris("connect/revoke")
                    .SetIntrospectionEndpointUris("connect/introspect");
                options.RemoveEventHandler(OpenIddict.Server.OpenIddictServerHandlers.Revocation.RevokeToken.Descriptor);
                options.AddEventHandler<OpenIddict.Server.OpenIddictServerEvents.HandleRevocationRequestContext>(handler => handler
                    .UseScopedHandler<RevokeSessionHandler>()
                    .SetOrder(OpenIddict.Server.OpenIddictServerHandlers.Revocation.RevokeToken.Descriptor.Order));
                options.AllowAuthorizationCodeFlow().AllowRefreshTokenFlow();
                options.RequireProofKeyForCodeExchange();
                options.Configure(server => server.CodeChallengeMethods.Remove(OpenIddictConstants.CodeChallengeMethods.Plain));
                options.RegisterScopes("openid", "profile");
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
                .RequireAuthenticatedUser().RequireAssertion(context =>
                    Guid.TryParse(context.User.FindFirst("sub")?.Value, out _))));
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
            options.AddPolicy("credentials", context => RateLimitPartition.GetFixedWindowLimiter(
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ =>
                    new FixedWindowRateLimiterOptions { PermitLimit = 20, Window = TimeSpan.FromMinutes(1) }));
            options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
                // Introspection закрыта Nginx для внешних клиентов и использует confidential client.
                // Её отдельный общий бюджет не расходует IP-лимит обычных пользовательских входов.
                context.Request.Path.Value?.TrimEnd('/').Equals("/connect/introspect", StringComparison.OrdinalIgnoreCase) == true ||
                context.Request.Path.StartsWithSegments("/internal/health", StringComparison.OrdinalIgnoreCase)
                    ? RateLimitPartition.GetFixedWindowLimiter("service:introspection", _ =>
                        new FixedWindowRateLimiterOptions { PermitLimit = 1200, Window = TimeSpan.FromMinutes(1) })
                    : RateLimitPartition.GetFixedWindowLimiter("ip:" + (context.Connection.RemoteIpAddress?.ToString() ?? "unknown"),
                        _ => new FixedWindowRateLimiterOptions { PermitLimit = 120, Window = TimeSpan.FromMinutes(1) }));
        });
        await using var app = builder.Build();
        await using var ntfy = app.Services.StartNtfyLogging();
        app.UseForwardedHeaders();
        app.UseExceptionHandler();
        if (!app.Environment.IsDevelopment()) app.UseHsts();
        app.Use(async (context, next) =>
        {
            // Совпадает с требованиями antiforgery, чтобы формы не перезаписывали заголовки с Warning.
            context.Response.Headers.CacheControl = "no-cache, no-store";
            context.Response.Headers.Pragma = "no-cache";
            context.Response.Headers["Referrer-Policy"] = "no-referrer";
            context.Response.Headers["X-Content-Type-Options"] = "nosniff";
            context.Response.Headers.ContentSecurityPolicy = "default-src 'none'; style-src 'self'; script-src 'self'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'";
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
        try
        {
            if (!app.Environment.IsEnvironment("Testing"))
            {
                await using var scope = app.Services.CreateAsyncScope();
                var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
                var cancellationToken = app.Lifetime.ApplicationStopping;
                // Блокировка живёт на отдельном непулируемом соединении: EF может менять
                // свои транзакции/соединения, а весь startup остаётся последовательным.
                var startupSettings = new NpgsqlConnectionStringBuilder(database.Database.GetConnectionString())
                {
                    Pooling = false,
                    ApplicationName = "FitLife startup"
                };
                await using var startupConnection = new NpgsqlConnection(startupSettings.ConnectionString);
                await startupConnection.OpenAsync(cancellationToken);
                await using var startupLock = new NpgsqlCommand("SELECT pg_advisory_lock(447295635001)", startupConnection);
                await startupLock.ExecuteNonQueryAsync(cancellationToken);
                // Обычный запуск обновляет схему до открытия HTTP listener.
                if (!args.Contains("--configure-clients") || args.Contains("--migrate"))
                {
                    // Npgsql обнаруживает отсутствие history через SQL exception.
                    // Штатное создание таблицы заранее исключает ложный CommandError при первом запуске.
                    await database.GetService<IHistoryRepository>().CreateIfNotExistsAsync(cancellationToken);
                    await database.Database.MigrateAsync(cancellationToken);
                }
                await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
                await AuthConfiguration.RegisterClient(scope.ServiceProvider, config, cancellationToken);
                await transaction.CommitAsync(cancellationToken);
                if (args.Contains("--migrate") || args.Contains("--configure-clients")) return;
            }
        }
        catch (Exception exception)
        {
            app.Logger.LogCritical(exception, "Authentication database/client startup failed.");
            throw;
        }
        await app.RunAsync();
    }
}
