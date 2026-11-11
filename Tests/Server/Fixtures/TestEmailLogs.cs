using System.Collections.Concurrent;
using FitLife.Authentication;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace FitLife.Server.Tests;

/// <summary>Собирает текст и structured fields почтовых событий или выбранной категории без сети и глобального Console.</summary>
/// <param name="selectedCategory">Отдельная категория для проверки регистрации; по умолчанию только отправка почты.</param>
/// <param name="onEntry">Необязательный сигнал завершения фоновой операции без polling и задержек.</param>
internal sealed class TestEmailLogs(string? selectedCategory = null, Action<TestEmailLogs.Entry>? onEntry = null) : ILoggerProvider
{
    private readonly Action<Entry>? _onEntry = onEntry;
    /// <summary>События доставки из текущего изолированного теста.</summary>
    internal ConcurrentQueue<Entry> Entries { get; } = new();

    /// <summary>Читает реальные shipped logging rules, чтобы тесты выявили скрытый Information по умолчанию.</summary>
    internal IConfiguration Configuration { get; } = LoadConfiguration();

    /// <summary>Настройки для реального HTTP host, без подмены категории на произвольный тестовый порог.</summary>
    internal IReadOnlyDictionary<string, string?> Settings => Configuration.AsEnumerable()
        .Where(item => item.Key.StartsWith("Logging:LogLevel:", StringComparison.Ordinal))
        .ToDictionary(item => item.Key, item => item.Value);

    /// <summary>Применяет реальные фильтры console pipeline к подменённому transport logger.</summary>
    internal ILoggerFactory Factory() => LoggerFactory.Create(builder => builder
        .AddConfiguration(Configuration.GetSection("Logging"))
        .AddProvider(this));

    /// <summary>Не захватывает посторонние framework события и request scopes.</summary>
    public ILogger CreateLogger(string categoryName)
    {
        var included = selectedCategory is null
            ? categoryName == typeof(EmailConfirmationService).FullName || categoryName == typeof(SmtpEmailSender).FullName
            : categoryName == selectedCategory;
        return included ? new Capture(this) : NullLogger.Instance;
    }

    /// <summary>Коллектор не владеет внешними ресурсами.</summary>
    public void Dispose() { }

    /// <summary>Находит исходный appsettings в checkout независимо от Debug/Release и рабочего каталога тестов.</summary>
    private static IConfiguration LoadConfiguration()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var file = Path.Combine(directory.FullName, "Authentication", "appsettings.json");
            if (File.Exists(file)) return new ConfigurationBuilder().AddJsonFile(file).Build();
            directory = directory.Parent;
        }
        throw new DirectoryNotFoundException("Authentication appsettings was not found in the test checkout.");
    }

    /// <summary>Сохраняет как сформатированный текст, так и исходные поля для проверки отсутствия секретов.</summary>
    internal sealed record Entry(LogLevel Level, int EventId, string Message, IReadOnlyDictionary<string, string?> Fields, Exception? Exception);

    /// <summary>Logger под штатными фильтрами ILoggerFactory, не пишет в stdout.</summary>
    private sealed class Capture(TestEmailLogs owner) : ILogger
    {
        /// <summary>Сохраняет только поля самого события.</summary>
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        /// <summary>Фактический порог проверяет factory по shipped configuration.</summary>
        public bool IsEnabled(LogLevel logLevel) => true;
        /// <summary>Даёт тесту проверить также неотображённые structured values и исходное exception.</summary>
        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            var fields = state is IEnumerable<KeyValuePair<string, object?>> values
                ? values.ToDictionary(item => item.Key, item => item.Value?.ToString()) : [];
            var entry = new Entry(logLevel, eventId.Id, formatter(state, exception), fields, exception);
            owner.Entries.Enqueue(entry);
            owner._onEntry?.Invoke(entry);
        }
    }
}
