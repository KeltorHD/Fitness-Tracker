using System.Collections.Concurrent;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace FitLife.Server.Tests;

/// <summary>Проверяет диагностику Backend с настоящими shipped filters без записи в глобальный Console.</summary>
internal sealed class TestBackendLogs : ILoggerProvider
{
    /// <summary>Хранит сформированные события и исходные structured values из изолированного host.</summary>
    internal ConcurrentQueue<Entry> Entries { get; } = new();
    /// <summary>Читает актуальный Backend appsettings, а не включает Information искусственным test filter.</summary>
    internal IConfiguration Configuration { get; } = LoadConfiguration();

    /// <summary>Подключает коллектор и реальные фильтры к DI тестового сервера.</summary>
    internal void Configure(ILoggingBuilder logging) => logging.AddConfiguration(Configuration.GetSection("Logging")).AddProvider(this);

    /// <summary>Создаёт такой же logger для непосредственной проверки middleware и import service.</summary>
    internal ILoggerFactory Factory() => LoggerFactory.Create(Configure);

    /// <summary>Не захватывает чужие категории или значения request scopes.</summary>
    public ILogger CreateLogger(string categoryName) => categoryName == "FitLife.Backend" || categoryName.StartsWith("FitLife.Backend.", StringComparison.Ordinal)
        ? new Capture(this) : NullLogger.Instance;

    /// <summary>Коллектор не владеет внешними ресурсами.</summary>
    public void Dispose() { }

    /// <summary>Находит конфигурацию в обычном checkout и git worktree для Debug и Release.</summary>
    private static IConfiguration LoadConfiguration()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var file = Path.Combine(directory.FullName, "Backend", "appsettings.json");
            if (File.Exists(file)) return new ConfigurationBuilder().AddJsonFile(file).Build();
            directory = directory.Parent;
        }
        throw new DirectoryNotFoundException("Backend appsettings was not found in the test checkout.");
    }

    /// <summary>Сохраняет также exception для проверки отсутствия приватной диагностики.</summary>
    internal sealed record Entry(LogLevel Level, int EventId, string Message, IReadOnlyDictionary<string, object?> Fields, Exception? Exception);

    /// <summary>Собирает параметры, уже допущенные штатными фильтрами ILoggerFactory.</summary>
    private sealed class Capture(TestBackendLogs owner) : ILogger
    {
        /// <summary>Request scopes не записываются.</summary>
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        /// <summary>Порог применяет LoggerFactory, а не этот transport.</summary>
        public bool IsEnabled(LogLevel logLevel) => true;
        /// <summary>Даёт проверить сообщение и неотображённые structured fields.</summary>
        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            var fields = state is IEnumerable<KeyValuePair<string, object?>> values ? values.ToDictionary(item => item.Key, item => item.Value) : [];
            owner.Entries.Enqueue(new(logLevel, eventId.Id, formatter(state, exception), fields, exception));
        }
    }
}
