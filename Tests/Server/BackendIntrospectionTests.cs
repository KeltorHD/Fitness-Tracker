using System.Net;
using System.Net.Http.Json;
using FitLife.Backend;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.Extensions.Configuration;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Logging;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет fail-closed поведение настоящего Backend до чтения и изменения копий.</summary>
[Trait("Category", "HTTP")]
public sealed class BackendIntrospectionTests
{
    /// <summary>Каждый запрос сверяет статус, а успешно проверенный JWT не остаётся активным в кеше Backend.</summary>
    [Fact]
    public async Task RechecksActiveTokenAndStopsRevokedWritesAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        using var allowed = await client.GetAsync("/v1/backups");
        Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        Assert.Equal(1, factory.Introspection.Calls);

        factory.Introspection.Active = false;
        using var read = await client.GetAsync("/v1/backups");
        using var write = await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", new StringContent("{}"));

        Assert.Equal(HttpStatusCode.Unauthorized, read.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, write.StatusCode);
        Assert.Equal(3, factory.Introspection.Calls);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<BackupDbContext>().Backups.ToListAsync());
    }

    /// <summary>Auth outage/credentials/JSON возвращают 503 без записи; восстановление работает с тем же JWT.</summary>
    [Theory]
    [InlineData("status")]
    [InlineData("credentials")]
    [InlineData("transport")]
    [InlineData("timeout")]
    [InlineData("malformed")]
    public async Task ReturnsServiceUnavailableWithoutConsumingCredentialsAsync(string failure)
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        factory.Introspection.Respond = (_, _) => failure switch
        {
            "transport" => throw new HttpRequestException("private-outage-marker"),
            "timeout" => throw new OperationCanceledException(),
            _ => Task.FromResult(new HttpResponseMessage(failure == "credentials" ? HttpStatusCode.Unauthorized :
                failure == "status" ? HttpStatusCode.ServiceUnavailable : HttpStatusCode.OK)
            { Content = new StringContent("private-outage-marker") })
        };

        using var response = await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", new StringContent("{}"));

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<System.Text.Json.JsonElement>();
        Assert.Equal("authentication_unavailable", body.GetProperty("code").GetString());
        Assert.DoesNotContain("private-outage-marker", await response.Content.ReadAsStringAsync());
        Assert.Empty(response.Headers.WwwAuthenticate);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<BackupDbContext>().Backups.ToListAsync());
        factory.Introspection.Respond = null;
        using var retry = await client.GetAsync("/v1/backups");
        Assert.Equal(HttpStatusCode.OK, retry.StatusCode);
    }

    /// <summary>Ошибка получения discovery/JWKS также даёт 503 вместо требования повторного входа.</summary>
    [Fact]
    public async Task DiscoveryFailureReturnsServiceUnavailableAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        factory.Services.GetRequiredService<IOptionsMonitor<JwtBearerOptions>>().Get(JwtBearerDefaults.AuthenticationScheme)
            .ConfigurationManager = new UnavailableConfiguration();

        using var response = await client.GetAsync("/v1/backups");

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(0, factory.Introspection.Calls);
    }

    /// <summary>Отказ по квоте запросов не создаёт лишние обращения к Auth.</summary>
    [Fact]
    public async Task AppliesRateLimitBeforeIntrospectionAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        for (var index = 0; index < 30; index++)
        {
            using var response = await client.GetAsync("/v1/backups");
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }

        using var limited = await client.GetAsync("/v1/backups");

        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
        Assert.Equal(30, factory.Introspection.Calls);
    }

    /// <summary>Недостающий секрет и небезопасный issuer не позволяют запустить Backend с отключённой проверкой.</summary>
    [Theory]
    [InlineData("Auth:IntrospectionClientSecret", "")]
    [InlineData("Auth:IntrospectionClientSecret", "short")]
    [InlineData("Auth:Issuer", "http://auth.test/")]
    [InlineData("Auth:Issuer", "https://user:super-secret-marker@auth.test/")]
    [InlineData("Auth:Issuer", "https://auth.test/subpath/")]
    public void RejectsUnsafeConfigurationAtStartup(string key, string value)
    {
        using var factory = new BackendFactory();
        using var startupLog = new StartupValidationLog();
        using var configured = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureAppConfiguration((_, config) =>
                config.AddInMemoryCollection(new Dictionary<string, string?> { [key] = value }));
            builder.ConfigureLogging(logging => logging
                .AddProvider(startupLog)
                .AddFilter<StartupValidationLog>(null, LogLevel.Error));
        });

        var failure = Record.Exception(() => configured.CreateClient());
        // RunAsync освобождает host при ошибке; DeferredHost иногда замечает disposal раньше исходного исключения.
        var error = Assert.IsType<OptionsValidationException>(
            failure is ObjectDisposedException ? startupLog.Error : failure);

        Assert.Same(startupLog.Error, error);
        Assert.Equal(typeof(IntrospectionOptions), error.OptionsType);
        Assert.Contains(error.Failures, message => message.StartsWith(key + " ", StringComparison.Ordinal));
        Assert.DoesNotContain("super-secret-marker", error.ToString());
        Assert.Equal(0, factory.Introspection.Calls);
    }

    /// <summary>Сохраняет исходную ошибку startup, когда тестовая фабрика видит уже освобождённый host.</summary>
    private sealed class StartupValidationLog : ILoggerProvider, ILogger
    {
        private OptionsValidationException? _error;

        /// <summary>Возвращает первую ошибку валидации, опубликованную потоком запуска приложения.</summary>
        internal OptionsValidationException? Error => Volatile.Read(ref _error);

        /// <summary>Принимает startup-ошибки без вывода конфигурации или сообщений в журнал тестов.</summary>
        public ILogger CreateLogger(string categoryName) => this;

        /// <summary>Для сохранения исключения дополнительные logging scopes не требуются.</summary>
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        /// <summary>Слушает только сообщения уровня ошибки и выше.</summary>
        public bool IsEnabled(LogLevel logLevel) => logLevel >= LogLevel.Error;

        /// <summary>Атомарно сохраняет исходный тип ошибки, не форматируя потенциально приватное сообщение.</summary>
        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            if (exception is OptionsValidationException error)
                Interlocked.CompareExchange(ref _error, error, null);
        }

        /// <summary>Провайдер хранит только ссылку на исключение и не владеет внешними ресурсами.</summary>
        public void Dispose() { }
    }

    /// <summary>Недоступная metadata-зависимость без сетевого запроса.</summary>
    private sealed class UnavailableConfiguration : IConfigurationManager<OpenIdConnectConfiguration>
    {
        /// <summary>Имитирует ошибку discovery до проверки подписи токена.</summary>
        public Task<OpenIdConnectConfiguration> GetConfigurationAsync(CancellationToken cancellationToken) =>
            throw new HttpRequestException("Synthetic discovery outage.");

        /// <summary>В тесте обновление также не обращается к внешнему серверу.</summary>
        public void RequestRefresh() { }
    }
}
