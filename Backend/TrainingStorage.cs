using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace FitLife.Backend;

/// <summary>Версионирует агрегаты одного владельца, сохраняя графы и tombstones транзакционно.</summary>
public sealed class TrainingStorage(BackupDbContext database)
{
    public const int MaximumBytes = 30 * 1024 * 1024;

    public async Task<TrainingChange> ApplyAsync(string owner, TrainingMutation mutation, CancellationToken ct)
    {
        var result = await ApplyBatchAsync(owner, [mutation], ct);
        return result[0];
    }

    public async Task<IReadOnlyList<TrainingChange>> ApplyBatchAsync(string owner, IReadOnlyList<TrainingMutation> mutations, CancellationToken ct)
    {
        if (mutations.Count is < 1 or > 100 || mutations.Any(x => x is null) ||
            mutations.Select(x => (x.Kind, x.Id)).Distinct().Count() != mutations.Count)
            throw new TrainingException(400, "invalid_training_batch");
        await using var transaction = await database.Database.BeginTransactionAsync(
            database.Database.IsNpgsql() ? IsolationLevel.ReadCommitted : IsolationLevel.Serializable, ct);
        try
        {
            await LockOwnerAsync(owner, ct);
            var result = new List<TrainingChange>();
            foreach (var mutation in mutations)
            {
                result.Add(await ApplyLockedAsync(owner, mutation, ct));
                database.ChangeTracker.Clear();
            }
            await transaction.CommitAsync(ct);
            return result;
        }
        finally { database.ChangeTracker.Clear(); }
    }

    public async Task<TrainingPage> ChangesAsync(string owner, long after, int limit, CancellationToken ct)
    {
        if (after < 0 || limit is < 1 or > 100) throw new TrainingException(400, "invalid_cursor");
        await using var transaction = await database.Database.BeginTransactionAsync(
            database.Database.IsNpgsql() ? IsolationLevel.RepeatableRead : IsolationLevel.Serializable, ct);
        var currentRevision = await database.TrainingOwners.AsNoTracking().Where(x => x.OwnerId == owner)
            .Select(x => x.Revision).SingleOrDefaultAsync(ct);
        if (after > currentRevision) throw new TrainingException(409, "cursor_reset_required");
        var records = await database.TrainingRecords.AsNoTracking().Where(x => x.OwnerId == owner && x.Revision > after)
            .OrderBy(x => x.Revision).Take(limit + 1).ToListAsync(ct);
        var results = new List<TrainingChange>();
        var size = 0;
        foreach (var record in records.Take(limit))
        {
            var change = await ChangeAsync(record, ct);
            var bytes = change.Value is { } value ? Encoding.UTF8.GetByteCount(value.GetRawText()) : 0;
            if (results.Count > 0 && size + bytes > MaximumBytes) break;
            results.Add(change);
            size += bytes;
        }
        var cursor = results.Count > 0 ? results[^1].Revision : after;
        await transaction.CommitAsync(ct);
        return new TrainingPage(results, cursor, records.Count > results.Count);
    }

