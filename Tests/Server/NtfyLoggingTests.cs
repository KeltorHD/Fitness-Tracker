using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using FitnessTracker.ServerLogging;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет ntfy без сети, внешних topics, секретов и фиксированных задержек.</summary>
[Trait("Category", "Unit")]
public sealed class NtfyLoggingTests
{
    private const string ACCESS_TOKEN = "tk_synthetic_ntfy_token_1234567890";

    /// <summary>Доставляет только выбранный уровень и более важные; None полностью отключает transport.</summary>
    [Theory]
    [InlineData(LogLevel.Trace, 6)]
    [InlineData(LogLevel.Debug, 5)]
    [InlineData(LogLevel.Information, 4)]
    [InlineData(LogLevel.Warning, 3)]
    [InlineData(LogLevel.Error, 2)]
    [InlineData(LogLevel.Critical, 1)]
    [InlineData(LogLevel.None, 0)]
    public async Task FiltersMinimumLevelBeforeFormattingAsync(LogLevel minimum, int expected)
    {
        using var handler = new CaptureHandler();
        var config = Configuration(minimum);
        await using var provider = Create(handler, config);
        var logger = provider.CreateLogger("Example.Service");
        foreach (var level in new[] { LogLevel.Trace, LogLevel.Debug, LogLevel.Information, LogLevel.Warning, LogLevel.Error, LogLevel.Critical, LogLevel.None })
            logger.Log(level, new EventId(42), "event", null, (state, _) => state);
        var formatted = false;
        logger.Log(LogLevel.Trace, default, "filtered", null, (state, _) => { formatted = true; return state; });
        Assert.Equal(minimum == LogLevel.Trace, formatted);
        provider.Start();
        await provider.DisposeAsync();
        Assert.Equal(expected + (minimum == LogLevel.Trace ? 1 : 0), handler.Messages.Count);
    }

    /// <summary>JSON POST использует root URL, UTF-8, bearer header и приоритет по серьёзности.</summary>
    [Fact]
    public async Task PublishesUnicodeMessageAndExceptionWithMetadataAsync()
    {
        using var handler = new CaptureHandler();
        await using var provider = Create(handler, Configuration());
        provider.CreateLogger("Example.Database").LogError(new EventId(27),
            new InvalidOperationException("Database unavailable"), "Ошибка соединения, status {Status}", 503);
        provider.Start();
        await provider.DisposeAsync();

        var sent = Assert.Single(handler.Messages);
        Assert.Equal("https://ntfy.example.com/", sent.Url);
        Assert.Equal("Bearer " + ACCESS_TOKEN, sent.Authorization);
        Assert.Equal("application/json", sent.ContentType);
        using var document = JsonDocument.Parse(sent.Body);
        Assert.Equal("private-fixture-topic", document.RootElement.GetProperty("topic").GetString());
        Assert.Equal("FitnessTracker Backend: Error", document.RootElement.GetProperty("title").GetString());
        Assert.Equal(4, document.RootElement.GetProperty("priority").GetInt32());
        var message = document.RootElement.GetProperty("message").GetString()!;
        Assert.Contains("Ошибка соединения, status 503", message);
        Assert.Contains("Example.Database / Event 27", message);
        Assert.Contains("InvalidOperationException: Database unavailable", message);
    }

    /// <summary>Тексты и exceptions маскируются до отправки; scopes не включаются.</summary>
    [Fact]
    public async Task MasksConfiguredAndDynamicSecretsWithoutLosingUsefulMessageAsync()
    {
        using var handler = new CaptureHandler();
        var config = Configuration(extra: new Dictionary<string, string?> { ["Smtp:Password"] = "configured-mail-secret" });
        await using var provider = Create(handler, config);
        var logger = provider.CreateLogger("Example.Service");
        using var scope = logger.BeginScope("scope-private-person");
        logger.LogError(new Exception("password=dynamic-exception-secret; https://user:uri-secret@example.com/callback?code=callback-secret"),
            "Delivery failed: password {Password}, bearer {Authorization}, email {Email}, smtp configured-mail-secret; status {Status}",
            "dynamic-password-secret", "Bearer dynamic-bearer-secret", "private@example.com", 503);
        provider.Start();
        await provider.DisposeAsync();
        var text = Assert.Single(handler.Messages).Body;
        foreach (var secret in new[] { "dynamic-exception-secret", "uri-secret", "callback-secret", "configured-mail-secret",
            "dynamic-password-secret", "dynamic-bearer-secret", "private@example.com", "scope-private-person", ACCESS_TOKEN })
            Assert.DoesNotContain(secret, text);
        using var document = JsonDocument.Parse(text);
        Assert.Contains("Delivery failed", document.RootElement.GetProperty("message").GetString());
        Assert.Contains("503", document.RootElement.GetProperty("message").GetString());
    }

