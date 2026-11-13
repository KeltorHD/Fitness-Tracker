using Npgsql;

namespace FitLife.Authentication;

/// <summary>Сериализует изменения OAuth-привязок пользователя между экземплярами Authentication.</summary>
public interface IHealthConnectionLocks
{
    /// <summary>Удерживает блокировку до освобождения lease, без транзакции поверх внешнего HTTP.</summary>
    Task<IAsyncDisposable> AcquireAsync(string userId, CancellationToken cancellationToken);
}

/// <summary>Использует отдельное непулируемое соединение; его закрытие гарантированно освобождает session lock.</summary>
public sealed class HealthConnectionLocks(IConfiguration configuration) : IHealthConnectionLocks
{
    /// <summary>Не допускает одновременную ротацию refresh token, отключение и повторную привязку.</summary>
    public async Task<IAsyncDisposable> AcquireAsync(string userId, CancellationToken cancellationToken)
    {
        var settings = new NpgsqlConnectionStringBuilder(configuration.GetConnectionString("Database")) { Pooling = false };
        var connection = new NpgsqlConnection(settings.ConnectionString);
        try
        {
            await connection.OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand("SELECT pg_advisory_lock(hashtextextended(@owner, 137))", connection);
            command.Parameters.AddWithValue("owner", userId);
            await command.ExecuteNonQueryAsync(cancellationToken);
            return connection;
        }
        catch { await connection.DisposeAsync(); throw; }
    }
}
