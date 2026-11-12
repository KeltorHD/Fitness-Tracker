using System.Net.Http.Headers;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Threading.Channels;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace FitLife.ServerLogging;

/// <summary>Не блокирует запросы: маскирует логи и доставляет ограниченную очередь одним HTTP worker.</summary>
[ProviderAlias("Ntfy")]
public sealed class NtfyLoggerProvider : ILoggerProvider, IHostedService, IAsyncDisposable
{
    private static readonly JsonSerializerOptions _json = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
    private readonly NtfyOptions _options;
    private readonly NtfyLogRedactor _redactor;
    private readonly TimeProvider _clock;
    private readonly string _serviceName;
    private readonly Func<(HttpClient Client, ILogger Diagnostics)> _transport;
    private readonly Channel<Notification> _queue;
    private readonly CancellationTokenSource _abort = new();
    private readonly object _gate = new();
    private Task? _worker;
    private Task? _shutdown;
    private HttpClient? _client;
    private ILogger? _diagnostics;
    private long _dropped;
    private int _completed;

    /// <summary>Создаёт очередь без HTTP/LoggerFactory, избегая циклического разрешения ILoggerProvider.</summary>
    internal NtfyLoggerProvider(NtfyOptions options, NtfyLogRedactor redactor, TimeProvider clock,
        string serviceName, Func<(HttpClient Client, ILogger Diagnostics)> transport)
    {
        options.Validate();
        _options = options;
        _redactor = redactor;
        _clock = clock;
        _serviceName = serviceName;
        _transport = transport;
        _queue = Channel.CreateBounded<Notification>(new BoundedChannelOptions(options.QueueCapacity)
        { SingleReader = true, AllowSynchronousContinuations = false, FullMode = BoundedChannelFullMode.Wait });
    }

    /// <summary>Создаёт стандартный ILogger; scope values не отправляются.</summary>
    public ILogger CreateLogger(string categoryName) => new NtfyLogger(this, categoryName);

    /// <summary>Идемпотентно запускает worker после готовности DI, включая ранний startup до миграций.</summary>
    internal void Start()
    {
        lock (_gate)
        {
            if (_worker is not null || _completed != 0 || !_options.Enabled || _options.MinimumLevel == LogLevel.None) return;
            (_client, _diagnostics) = _transport();
            _worker = SendAsync();
        }
    }

    /// <summary>Повторный host start не создаёт второй worker.</summary>
    public Task StartAsync(CancellationToken cancellationToken) { Start(); return Task.CompletedTask; }

    /// <summary>Завершает очередь до освобождения DI/HttpClientFactory.</summary>
    public async Task StopAsync(CancellationToken cancellationToken) =>
        await DisposeAsync().AsTask().WaitAsync(cancellationToken);

    /// <summary>ILoggerFactory начинает неблокирующий shutdown; host/root scope ожидает DisposeAsync.</summary>
    public void Dispose() => _ = DisposeAsync();

    /// <summary>Даёт очереди до пяти секунд, затем отменяет только собственный HTTP worker.</summary>
    public ValueTask DisposeAsync()
    {
        lock (_gate) return new(_shutdown ??= ShutdownAsync());
    }

    /// <summary>Фильтрует до formatter, включая собственные диагностические сообщения.</summary>
    private bool IsEnabled(string category, LogLevel level) => _options.Enabled &&
        _completed == 0 && level >= _options.MinimumLevel && level < LogLevel.None &&
        !category.StartsWith("FitLife.ServerLogging", StringComparison.Ordinal);

    /// <summary>Маскирует до очереди; TryWrite никогда не ожидает свободного места или сеть.</summary>
    private void Write<TState>(string category, LogLevel level, EventId id, TState state, Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        if (!IsEnabled(category, level)) return;
        string message;
        try
        {
            // Эти framework diagnostics могут содержать произвольные protocol/form payloads.
            var sensitiveProtocol = level < LogLevel.Warning &&
                (category.StartsWith("OpenIddict", StringComparison.Ordinal) ||
                 category.StartsWith("Microsoft.AspNetCore.Mvc.ModelBinding", StringComparison.Ordinal) ||
                 category.StartsWith("Microsoft.AspNetCore.HttpLogging", StringComparison.Ordinal));
            message = sensitiveProtocol ? "[Sensitive protocol/form details omitted]" : _redactor.Redact(formatter(state, exception), state);
            if (exception is not null)
                message += "\n" + (sensitiveProtocol ? exception.GetType().FullName : _redactor.Redact(exception.ToString()));
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            message = "[Log formatting/redaction failed]";
        }
        var text = $"{_clock.GetUtcNow():O}\n{_redactor.Redact(category)} / Event {id.Id}\n{message}";
        if (!_queue.Writer.TryWrite(new(level, LimitUtf8(text, 3_000)))) Interlocked.Increment(ref _dropped);
    }