    private async Task<TrainingChange> ApplyLockedAsync(string owner, TrainingMutation mutation, CancellationToken ct)
    {
        if (!TrainingKinds.Contains(mutation.Kind) || mutation.BaseRevision < 0)
            throw new TrainingException(400, "invalid_training_mutation");
        if (mutation.Deleted && mutation.Value is { ValueKind: not JsonValueKind.Null })
            throw new TrainingException(400, "invalid_training_mutation");
        JsonElement? canonical = mutation.Deleted ? null : TrainingValidation.Canonical(mutation.Kind,
            mutation.Id, mutation.Value ?? throw new TrainingException(400, "invalid_training_data"));
        var hash = canonical is { } value ? Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value.GetRawText()))) : "";
        if (await database.DeletedAccounts.AnyAsync(x => x.Id == owner, ct))
            throw new TrainingException(403, "account_deleted");
        var record = await database.TrainingRecords.SingleOrDefaultAsync(
            x => x.OwnerId == owner && x.Kind == mutation.Kind && x.Id == mutation.Id, ct);
        if (record is not null && record.Deleted == mutation.Deleted && record.Hash == hash)
            return await ChangeAsync(record, ct);
        if ((record?.Revision ?? 0) != mutation.BaseRevision)
            throw new TrainingException(409, "training_conflict", record is null ? null : await ChangeAsync(record, ct));
        if (record is null && await database.TrainingRecords.CountAsync(x => x.OwnerId == owner, ct) >= 100_000)
            throw new TrainingException(409, "training_limit");
        if (!mutation.Deleted && (record is null || record.Deleted))
        {
            var limit = mutation.Kind == TrainingKinds.Template ? 1000 : 10_000;
            if (await database.TrainingRecords.CountAsync(x => x.OwnerId == owner && x.Kind == mutation.Kind && !x.Deleted, ct) >= limit)
                throw new TrainingException(409, "training_limit");
        }
        var account = await database.TrainingOwners.SingleOrDefaultAsync(x => x.OwnerId == owner, ct);
        if (account is null)
        {
            account = new TrainingOwner { OwnerId = owner };
            database.TrainingOwners.Add(account);
        }
        if (record is null)
        {
            record = new TrainingRecordMetadata { OwnerId = owner, Kind = mutation.Kind, Id = mutation.Id };
            database.TrainingRecords.Add(record);
        }
        record.Revision = checked(++account.Revision);
        record.Deleted = mutation.Deleted;
        record.Hash = hash;
        // Metadata создаётся до вставки зависимых строк, оставаясь внутри той же транзакции.
        await database.SaveChangesAsync(ct);
        if (mutation.Deleted) await RemoveAsync(owner, mutation.Kind, mutation.Id, account, ct);
        else await SaveAsync(owner, mutation.Kind, mutation.Id, canonical!.Value, ct);
        await database.SaveChangesAsync(ct);
        return new TrainingChange(record.Kind, record.Id, record.Revision, record.Deleted, canonical);
    }

    private async Task SaveAsync(string owner, string kind, Guid id, JsonElement value, CancellationToken ct)
    {
        switch (kind)
        {
            case TrainingKinds.Workout:
                var workout = TrainingJson.Read<WorkoutData>(value);
                var workoutRow = TrainingMapping.Workout(owner, workout);
                var currentWorkout = await database.Workouts.SingleOrDefaultAsync(x => x.OwnerId == owner && x.Id == id, ct);
                if (currentWorkout is null) database.Workouts.Add(workoutRow);
                else
                {
                    await database.Set<TrainingPause>().Where(x => x.OwnerId == owner && x.WorkoutId == id).ExecuteDeleteAsync(ct);
                    database.Entry(currentWorkout).CurrentValues.SetValues(workoutRow);
                    currentWorkout.Pauses = workoutRow.Pauses;
                }
                await ReplaceExercisesAsync(owner, kind, id, TrainingMapping.WorkoutExercises(owner, workout), ct);
                break;
            case TrainingKinds.Template:
                var template = TrainingJson.Read<TemplateData>(value);
                var templateRow = TrainingMapping.Template(owner, template);
                var currentTemplate = await database.Templates.SingleOrDefaultAsync(x => x.OwnerId == owner && x.Id == id, ct);
                if (currentTemplate is null) database.Templates.Add(templateRow);
                else
                {
                    await database.Set<TrainingVariation>().Where(x => x.OwnerId == owner && x.TemplateId == id).ExecuteDeleteAsync(ct);
                    database.Entry(currentTemplate).CurrentValues.SetValues(templateRow);
                    currentTemplate.Variations = templateRow.Variations;
                }
                await ReplaceExercisesAsync(owner, kind, id, TrainingMapping.TemplateExercises(owner, template), ct);
                break;
            case TrainingKinds.BodyWeight:
                var weightRow = TrainingMapping.BodyWeight(owner, TrainingJson.Read<BodyWeightData>(value));
                var currentWeight = await database.BodyWeights.SingleOrDefaultAsync(x => x.OwnerId == owner && x.Id == id, ct);
                if (currentWeight is null) database.BodyWeights.Add(weightRow);
                else database.Entry(currentWeight).CurrentValues.SetValues(weightRow);
                break;
            case TrainingKinds.HeartRate:
                if (!await database.Workouts.AnyAsync(x => x.OwnerId == owner && x.Id == id, ct))
                    throw new TrainingException(409, "workout_missing");
                var heartRow = TrainingMapping.HeartRate(owner, TrainingJson.Read<HeartRateData>(value));
                var currentHeart = await database.HeartRateRecordings.SingleOrDefaultAsync(x => x.OwnerId == owner && x.Id == id, ct);
                if (currentHeart is null) database.HeartRateRecordings.Add(heartRow);
                else
                {
                    await database.Set<TrainingHeartRateReading>().Where(x => x.OwnerId == owner && x.WorkoutId == id).ExecuteDeleteAsync(ct);
                    database.Entry(currentHeart).CurrentValues.SetValues(heartRow);
                    currentHeart.Readings = heartRow.Readings;
                }
                break;
        }
    }

    private async Task ReplaceExercisesAsync(string owner, string kind, Guid id, List<TrainingExercise> rows, CancellationToken ct)
    {
        await database.Exercises.Where(x => x.OwnerId == owner && x.Kind == kind && x.AggregateId == id).ExecuteDeleteAsync(ct);
        database.Exercises.AddRange(rows);
    }

    private async Task RemoveAsync(string owner, string kind, Guid id, TrainingOwner account, CancellationToken ct)
    {
        switch (kind)
        {
            case TrainingKinds.Workout:
                var heart = await database.TrainingRecords.SingleOrDefaultAsync(
                    x => x.OwnerId == owner && x.Kind == TrainingKinds.HeartRate && x.Id == id, ct);
                if (heart is not null && !heart.Deleted)
                {
                    heart.Deleted = true;
                    heart.Hash = "";
                    heart.Revision = checked(++account.Revision);
                }
                await database.Workouts.Where(x => x.OwnerId == owner && x.Id == id).ExecuteDeleteAsync(ct);
                break;
            case TrainingKinds.Template:
                await database.Templates.Where(x => x.OwnerId == owner && x.Id == id).ExecuteDeleteAsync(ct);
                break;
            case TrainingKinds.BodyWeight:
                await database.BodyWeights.Where(x => x.OwnerId == owner && x.Id == id).ExecuteDeleteAsync(ct);
                break;
            case TrainingKinds.HeartRate:
                await database.HeartRateRecordings.Where(x => x.OwnerId == owner && x.Id == id).ExecuteDeleteAsync(ct);
                break;
        }
        await database.Exercises.Where(x => x.OwnerId == owner && x.Kind == kind && x.AggregateId == id).ExecuteDeleteAsync(ct);
    }

    private async Task<TrainingChange> ChangeAsync(TrainingRecordMetadata record, CancellationToken ct) =>
        new(record.Kind, record.Id, record.Revision, record.Deleted, record.Deleted ? null :
            await TrainingMapping.ReadAsync(database, record.OwnerId, record.Kind, record.Id, ct));

    private async Task LockOwnerAsync(string owner, CancellationToken ct)
    {
        if (database.Database.IsNpgsql())
            await database.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({owner}, 0))", ct);
    }

    /// <summary>Однократно переносит последний полный v4-архив владельца, сохраняя оригинальные копии.</summary>
    public async Task ImportLatestBackupsAsync(CancellationToken ct)
    {
        var owners = await database.Backups.AsNoTracking().Select(x => x.OwnerId).Distinct().ToListAsync(ct);
        foreach (var owner in owners)
        {
            await using var transaction = await database.Database.BeginTransactionAsync(
                database.Database.IsNpgsql() ? IsolationLevel.ReadCommitted : IsolationLevel.Serializable, ct);
            try
            {
                await LockOwnerAsync(owner, ct);
                if (await database.TrainingOwners.AnyAsync(x => x.OwnerId == owner, ct) ||
                    await database.DeletedAccounts.AnyAsync(x => x.Id == owner, ct)) continue;
                var backup = await database.Backups.AsNoTracking().Where(x => x.OwnerId == owner)
                    .OrderByDescending(x => x.CreatedAtMilliseconds).ThenByDescending(x => x.Id).FirstAsync(ct);
                if (backup.Size != backup.Payload.Length || backup.Sha256 != Convert.ToHexStringLower(SHA256.HashData(backup.Payload)))
                    throw new InvalidOperationException("Stored training import failed: invalid archive integrity.");
                var archive = JsonSerializer.Deserialize<StoredArchive>(backup.Payload, TrainingJson.Options)
                    ?? throw new InvalidOperationException("Stored training import failed: invalid archive.");
                if (archive.Format != "com.fitlife.archive" || archive.Version != 4 || !double.IsFinite(archive.ExportedAt))
                    throw new InvalidOperationException("Stored training import requires a current version 4 archive.");
                await Import(TrainingKinds.Workout, archive.Workouts.Select(x => (x.Id, TrainingJson.Element(x))));
                await Import(TrainingKinds.Template, archive.Templates.Select(x => (x.Id, TrainingJson.Element(x))));
                await Import(TrainingKinds.BodyWeight, archive.BodyWeights.Select(x => (x.Id, TrainingJson.Element(x))));
                var account = await database.TrainingOwners.SingleOrDefaultAsync(x => x.OwnerId == owner, ct);
                if (account is null) { account = new TrainingOwner { OwnerId = owner }; database.TrainingOwners.Add(account); }
                account.ImportedBackupId = backup.Id;
                await database.SaveChangesAsync(ct);
                await transaction.CommitAsync(ct);
                async Task Import(string kind, IEnumerable<(Guid Id, JsonElement Value)> values)
                {
                    var ids = new HashSet<Guid>();
                    foreach (var (id, value) in values)
                    {
                        if (!ids.Add(id)) throw new InvalidOperationException("Stored training import failed: duplicate record.");
                        await ApplyLockedAsync(owner, new TrainingMutation
                        { Kind = kind, Id = id, BaseRevision = 0, Deleted = false, Value = value }, ct);
                        database.ChangeTracker.Clear();
                    }
                }
            }
            catch (Exception error) when (error is JsonException or TrainingException or NullReferenceException)
            {
                throw new InvalidOperationException("Stored training import failed: invalid archive data.");
            }
            finally { database.ChangeTracker.Clear(); }
        }
    }

    private sealed record StoredArchive
    {
        public required string Format { get; init; }
        public required int Version { get; init; }
        public required double ExportedAt { get; init; }
        public required List<WorkoutData> Workouts { get; init; }
        public required List<TemplateData> Templates { get; init; }
        public required List<BodyWeightData> BodyWeights { get; init; }
    }
}
