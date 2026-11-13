using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;

namespace FitLife.Backend;

/// <summary>Версионирует агрегаты одного владельца, сохраняя графы и tombstones транзакционно.</summary>
public sealed class TrainingStorage(BackupDbContext database, ILogger<TrainingStorage>? logger = null)
{
    private readonly ILogger<TrainingStorage> _logger = logger ?? NullLogger<TrainingStorage>.Instance;
    /// <summary>Максимальный размер одного HTTP-пакета: 30 MiB.</summary>
    public const int MaximumBytes = 30 * 1024 * 1024;

    /// <summary>Атомарно применяет одну мутацию с проверкой версии и возвращает подтверждённое значение.</summary>
    public async Task<TrainingChange> ApplyAsync(string owner, TrainingMutation mutation, CancellationToken cancellationToken)
    {
        var result = await ApplyBatchAsync(owner, [mutation], cancellationToken);
        return result[0];
    }

    /// <summary>Атомарно применяет до ста мутаций одного владельца под общей блокировкой; конфликт откатывает весь пакет.</summary>
    public async Task<IReadOnlyList<TrainingChange>> ApplyBatchAsync(string owner, IReadOnlyList<TrainingMutation> mutations, CancellationToken cancellationToken)
    {
        if (mutations.Count is < 1 or > 100 || mutations.Any(x => x is null) ||
            mutations.Select(x => (x.Kind, x.Id)).Distinct().Count() != mutations.Count)
            throw new TrainingException(400, "invalid_training_batch");
        await using var transaction = await database.Database.BeginTransactionAsync(
            database.Database.IsNpgsql() ? IsolationLevel.ReadCommitted : IsolationLevel.Serializable, cancellationToken);
        try
        {
            await LockOwnerAsync(owner, cancellationToken);
            var result = new List<TrainingChange>();
            foreach (var mutation in mutations)
            {
                result.Add(await ApplyLockedAsync(owner, mutation, cancellationToken));
                database.ChangeTracker.Clear();
            }
            await transaction.CommitAsync(cancellationToken);
            return result;
        }
        finally { database.ChangeTracker.Clear(); }
    }

    /// <summary>Читает согласованный снимок последних версий после курсора; превышение актуальной версии требует сверки.</summary>
    public Task<TrainingPage> ChangesAsync(string owner, long after, int limit, CancellationToken cancellationToken) =>
        ChangesAsync(owner, after, limit, null, cancellationToken);

    /// <summary>Читает только поддерживаемые клиентом типы, не раскрывая новые типы прежним клиентам.</summary>
    public async Task<TrainingPage> ChangesAsync(string owner, long after, int limit, string[]? kinds, CancellationToken cancellationToken)
    {
        if (after < 0 || limit is < 1 or > 100) throw new TrainingException(400, "invalid_cursor");
        await using var transaction = await database.Database.BeginTransactionAsync(
            database.Database.IsNpgsql() ? IsolationLevel.RepeatableRead : IsolationLevel.Serializable, cancellationToken);
        var currentRevision = await database.TrainingOwners.AsNoTracking().Where(x => x.OwnerId == owner)
            .Select(x => x.Revision).SingleOrDefaultAsync(cancellationToken);
        if (after > currentRevision) throw new TrainingException(409, "cursor_reset_required");
        var records = await database.TrainingRecords.AsNoTracking().Where(x => x.OwnerId == owner && x.Revision > after && (kinds == null || kinds.Contains(x.Kind)))
            .OrderBy(x => x.Revision).Take(limit + 1).ToListAsync(cancellationToken);
        var results = new List<TrainingChange>();
        var size = 0;
        foreach (var record in records.Take(limit))
        {
            var change = await ChangeAsync(record, cancellationToken);
            var bytes = change.Value is { } value ? Encoding.UTF8.GetByteCount(value.GetRawText()) : 0;
            if (results.Count > 0 && size + bytes > MaximumBytes) break;
            results.Add(change);
            size += bytes;
        }
        var cursor = results.Count > 0 ? results[^1].Revision : after;
        await transaction.CommitAsync(cancellationToken);
        return new TrainingPage(results, cursor, records.Count > results.Count);
    }

