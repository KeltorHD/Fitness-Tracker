using System.Data;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace FitnessTracker.Backend;

public sealed record BackupInfo(Guid Id, DateTimeOffset CreatedAt, int ArchiveVersion, int Size, string Sha256);

public sealed class BackupStorage(BackupDbContext database, TimeProvider clock)
{
    public const int MaximumBytes = 20 * 1024 * 1024;
    public const int MaximumCopies = 10;

    public async Task<(BackupInfo Info, bool Created)> Put(string owner, Guid id, byte[] payload,
        CancellationToken cancellationToken)
    {
        if (payload.Length == 0 || payload.Length > MaximumBytes) throw new BackupException(413, "invalid_size");
        var version = ValidateEnvelope(payload);
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

    private async Task LockOwner(string owner, CancellationToken cancellationToken)
    {
        if (database.Database.IsNpgsql())
            await database.Database.ExecuteSqlInterpolatedAsync(
                $"SELECT pg_advisory_xact_lock(hashtextextended({owner}, 0))", cancellationToken);
    }

    public static BackupInfo Info(BackupRecord value) =>
        new(value.Id, DateTimeOffset.FromUnixTimeMilliseconds(value.CreatedAtMilliseconds), value.ArchiveVersion, value.Size, value.Sha256);

    private static int ValidateEnvelope(byte[] payload)
    {
        try
        {
            using var document = JsonDocument.Parse(payload, new JsonDocumentOptions { MaxDepth = 64 });
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("format", out var format) ||
                format.ValueKind != JsonValueKind.String || format.GetString() is not
                    ("com.fitnesstracker.archive" or "com.fitsession.archive") ||
                !root.TryGetProperty("version", out var version) || version.ValueKind != JsonValueKind.Number || !version.TryGetInt32(out var number) ||
                number is < 1 or > 4 || !root.TryGetProperty("exportedAt", out var date) ||
                date.ValueKind != JsonValueKind.Number || !date.TryGetDouble(out var timestamp) || !double.IsFinite(timestamp) ||
                !Array(root, "workouts", 10000) || !Array(root, "templates", 1000) ||
                (number >= 2 && !Array(root, "bodyWeights", 10000)))
                throw new BackupException(400, "invalid_archive");
            return number;
        }
        catch (JsonException) { throw new BackupException(400, "invalid_archive"); }
    }

    private static bool Array(JsonElement root, string name, int limit) =>
        root.TryGetProperty(name, out var array) && array.ValueKind == JsonValueKind.Array && array.GetArrayLength() <= limit;
}

public sealed class BackupException(int status, string code) : Exception(code)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
}