    /// <summary>Переполнение не ждёт сеть; сохраняются только первый и помещённый в очередь запросы.</summary>
    [Fact(Timeout = 10_000)]
    public async Task QueueOverflowDoesNotBlockLogCallsAsync()
    {
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var handler = new CaptureHandler(async cancellationToken =>
        {
            started.TrySetResult();
            await release.Task.WaitAsync(cancellationToken);
            return new(HttpStatusCode.OK);
        });
        await using var provider = Create(handler, Configuration(extra: new() { ["Ntfy:QueueCapacity"] = "1" }));
        provider.Start();
        var logger = provider.CreateLogger("Example.Service");
        logger.LogError("first-in-flight");
        await started.Task;
        logger.LogError("second-queued");
        logger.LogError("third-dropped");
        logger.LogError("fourth-dropped");
        release.SetResult();
        await provider.DisposeAsync();
        Assert.Equal(2, handler.Messages.Count);
        Assert.DoesNotContain(handler.Messages, message => message.Body.Contains("dropped", StringComparison.Ordinal));
    }

    /// <summary>После HTTP-ошибки/redirect нет немедленного retry или шторма из уже накопленных записей.</summary>
    [Theory]
    [InlineData(HttpStatusCode.Redirect)]
    [InlineData(HttpStatusCode.Unauthorized)]
    [InlineData(HttpStatusCode.TooManyRequests)]
    [InlineData(HttpStatusCode.ServiceUnavailable)]
    public async Task FailureHasCooldownAndDoesNotRecurseAsync(HttpStatusCode failure)
    {
        var clock = new MutableClock();
        var calls = 0;
        using var handler = new CaptureHandler(_ =>
        {
            var response = new HttpResponseMessage(++calls == 1 ? failure : HttpStatusCode.OK);
            response.Headers.Location = new Uri("https://attacker.example.com/");
            return Task.FromResult(response);
        });
        await using var provider = Create(handler, Configuration(), clock);
        provider.CreateLogger("Example.Service").LogError("first");
        provider.CreateLogger("Example.Service").LogError("suppressed-during-cooldown");
        provider.Start();
        // Завершение worker и отсутствие повторов проверяются без ожидания реальных 30 секунд.
        await provider.DisposeAsync();
        Assert.Single(handler.Messages);
        Assert.Equal(1, calls);
        Assert.DoesNotContain("attacker", handler.Messages[0].Url);
        Assert.False(provider.CreateLogger("FitnessTracker.ServerLogging.Ntfy").IsEnabled(LogLevel.Critical));
    }

    /// <summary>Clock advance восстанавливает доставку без повторной отправки потерянной записи.</summary>
    [Fact]
    public async Task RecoversAfterCooldownWithoutRetryingFailedMessageAsync()
    {
        var failed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var clock = new MutableClock();
        var count = 0;
        using var handler = new CaptureHandler(_ => Task.FromResult(new HttpResponseMessage(
            ++count == 1 ? HttpStatusCode.ServiceUnavailable : HttpStatusCode.OK)));
        var diagnostics = new SignalLogger(() => failed.TrySetResult());
        await using var provider = new NtfyLoggerProvider(NtfyOptions.Read(Configuration()), new(Configuration()), clock,
            "Backend", () => (new HttpClient(handler, disposeHandler: false), diagnostics));
        provider.Start();
        var logger = provider.CreateLogger("Example.Service");
        logger.LogError("failed-first");
        await failed.Task;
        clock.Advance(TimeSpan.FromSeconds(31));
        logger.LogError("recovered-second");
        await provider.DisposeAsync();
        Assert.Equal(2, handler.Messages.Count);
        Assert.Contains("failed-first", handler.Messages[0].Body);
        Assert.Contains("recovered-second", handler.Messages[1].Body);
    }

    /// <summary>Стандартный environment provider преобразует Ntfy__* в options без изменения общих env keys.</summary>
    [Fact]
    public void ReadsEnvironmentVariablesWithDoubleUnderscores()
    {
        var prefix = "FITNESS_NTFY_TEST_" + Guid.NewGuid().ToString("N") + "_";
        var variables = new Dictionary<string, string>
        {
            ["Ntfy__Enabled"] = "true",
            ["Ntfy__ServerUrl"] = "https://ntfy.example.com/",
            ["Ntfy__Topic"] = "fixture-only",
            ["Ntfy__MinimumLevel"] = "Error",
            ["Ntfy__TimeoutSeconds"] = "2"
        };
        try
        {
            foreach (var item in variables) Environment.SetEnvironmentVariable(prefix + item.Key, item.Value);
            var config = new ConfigurationBuilder().AddEnvironmentVariables(prefix).Build();
            var options = NtfyOptions.Read(config);
            Assert.Equal(LogLevel.Error, options.MinimumLevel);
            Assert.Equal(2, options.TimeoutSeconds);
            Assert.Equal("fixture-only", options.Topic);
        }
        finally
        {
            foreach (var key in variables.Keys) Environment.SetEnvironmentVariable(prefix + key, null);
        }
    }