    /// <summary>Проверяет версию под блокировкой владельца и сохраняет граф либо tombstone в текущей транзакции.</summary>
    private async Task<TrainingChange> ApplyLockedAsync(string owner, TrainingMutation mutation, CancellationToken cancellationToken)
    {
        if (!TrainingKinds.Contains(mutation.Kind) || mutation.BaseRevision < 0
            || mutation.Kind == TrainingKinds.NutritionProfile && mutation.Id != NutritionValidation.ProfileId)
            throw new TrainingException(400, "invalid_training_mutation");
        if (mutation.Deleted && mutation.Value is { ValueKind: not JsonValueKind.Null })
            throw new TrainingException(400, "invalid_training_mutation");
        JsonElement? canonical = mutation.Deleted ? null : TrainingValidation.Canonical(mutation.Kind,
            mutation.Id, mutation.Value ?? throw new TrainingException(400, "invalid_training_data"));
        if (canonical is { } encoded && Encoding.UTF8.GetByteCount(encoded.GetRawText()) > MaximumBytes)
            throw new TrainingException(413, "record_too_large");
        var hash = canonical is { } value ? Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value.GetRawText()))) : "";
        if (await database.DeletedAccounts.AnyAsync(x => x.Id == owner, cancellationToken))
            throw new TrainingException(403, "account_deleted");
        var record = await database.TrainingRecords.SingleOrDefaultAsync(
            x => x.OwnerId == owner && x.Kind == mutation.Kind && x.Id == mutation.Id, cancellationToken);
        if (record is not null && record.Deleted == mutation.Deleted && record.Hash == hash)
            return await ChangeAsync(record, cancellationToken);
        if ((record?.Revision ?? 0) != mutation.BaseRevision)
            throw new TrainingException(409, "training_conflict", record is null ? null : await ChangeAsync(record, cancellationToken));
        if (record is null && await database.TrainingRecords.CountAsync(x => x.OwnerId == owner, cancellationToken) >= 100_000)
            throw new TrainingException(409, "training_limit");
        if (!mutation.Deleted && (record is null || record.Deleted))
        {
            var limit = mutation.Kind == TrainingKinds.Template ? 1000 : 10_000;
            if (await database.TrainingRecords.CountAsync(x => x.OwnerId == owner && x.Kind == mutation.Kind && !x.Deleted, cancellationToken) >= limit)
                throw new TrainingException(409, "training_limit");
        }
        var account = await database.TrainingOwners.SingleOrDefaultAsync(x => x.OwnerId == owner, cancellationToken);
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
        await database.SaveChangesAsync(cancellationToken);
        if (mutation.Deleted) await RemoveAsync(owner, mutation.Kind, mutation.Id, account, cancellationToken);
        else await SaveAsync(owner, mutation.Kind, mutation.Id, canonical!.Value, cancellationToken);
        await database.SaveChangesAsync(cancellationToken);
        return new TrainingChange(record.Kind, record.Id, record.Revision, record.Deleted, canonical);
    }

    /// <summary>Заменяет граф одного проверенного агрегата, сохраняя независимый пульс при правке тренировки.</summary>
    private async Task SaveAsync(string owner, string kind, Guid id, JsonElement value, CancellationToken cancellationToken)
    {
        if (TrainingKinds.IsNutrition(kind))
        {
            await NutritionStorage.SaveAsync(database, owner, kind, id, value, cancellationToken);
            return;
        }
        switch (kind)
        {
            case TrainingKinds.Workout:
                var workout = TrainingJson.Read<WorkoutData>(value);
                var workoutRow = TrainingMapping.Workout(owner, workout);
                var currentWorkout = await database.Workouts.SingleOrDefaultAsync(x => x.OwnerId == owner && x.Id == id, cancellationToken);
                if (currentWorkout is null) database.Workouts.Add(workoutRow);
                else
                {
                    await database.Set<TrainingPause>().Where(x => x.OwnerId == owner && x.WorkoutId == id).ExecuteDeleteAsync(cancellationToken);
                    database.Entry(currentWorkout).CurrentValues.SetValues(workoutRow);
                    currentWorkout.Pauses = workoutRow.Pauses;
                }
                await ReplaceExercisesAsync(owner, kind, id, TrainingMapping.WorkoutExercises(owner, workout), cancellationToken);
                break;
            case TrainingKinds.Template:
                var template = TrainingJson.Read<TemplateData>(value);
                var templateRow = TrainingMapping.Template(owner, template);
                var currentTemplate = await database.Templates.SingleOrDefaultAsync(x => x.OwnerId == owner && x.Id == id, cancellationToken);
                if (currentTemplate is null) database.Templates.Add(templateRow);
                else
                {
                    await database.Set<TrainingVariation>().Where(x => x.OwnerId == owner && x.TemplateId == id).ExecuteDeleteAsync(cancellationToken);
                    database.Entry(currentTemplate).CurrentValues.SetValues(templateRow);
                    currentTemplate.Variations = templateRow.Variations;
                }
                await ReplaceExercisesAsync(owner, kind, id, TrainingMapping.TemplateExercises(owner, template), cancellationToken);
                break;
            case TrainingKinds.BodyWeight:
                var weightRow = TrainingMapping.BodyWeight(owner, TrainingJson.Read<BodyWeightData>(value));
                var currentWeight = await database.BodyWeights.SingleOrDefaultAsync(x => x.OwnerId == owner && x.Id == id, cancellationToken);
                if (currentWeight is null) database.BodyWeights.Add(weightRow);
                else database.Entry(currentWeight).CurrentValues.SetValues(weightRow);
                break;
            case TrainingKinds.HeartRate:
                if (!await database.Workouts.AnyAsync(x => x.OwnerId == owner && x.Id == id, cancellationToken))
                    throw new TrainingException(409, "workout_missing");
                var heartRow = TrainingMapping.HeartRate(owner, TrainingJson.Read<HeartRateData>(value));
                var currentHeart = await database.HeartRateRecordings.SingleOrDefaultAsync(x => x.OwnerId == owner && x.Id == id, cancellationToken);
                if (currentHeart is null) database.HeartRateRecordings.Add(heartRow);
                else
                {
                    await database.Set<TrainingHeartRateReading>().Where(x => x.OwnerId == owner && x.WorkoutId == id).ExecuteDeleteAsync(cancellationToken);
                    database.Entry(currentHeart).CurrentValues.SetValues(heartRow);
                    currentHeart.Readings = heartRow.Readings;
                }
                break;
        }
    }

    /// <summary>Заменяет дочерние упражнения с каскадной очисткой прежних подходов и этапов.</summary>
    private async Task ReplaceExercisesAsync(string owner, string kind, Guid id, List<TrainingExercise> rows, CancellationToken cancellationToken)
    {
        await database.Exercises.Where(x => x.OwnerId == owner && x.Kind == kind && x.AggregateId == id).ExecuteDeleteAsync(cancellationToken);
        database.Exercises.AddRange(rows);
    }

    /// <summary>Удаляет граф; для тренировки сохраняет tombstone пульса и самостоятельные замеры веса.</summary>
    private async Task RemoveAsync(string owner, string kind, Guid id, TrainingOwner account, CancellationToken cancellationToken)
    {
        if (TrainingKinds.IsNutrition(kind))
        {
            await NutritionStorage.RemoveAsync(database, owner, kind, id, cancellationToken);
            return;
        }
        switch (kind)
        {
            case TrainingKinds.Workout:
                var heart = await database.TrainingRecords.SingleOrDefaultAsync(
                    x => x.OwnerId == owner && x.Kind == TrainingKinds.HeartRate && x.Id == id, cancellationToken);
                if (heart is not null && !heart.Deleted)
                {
                    heart.Deleted = true;
                    heart.Hash = "";
                    heart.Revision = checked(++account.Revision);
                }
                await database.Workouts.Where(x => x.OwnerId == owner && x.Id == id).ExecuteDeleteAsync(cancellationToken);
                break;
            case TrainingKinds.Template:
                await database.Templates.Where(x => x.OwnerId == owner && x.Id == id).ExecuteDeleteAsync(cancellationToken);
                break;
            case TrainingKinds.BodyWeight:
                await database.BodyWeights.Where(x => x.OwnerId == owner && x.Id == id).ExecuteDeleteAsync(cancellationToken);
                break;
            case TrainingKinds.HeartRate:
                await database.HeartRateRecordings.Where(x => x.OwnerId == owner && x.Id == id).ExecuteDeleteAsync(cancellationToken);
                break;
        }
        await database.Exercises.Where(x => x.OwnerId == owner && x.Kind == kind && x.AggregateId == id).ExecuteDeleteAsync(cancellationToken);
    }

    /// <summary>Возвращает метаданные удаления либо восстановленное текущее значение агрегата.</summary>
    private async Task<TrainingChange> ChangeAsync(TrainingRecordMetadata record, CancellationToken cancellationToken) =>
        new(record.Kind, record.Id, record.Revision, record.Deleted, record.Deleted ? null :
            await TrainingMapping.ReadAsync(database, record.OwnerId, record.Kind, record.Id, cancellationToken));

    /// <summary>Сериализует записи и очистку одного аккаунта штатной PostgreSQL advisory-блокировкой.</summary>
    private async Task LockOwnerAsync(string owner, CancellationToken cancellationToken)
    {
        if (database.Database.IsNpgsql())
            await database.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({owner}, 0))", cancellationToken);
    }

    /// <summary>Однократно переносит последний полный v4 архив каждого владельца, сохраняя оригинал и откатывая владельца при ошибке.</summary>
    public async Task ImportLatestBackupsAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation(new EventId(4110, "TrainingImportStarting"), "Checking stored archives for training import.");
        var imported = 0;
        var skipped = 0;
        var owners = await database.Backups.AsNoTracking().Select(x => x.OwnerId).Distinct().ToListAsync(cancellationToken);
        foreach (var owner in owners)
        {
            await using var transaction = await database.Database.BeginTransactionAsync(
                database.Database.IsNpgsql() ? IsolationLevel.ReadCommitted : IsolationLevel.Serializable, cancellationToken);
            try
            {
                await LockOwnerAsync(owner, cancellationToken);
                if (await database.TrainingOwners.AnyAsync(x => x.OwnerId == owner, cancellationToken) ||
                    await database.DeletedAccounts.AnyAsync(x => x.Id == owner, cancellationToken))
                {
                    skipped++;
                    continue;
                }
                var backup = await database.Backups.AsNoTracking().Where(x => x.OwnerId == owner)
                    .OrderByDescending(x => x.CreatedAtMilliseconds).ThenByDescending(x => x.Id).FirstAsync(cancellationToken);
                if (backup.Size != backup.Payload.Length || backup.Sha256 != Convert.ToHexStringLower(SHA256.HashData(backup.Payload)))
                    throw new InvalidOperationException("Stored training import failed: invalid archive integrity.");
                var archive = JsonSerializer.Deserialize<StoredArchive>(backup.Payload, TrainingJson.Options)
                    ?? throw new InvalidOperationException("Stored training import failed: invalid archive.");
                if (archive.Format != "com.fitlife.archive" || archive.Version != 4 || !double.IsFinite(archive.ExportedAt))
                    throw new InvalidOperationException("Stored training import requires a current version 4 archive.");
                await ImportAsync(TrainingKinds.Workout, archive.Workouts.Select(x => (x.Id, TrainingJson.Element(x))));
                await ImportAsync(TrainingKinds.Template, archive.Templates.Select(x => (x.Id, TrainingJson.Element(x))));
                await ImportAsync(TrainingKinds.BodyWeight, archive.BodyWeights.Select(x => (x.Id, TrainingJson.Element(x))));
                var account = await database.TrainingOwners.SingleOrDefaultAsync(x => x.OwnerId == owner, cancellationToken);
                if (account is null) { account = new TrainingOwner { OwnerId = owner }; database.TrainingOwners.Add(account); }
                account.ImportedBackupId = backup.Id;
                await database.SaveChangesAsync(cancellationToken);
                await transaction.CommitAsync(cancellationToken);
                imported++;
                async Task ImportAsync(string kind, IEnumerable<(Guid Id, JsonElement Value)> values)
                {
                    var ids = new HashSet<Guid>();
                    foreach (var (id, value) in values)
                    {
                        if (!ids.Add(id)) throw new InvalidOperationException("Stored training import failed: duplicate record.");
                        await ApplyLockedAsync(owner, new TrainingMutation
                        { Kind = kind, Id = id, BaseRevision = 0, Deleted = false, Value = value }, cancellationToken);
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
        _logger.LogInformation(new EventId(4111, "TrainingImportCompleted"),
            "Training archive import completed. Imported owners: {ImportedOwners}; skipped owners: {SkippedOwners}.", imported, skipped);
    }

    /// <summary>Текущий полный v4 архив для однократного переноса в структурированный журнал.</summary>
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
