using Npgsql;

namespace FitnessTracker.Server.Tests;

/// <summary>Создаёт отдельную БД на явно выбранном тестовом PostgreSQL и гарантирует её удаление.</summary>
internal sealed class PostgresDatabase : IAsyncDisposable
{
    private readonly string _adminConnectionString;
    private readonly string _name;

    /// <summary>Хранит параметры только собственной случайной БД, без общего connection pool.</summary>
    private PostgresDatabase(string adminConnectionString, string name, string connectionString)
    {
        _adminConnectionString = adminConnectionString;
        _name = name;
        ConnectionString = connectionString;
    }

    /// <summary>Строка подключения к изолированной БД сценария.</summary>
    internal string ConnectionString { get; }

    /// <summary>Без явной тестовой конфигурации завершается ошибкой; создаёт только БД с генерируемым именем.</summary>
    internal static async Task<PostgresDatabase> CreateAsync(CancellationToken cancellationToken = default)
    {
        var configured = Environment.GetEnvironmentVariable("FITNESS_TRACKER_TEST_POSTGRES");
        if (string.IsNullOrWhiteSpace(configured))
            throw new InvalidOperationException("Set FITNESS_TRACKER_TEST_POSTGRES to a disposable PostgreSQL instance.");
        var adminSettings = new NpgsqlConnectionStringBuilder(configured) { Pooling = false, Timeout = 10, CommandTimeout = 15 };
        var name = "fitnesstracker_tests_" + Guid.NewGuid().ToString("N");
        var isolated = new NpgsqlConnectionStringBuilder(adminSettings.ConnectionString) { Database = name }.ConnectionString;
        await using var admin = new NpgsqlConnection(adminSettings.ConnectionString);
        await admin.OpenAsync(cancellationToken);
        // Имя целиком генерируется здесь; пользовательские SQL identifiers не интерполируются.
        await using var create = new NpgsqlCommand($"CREATE DATABASE {name}", admin);
        await create.ExecuteNonQueryAsync(cancellationToken);
        return new PostgresDatabase(adminSettings.ConnectionString, name, isolated);
    }

    /// <summary>Удаляет только собственную БД с отдельным deadline даже после отмены основного теста.</summary>
    public async ValueTask DisposeAsync()
    {
        using var cleanup = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        await using var admin = new NpgsqlConnection(_adminConnectionString);
        await admin.OpenAsync(cleanup.Token);
        await using var drop = new NpgsqlCommand($"DROP DATABASE {_name} WITH (FORCE)", admin);
        await drop.ExecuteNonQueryAsync(cleanup.Token);
    }
}