    /// <summary>Небезопасные URL, неверные уровни и параметры очереди/headers отклоняются до отправки.</summary>
    [Theory]
    [InlineData("Ntfy:ServerUrl", "http://ntfy.example.com/")]
    [InlineData("Ntfy:ServerUrl", "https://private-marker@ntfy.example.com/")]
    [InlineData("Ntfy:ServerUrl", "https://ntfy.example.com/?token=private-marker")]
    [InlineData("Ntfy:ServerUrl", "https://ntfy.example.com/#private-marker")]
    [InlineData("Ntfy:Topic", "with space")]
    [InlineData("Ntfy:MinimumLevel", "7")]
    [InlineData("Ntfy:QueueCapacity", "0")]
    [InlineData("Ntfy:TimeoutSeconds", "31")]
    [InlineData("Ntfy:Token", "private-marker\r\nAuthorization: injected")]
    public void RejectsInvalidConfigurationWithoutLeakingValue(string key, string value)
    {
        var exception = Assert.Throws<InvalidOperationException>(() => NtfyOptions.Read(Configuration(extra: new() { [key] = value })));
        Assert.DoesNotContain("private-marker", exception.ToString());
    }

    /// <summary>Порог ntfy независим от console/category filters, а повторный Start не создаёт второй worker.</summary>
    [Fact]
    public async Task IntegratesWithLoggerFactoryAndIndependentFilterAsync()
    {
        using var handler = new CaptureHandler();
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(Configuration(LogLevel.Debug));
        services.AddLogging(logging => logging.SetMinimumLevel(LogLevel.Critical)
            .AddFilter("Microsoft", LogLevel.Critical).AddNtfy("Authentication"));
        services.AddHttpClient("FitnessTracker.Ntfy").ConfigurePrimaryHttpMessageHandler(() => handler);
        await using var container = services.BuildServiceProvider();
        await using var lifetime = container.StartNtfyLogging();
        await container.GetRequiredService<NtfyLoggerProvider>().StartAsync(default);
        var logger = container.GetRequiredService<ILoggerFactory>().CreateLogger("Microsoft.Example");
        Assert.True(logger.IsEnabled(LogLevel.Debug));
        logger.LogDebug("ntfy-debug-with-console-critical");
        await lifetime.DisposeAsync();
        Assert.Single(handler.Messages);
        Assert.Contains("Authentication", handler.Messages[0].Body);
    }

    /// <summary>Verbose protocol/form события не вызывают formatter, который может раскрыть произвольный payload.</summary>
    [Fact]
    public async Task SensitiveFrameworkDetailsAreNotFormattedAsync()
    {
        using var handler = new CaptureHandler();
        await using var provider = Create(handler, Configuration(LogLevel.Trace));
        foreach (var category in new[] { "OpenIddict.Server", "Microsoft.AspNetCore.Mvc.ModelBinding.Test", "Microsoft.AspNetCore.HttpLogging.HttpLoggingMiddleware" })
            provider.CreateLogger(category).Log(LogLevel.Debug, new EventId(7), "opaque-private-payload", null,
                (_, _) => throw new InvalidOperationException("Sensitive formatter must not run"));
        provider.Start();
        await provider.DisposeAsync();
        Assert.Equal(3, handler.Messages.Count);
        Assert.All(handler.Messages, item =>
        {
            Assert.Contains("Sensitive protocol/form details omitted", item.Body);
            Assert.DoesNotContain("opaque-private-payload", item.Body);
            Assert.DoesNotContain("formatting/redaction failed", item.Body);
        });
    }

    /// <summary>Disabled и None не создают HttpClient, не форматируют и не выполняют I/O.</summary>
    [Theory]
    [InlineData(false, LogLevel.Warning)]
    [InlineData(true, LogLevel.None)]
    public async Task DisabledDoesNotCreateTransportAsync(bool enabled, LogLevel level)
    {
        var config = Configuration(level, new() { ["Ntfy:Enabled"] = enabled.ToString() });
        await using var provider = new NtfyLoggerProvider(NtfyOptions.Read(config), new(config), TimeProvider.System,
            "Backend", () => throw new InvalidOperationException("Transport must not be created"));
        provider.Start();
        provider.CreateLogger("Example.Service").LogCritical("not-sent");
    }

