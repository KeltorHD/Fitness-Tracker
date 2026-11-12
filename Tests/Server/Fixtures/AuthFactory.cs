using System.Net;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;
using FitnessTracker.Authentication;

namespace FitnessTracker.Server.Tests;

/// <summary>Изолирует Identity/OpenIddict и подменяет только внешний HTTP-сервис удаления копий.</summary>
/// <param name="peerAddress">Сетевой адрес непосредственного отправителя для проверки reverse proxy.</param>
/// <param name="trustedProxy">Единственный дополнительно доверенный proxy в тестовой конфигурации.</param>
/// <param name="claimsTransformation">Необязательная точка синхронизации после проверки cookie для тестов гонок.</param>
/// <param name="appleAppIdentifier">Синтетическая привязка приложения для тестирования AASA без настоящего Apple аккаунта.</param>
/// <param name="providerSettings">Синтетические настройки провайдеров для проверки доступности кнопок без внешних запросов.</param>
/// <param name="personalCallbackScheme">Необязательная URL-схема отдельного Personal Team client.</param>
/// <param name="clock">Управляемое время для ограничений повторной отправки.</param>
public sealed class AuthFactory(IPAddress? peerAddress = null, string? trustedProxy = null,
    IClaimsTransformation? claimsTransformation = null, string? appleAppIdentifier = null,
    IReadOnlyDictionary<string, string?>? providerSettings = null, string? personalCallbackScheme = null,
    TimeProvider? clock = null) : WebApplicationFactory<Authentication.Program>
{
    /// <summary>Синтетический секрет отдельного confidential client в изолированной Auth-БД.</summary>
    internal const string IntrospectionSecret = "test-introspection-secret-with-at-least-32-characters";
    private readonly SqliteConnection _connection = new("Data Source=:memory:");
    /// <summary>Количество реальных обращений Auth к подменённому Backend.</summary>
    internal int CleanupCalls;
    /// <summary>Включает отказ внешней очистки без изменения состояния Identity.</summary>
    internal bool CleanupFails;
    /// <summary>Изолированный outbox вместо реальной отправки писем.</summary>
    internal TestEmailSender EmailSender { get; } = new();

    /// <summary>Отключает пользовательские настройки, реальные provider registrations и рабочую БД.</summary>
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        _connection.Open();
        builder.UseEnvironment("Testing");
        // Minimal hosting читает часть настроек до ConfigureAppConfiguration.
        builder.UseSetting("Auth:Issuer", "https://localhost/");
        builder.UseSetting("Providers:Google:Enabled", "false");
        builder.UseSetting("Providers:Apple:Enabled", "false");
        builder.UseSetting("Providers:Yandex:Enabled", "false");
        if (providerSettings is not null)
            foreach (var setting in providerSettings) builder.UseSetting(setting.Key, setting.Value);
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.Sources.Clear();
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Auth:Issuer"] = "https://localhost/",
                ["Smtp:Enabled"] = "true",
                ["Smtp:Host"] = "smtp.example.com",
                ["Smtp:FromAddress"] = "fitness@example.com",
                ["Auth:IntrospectionClientSecret"] = IntrospectionSecret,
                ["Auth:AppleAppIdentifier"] = appleAppIdentifier,
                ["Auth:PersonalCallbackScheme"] = personalCallbackScheme,
                ["Backend:InternalUrl"] = "https://backend.test/",
                ["Backend:ServiceKey"] = BackendFactory.ServiceKey,
                ["ReverseProxy:Address"] = trustedProxy,
                ["AllowedHosts"] = "localhost",
                ["Logging:LogLevel:Default"] = "None"
            });
            if (providerSettings is not null) config.AddInMemoryCollection(providerSettings);
        });
        builder.ConfigureServices(services =>
        {
            if (clock is not null) services.AddSingleton(clock);
            if (peerAddress is not null)
                services.AddSingleton<IStartupFilter>(new PeerAddressStartupFilter(peerAddress));
            if (claimsTransformation is not null)
                services.AddSingleton(claimsTransformation);
            services.RemoveAll<DbContextOptions<AuthDbContext>>();
            services.RemoveAll<IAccountEmailSender>();
            services.AddSingleton<IAccountEmailSender>(EmailSender);
            services.RemoveAll<IDbContextOptionsConfiguration<AuthDbContext>>();
            services.AddDbContext<AuthDbContext>(options => options
                .UseSqlite(_connection)
                .UseOpenIddict()
                .ReplaceService<IModelCustomizer, AuthSqliteModelCustomizer>());
            services.AddHttpClient<BackupCleanup>().ConfigurePrimaryHttpMessageHandler(() => new CleanupHandler(this));
        });
    }

    /// <summary>Только SQLite fixture хранит CreatedAt как UTC DateTime для сравнения сроков; PostgreSQL проверяется отдельно.</summary>
    private sealed class AuthSqliteModelCustomizer(ModelCustomizerDependencies dependencies) : RelationalModelCustomizer(dependencies)
    {
        /// <summary>Обходит отсутствие SQL-сравнения DateTimeOffset у SQLite без изменения production-модели.</summary>
        public override void Customize(ModelBuilder modelBuilder, DbContext context)
        {
            base.Customize(modelBuilder, context);
            modelBuilder.UseOpenIddict();
            modelBuilder.Entity<ApplicationUser>().Property(user => user.CreatedAt).HasConversion(
                value => value.UtcDateTime,
                value => new DateTimeOffset(DateTime.SpecifyKind(value, DateTimeKind.Utc)));
        }
    }

    /// <summary>Подставляет реальный TCP peer до production middleware обработки forwarded headers.</summary>
    private sealed class PeerAddressStartupFilter(IPAddress address) : IStartupFilter
    {
        /// <summary>Сохраняет остальной pipeline приложения, меняя только сетевое окружение запроса.</summary>
        public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next) => app =>
        {
            app.Use(nextMiddleware => context =>
            {
                context.Connection.RemoteIpAddress = address;
                return nextMiddleware(context);
            });
            next(app);
        };
    }

    /// <summary>Создаёт отдельного пользователя и защищённый Identity cookie без обращения к OAuth-провайдеру.</summary>
    internal async Task<HttpClient> SignedInAsync(CancellationToken cancellationToken = default)
    {
        var client = CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost"), AllowAutoRedirect = false });
        try
        {
            using var scope = Services.CreateScope();
            await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Database.EnsureCreatedAsync(cancellationToken);
            await AuthConfiguration.RegisterClient(scope.ServiceProvider, scope.ServiceProvider.GetRequiredService<IConfiguration>());
            var manager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var user = new ApplicationUser { Id = Guid.NewGuid().ToString(), UserName = Guid.NewGuid().ToString("N"), DisplayName = "Test" };
            var created = await manager.CreateAsync(user);
            if (!created.Succeeded) throw new InvalidOperationException("Cannot create the isolated Identity fixture.");
            var principal = await scope.ServiceProvider.GetRequiredService<SignInManager<ApplicationUser>>().CreateUserPrincipalAsync(user);
            var options = scope.ServiceProvider.GetRequiredService<IOptionsMonitor<CookieAuthenticationOptions>>().Get(IdentityConstants.ApplicationScheme);
            var ticket = options.TicketDataFormat.Protect(new AuthenticationTicket(principal, new AuthenticationProperties
            { IssuedUtc = DateTimeOffset.UtcNow, ExpiresUtc = DateTimeOffset.UtcNow.AddHours(1) }, IdentityConstants.ApplicationScheme));
            client.DefaultRequestHeaders.Add("Cookie", $"{options.Cookie.Name}={ticket}");
            return client;
        }
        catch { client.Dispose(); throw; }
    }

    /// <summary>Возвращает контролируемый ответ Backend и проверяет служебный credential исходящего запроса.</summary>
    private sealed class CleanupHandler(AuthFactory owner) : HttpMessageHandler
    {
        /// <summary>Учитывает отмену и имитирует успешное удаление либо недоступность Backend.</summary>
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (request.Headers.GetValues("X-Service-Key").Single() != BackendFactory.ServiceKey)
                throw new InvalidOperationException("Incorrect service credential in fixture request.");
            Interlocked.Increment(ref owner.CleanupCalls);
            return Task.FromResult(new HttpResponseMessage(owner.CleanupFails ? HttpStatusCode.ServiceUnavailable : HttpStatusCode.NoContent));
        }
    }

    /// <summary>Закрывает SQLite даже при ошибке завершения host.</summary>
    protected override void Dispose(bool disposing)
    {
        try { base.Dispose(disposing); }
        finally { if (disposing) _connection.Dispose(); }
    }
}