    /// <summary>Отправляет один раз; после отказа на 30 секунд подавляет новые попытки против недоступного ntfy.</summary>
    private async Task SendAsync()
    {
        var nextAttempt = DateTimeOffset.MinValue;
        try
        {
            await foreach (var entry in _queue.Reader.ReadAllAsync(_abort.Token))
            {
                if (_clock.GetUtcNow() < nextAttempt) { Interlocked.Increment(ref _dropped); continue; }
                try
                {
                    using var request = new HttpRequestMessage(HttpMethod.Post, _options.ServerUrl);
                    if (_options.Token.Length > 0)
                        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _options.Token);
                    var body = JsonSerializer.Serialize(new
                    {
                        topic = _options.Topic,
                        title = $"FitLife {_serviceName}: {entry.Level}",
                        message = entry.Message,
                        priority = entry.Level switch { LogLevel.Critical => 5, LogLevel.Error => 4, LogLevel.Warning => 3, _ => 2 }
                    }, _json);
                    request.Content = new StringContent(body, Encoding.UTF8, "application/json");
                    using var response = await _client!.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, _abort.Token);
                    if (!response.IsSuccessStatusCode) throw new HttpRequestException(null, null, response.StatusCode);
                }
                catch (Exception error) when (error is not OutOfMemoryException)
                {
                    if (_abort.IsCancellationRequested) break;
                    Interlocked.Increment(ref _dropped);
                    nextAttempt = _clock.GetUtcNow().AddSeconds(30);
                    // Ни URL/topic/token, ни response body/exception message не пишутся обратно в лог.
                    _diagnostics!.LogWarning("ntfy delivery failed; cooldown is 30 seconds. HTTP status: {Status}",
                        error is HttpRequestException http ? (int?)http.StatusCode : null);
                }
            }
        }
        catch (OperationCanceledException) when (_abort.IsCancellationRequested) { return; }
    }

    /// <summary>Общий shutdown task обслуживает ILoggerFactory, IHostedService и ранний startup scope.</summary>
    private async Task ShutdownAsync()
    {
        Interlocked.Exchange(ref _completed, 1);
        _queue.Writer.TryComplete();
        if (_worker is not null)
        {
            try { await _worker.WaitAsync(TimeSpan.FromSeconds(5)); }
            catch (TimeoutException) { _abort.Cancel(); await _worker; }
        }
        if (_dropped > 0) _diagnostics?.LogWarning("ntfy dropped {Count} notifications; original logs remain available.", _dropped);
        _client?.Dispose();
        _abort.Dispose();
    }

    /// <summary>Обрезает только уже замаскированный текст, сохраняя целые Unicode scalar values.</summary>
    private static string LimitUtf8(string text, int maximumBytes)
    {
        if (Encoding.UTF8.GetByteCount(text) <= maximumBytes) return text;
        var result = new StringBuilder();
        var bytes = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            if (bytes + rune.Utf8SequenceLength > maximumBytes - 16) break;
            result.Append(rune.ToString());
            bytes += rune.Utf8SequenceLength;
        }
        return result.Append("\n[truncated]").ToString();
    }

    /// <summary>В очереди находится только безопасный текст и уровень, без Exception/state.</summary>
    private sealed record Notification(LogLevel Level, string Message);

    /// <summary>Тонкий адаптер стандартного ILogger к очереди своего процесса.</summary>
    private sealed class NtfyLogger(NtfyLoggerProvider provider, string category) : ILogger
    {
        /// <summary>Не собирает scope values, потенциально содержащие пользовательские данные.</summary>
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        /// <summary>Применяет порог ntfy до дорогого форматирования.</summary>
        public bool IsEnabled(LogLevel logLevel) => provider.IsEnabled(category, logLevel);
        /// <summary>Синхронно помещает замаскированную запись в ограниченную очередь.</summary>
        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter) => provider.Write(category, logLevel, eventId, state, exception, formatter);
    }
}