    /// <summary>Слишком большой текст ограничивается по UTF-8 без повреждения Unicode и без raw payload.</summary>
    [Fact]
    public async Task BoundsUnicodeAndSuppressesArchivePayloadsAsync()
    {
        using var handler = new CaptureHandler();
        await using var provider = Create(handler, Configuration());
        var logger = provider.CreateLogger("Example.Service");
        logger.LogError("{Text}", string.Concat(Enumerable.Repeat("Тренировка🏋️", 1_000)));
        logger.LogError("{Body}", "{\"workouts\":[{\"notes\":\"private-health-record\"}]}");
        provider.Start();
        await provider.DisposeAsync();
        Assert.Equal(2, handler.Messages.Count);
        foreach (var sent in handler.Messages)
        {
            using var json = JsonDocument.Parse(sent.Body);
            var message = json.RootElement.GetProperty("message").GetString()!;
            Assert.True(Encoding.UTF8.GetByteCount(message) <= 3_000);
            Assert.DoesNotContain('\uFFFD', message);
            Assert.DoesNotContain("private-health-record", message);
        }
    }

    /// <summary>Создаёт настройки только синтетического HTTPS topic, без обращения к сети.</summary>
    private static IConfiguration Configuration(LogLevel minimum = LogLevel.Warning, Dictionary<string, string?>? extra = null)
    {
        var values = new Dictionary<string, string?>
        {
            ["Ntfy:Enabled"] = "true",
            ["Ntfy:ServerUrl"] = "https://ntfy.example.com/",
            ["Ntfy:Topic"] = "private-fixture-topic",
            ["Ntfy:Token"] = ACCESS_TOKEN,
            ["Ntfy:MinimumLevel"] = minimum.ToString()
        };
        if (extra is not null) foreach (var pair in extra) values[pair.Key] = pair.Value;
        return new ConfigurationBuilder().AddInMemoryCollection(values).Build();
    }

    /// <summary>Создаёт экземпляр со штатным redactor, подменяя только HTTP и часы.</summary>
    private static NtfyLoggerProvider Create(CaptureHandler handler, IConfiguration config, TimeProvider? clock = null) =>
        new(NtfyOptions.Read(config), new(config), clock ?? TimeProvider.System, "Backend",
            () => (new HttpClient(handler, disposeHandler: false), NullLogger.Instance));

    /// <summary>Сохраняет синтетический запрос до освобождения HttpRequestMessage.</summary>
    private sealed class CaptureHandler(Func<CancellationToken, Task<HttpResponseMessage>>? response = null) : HttpMessageHandler
    {
        /// <summary>Записи читаются только после завершения worker.</summary>
        internal List<SentMessage> Messages { get; } = [];
        /// <summary>Не открывает соединений; может управляемо задержать или отклонить запрос.</summary>
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Assert.Equal(HttpMethod.Post, request.Method);
            Messages.Add(new(request.RequestUri!.AbsoluteUri, request.Headers.Authorization?.ToString(),
                request.Content?.Headers.ContentType?.MediaType, await request.Content!.ReadAsStringAsync(cancellationToken)));
            return response is null ? new(HttpStatusCode.OK) : await response(cancellationToken);
        }
    }

    /// <summary>Не содержит рабочих credentials или ответов внешнего ntfy.</summary>
    private sealed record SentMessage(string Url, string? Authorization, string? ContentType, string Body);

    /// <summary>Позволяет управлять cooldown без реальных задержек.</summary>
    private sealed class MutableClock : TimeProvider
    {
        private DateTimeOffset _now = new(2026, 11, 7, 12, 0, 0, TimeSpan.Zero);
        /// <summary>Фиксированное время сценария.</summary>
        public override DateTimeOffset GetUtcNow() => _now;
        /// <summary>Сдвигает время до следующей попытки после завершённого отказа.</summary>
        internal void Advance(TimeSpan value) => _now += value;
    }

    /// <summary>Сигнализирует о завершённом отказе transport без ожидания по таймеру.</summary>
    private sealed class SignalLogger(Action signal) : ILogger
    {
        /// <summary>Не сохраняет scopes теста.</summary>
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        /// <summary>Принимает диагностические события провайдера.</summary>
        public bool IsEnabled(LogLevel level) => true;
        /// <summary>Уведомляет тест после установки cooldown в worker.</summary>
        public void Log<TState>(LogLevel level, EventId id, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter) => signal();
    }
}
