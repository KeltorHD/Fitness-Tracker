using System.Data;
using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;

namespace FitnessTracker.Backend;

/// <summary>Описывает копию без передачи её содержимого в списке метаданных.</summary>
public sealed record BackupInfo(Guid Id, DateTimeOffset CreatedAt, int ArchiveVersion, int Size, string Sha256);

/// <summary>Атомарно сохраняет неизменяемые архивы, квоту и запрет загрузок удалённого аккаунта.</summary>
public sealed class BackupStorage(BackupDbContext database, TimeProvider clock)
{
    /// <summary>Максимальный размер архива в байтах, согласованный со Swift Core.</summary>
    public const int MaximumBytes = 30 * 1024 * 1024;
    /// <summary>Максимальное количество одновременно сохранённых копий одного пользователя.</summary>
    public const int MaximumCopies = 10;

    /// <summary>Создаёт копию или подтверждает повтор того же UUID и байтов без изменения времени создания.</summary>
    public async Task<(BackupInfo Info, bool Created)> Put(string owner, Guid id, byte[] payload,
        CancellationToken cancellationToken)
    {
        var version = BackupArchiveValidator.Validate(payload);
        var hash = Convert.ToHexStringLower(SHA256.HashData(payload));
        await using var transaction = await database.Database.BeginTransactionAsync(
            database.Database.IsNpgsql() ? IsolationLevel.ReadCommitted : IsolationLevel.Serializable, cancellationToken);
        await LockOwner(owner, cancellationToken);
        if (await database.DeletedAccounts.AnyAsync(item => item.Id == owner, cancellationToken))
            throw new BackupException(403, "account_deleted");
        var existing = await database.Backups.SingleOrDefaultAsync(item => item.OwnerId == owner && item.Id == id, cancellationToken);
        if (existing is not null)
        {
            if (existing.Sha256 != hash) throw new BackupException(409, "backup_exists");
            await transaction.CommitAsync(cancellationToken);
            return (Info(existing), false);
        }
        if (await database.Backups.CountAsync(item => item.OwnerId == owner, cancellationToken) >= MaximumCopies)
            throw new BackupException(409, "backup_limit");
        var backup = new BackupRecord
        {
            Id = id,
            OwnerId = owner,
            CreatedAtMilliseconds = clock.GetUtcNow().ToUnixTimeMilliseconds(),
            ArchiveVersion = version,
            Size = payload.Length,
            Sha256 = hash,
            Payload = payload
        };
        database.Backups.Add(backup);
        await database.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return (Info(backup), true);
    }

    /// <summary>Удаляет копии и запрещает новые загрузки в одной транзакции с per-user блокировкой.</summary>
    public async Task DeleteAccount(string owner, CancellationToken cancellationToken)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(
            database.Database.IsNpgsql() ? IsolationLevel.ReadCommitted : IsolationLevel.Serializable, cancellationToken);
        await LockOwner(owner, cancellationToken);
        await database.Backups.Where(item => item.OwnerId == owner).ExecuteDeleteAsync(cancellationToken);
        if (!await database.DeletedAccounts.AnyAsync(item => item.Id == owner, cancellationToken))
            database.DeletedAccounts.Add(new DeletedAccount { Id = owner });
        await database.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    /// <summary>Сериализует изменения квоты и удаления одного владельца в PostgreSQL.</summary>
    private async Task LockOwner(string owner, CancellationToken cancellationToken)
    {
        if (database.Database.IsNpgsql())
            await database.Database.ExecuteSqlInterpolatedAsync(
                $"SELECT pg_advisory_xact_lock(hashtextextended({owner}, 0))", cancellationToken);
    }

    /// <summary>Преобразует запись в безопасный HTTP DTO метаданных.</summary>
    public static BackupInfo Info(BackupRecord value) =>
        new(value.Id, DateTimeOffset.FromUnixTimeMilliseconds(value.CreatedAtMilliseconds), value.ArchiveVersion, value.Size, value.Sha256);

}

/// <summary>Возвращает устойчивый HTTP status/code без содержимого архива и внутренних деталей.</summary>
public sealed class BackupException(int status, string code) : Exception(code)
{
    /// <summary>HTTP-статус отказа в операции.</summary>
    public int Status { get; } = status;
    /// <summary>Машинный код ошибки, используемый клиентом.</summary>
    public string Code { get; } = code;
}
