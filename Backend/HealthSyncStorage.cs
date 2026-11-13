using System.Data;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace FitLife.Backend;

/// <summary>Транзакционно сохраняет нативные HealthKit UUID, явные удаления и версии объединённых дневных сводок.</summary>
public sealed class HealthSyncStorage(BackupDbContext database, TimeProvider clock)
{
    private static readonly string[] _metrics = ["sleep", "steps", "bodyWeight", "bodyFatPercentage", "heartRate", "restingHeartRate", "activeEnergy", "bloodOxygen", "distance"];
    private static readonly string[] _additive = ["steps", "activeEnergy", "distance"];

    /// <summary>Принимает только следующий пакет; потерянный ответ повторяется без изменения данных и без продвижения anchor до ACK.</summary>
    public async Task<HealthSyncAcknowledgement> ApplyAsync(string owner, HealthSyncBatch batch, CancellationToken cancellationToken)
    {
        var zone = Validate(batch);
        var hash = Convert.ToHexStringLower(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(batch, HealthSyncJson.Options)));
        await using var transaction = await database.Database.BeginTransactionAsync(
            database.Database.IsNpgsql() ? IsolationLevel.ReadCommitted : IsolationLevel.Serializable, cancellationToken);
        try
        {
            if (database.Database.IsNpgsql())
                await database.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({owner}, 0))", cancellationToken);
            if (await database.DeletedAccounts.AnyAsync(x => x.Id == owner, cancellationToken)) throw Failure(403, "account_deleted");
            var account = await database.Set<HealthSyncOwner>().FindAsync([owner], cancellationToken);
            if (account is null) { account = new() { OwnerId = owner }; database.Add(account); }
            var device = await database.Set<HealthSyncDevice>().FindAsync([owner, batch.DeviceId], cancellationToken);
            if (device is not null && device.Sequence == batch.Sequence && device.BatchId == batch.BatchId && device.Hash == hash)
                return JsonSerializer.Deserialize<HealthSyncAcknowledgement>(device.Acknowledgement, HealthSyncJson.Options)!;
            if (batch.Sequence != (device?.Sequence ?? 0) + 1) throw Failure(409, "health_sync_sequence_conflict");
            if (device is null)
            {
                if (await database.Set<HealthSyncDevice>().CountAsync(x => x.OwnerId == owner, cancellationToken) >= 16) throw Failure(409, "health_sync_limit");
                device = new() { OwnerId = owner, Id = batch.DeviceId }; database.Add(device);
            }
            var ids = batch.Quantities.Select(x => x.Id).Concat(batch.Sleep.Select(x => x.Id)).Concat(batch.DeletedIds).ToArray();
            var records = await database.Set<HealthSyncSample>().Where(x => x.OwnerId == owner && ids.Contains(x.Id))
                .ToDictionaryAsync(x => x.Id, cancellationToken);
            if (await database.Set<HealthSyncSample>().CountAsync(x => x.OwnerId == owner, cancellationToken) + ids.Count(id => !records.ContainsKey(id)) > 500_000)
                throw Failure(409, "health_sync_limit");
            var changed = new List<HealthSyncSample>();
            foreach (var id in batch.DeletedIds)
            {
                if (!records.TryGetValue(id, out var row)) { row = new() { OwnerId = owner, Id = id }; database.Add(row); records.Add(id, row); }
                if (!row.Deleted)
                {
                    row.Deleted = true; row.Value = null; row.Stage = null; row.SourceId = ""; row.SourceName = "";
                    changed.Add(row);
                }
            }
            foreach (var candidate in batch.Quantities.Select(x => Sample(owner, x)).Concat(batch.Sleep.Select(x => Sample(owner, x))))
            {
                if (records.TryGetValue(candidate.Id, out var prior))
                {
                    if (prior.Deleted)
                    {
                        if (prior.Metric.Length == 0) { prior.Metric = candidate.Metric; prior.StartMilliseconds = candidate.StartMilliseconds; prior.EndMilliseconds = candidate.EndMilliseconds; changed.Add(prior); }
                        continue;
                    }
                    if (!Same(prior, candidate)) throw Failure(409, "health_sample_conflict");
                    prior.SourceName = candidate.SourceName;
                }
                else { records.Add(candidate.Id, candidate); database.Add(candidate); changed.Add(candidate); }
            }
            if (changed.Count > 0) account.Revision++;
            var affected = changed.Where(x => _additive.Contains(x.Metric)).ToArray();
            var buckets = await database.Set<HealthSyncBucket>().Where(x => x.OwnerId == owner).ToListAsync(cancellationToken);
            foreach (var bucket in buckets.Where(bucket => affected.Any(sample => sample.StartMilliseconds < bucket.EndMilliseconds && sample.EndMilliseconds >= bucket.StartMilliseconds && sample.Metric == bucket.Metric)))
            { bucket.Dirty = true; bucket.Revision = account.Revision; }
            var relevant = affected.Concat(batch.Quantities.Where(x => _additive.Contains(x.Metric) && !records[x.Id].Deleted).Select(x => Sample(owner, x))).ToArray();
            foreach (var sample in relevant)
            {
                var first = TimeZoneInfo.ConvertTime(DateTimeOffset.FromUnixTimeMilliseconds(sample.StartMilliseconds), zone).Date;
                var last = TimeZoneInfo.ConvertTime(DateTimeOffset.FromUnixTimeMilliseconds(Math.Max(sample.StartMilliseconds, sample.EndMilliseconds - 1)), zone).Date;
                for (var date = first; date <= last; date = date.AddDays(1))
                {
                    var start = UtcDay(date, zone); var end = UtcDay(date.AddDays(1), zone);
                    if (end <= start) continue;
                    var bucket = buckets.SingleOrDefault(x => x.Metric == sample.Metric && x.TimeZoneId == zone.Id && x.StartMilliseconds == start);
                    if (bucket is null)
                    {
                        bucket = new() { OwnerId = owner, Metric = sample.Metric, TimeZoneId = zone.Id, StartMilliseconds = start, EndMilliseconds = end };
                        buckets.Add(bucket); database.Add(bucket);
                    }
                    if (bucket.Revision == 0) { bucket.Dirty = true; bucket.Revision = Math.Max(1, account.Revision); }
                }
            }
            if (buckets.Count > 20_000) throw Failure(409, "health_sync_limit");
            var retry = new Dictionary<(string, string, long), HealthSyncBucket>();
            foreach (var bucket in buckets.Where(x => x.Dirty && x.TimeZoneId == zone.Id && relevant.Any(sample => sample.Metric == x.Metric && sample.StartMilliseconds < x.EndMilliseconds && sample.EndMilliseconds >= x.StartMilliseconds)))
                retry[(bucket.Metric, bucket.TimeZoneId, bucket.StartMilliseconds)] = bucket;
            // Чтение tombstones ниже должно видеть и удаления из текущего атомарного пакета.
            await database.SaveChangesAsync(cancellationToken);
            foreach (var aggregate in batch.Aggregates)
            {
                var value = aggregate.Bucket;
                var bucket = buckets.SingleOrDefault(x => x.Metric == value.Metric && x.TimeZoneId == value.TimeZoneId && x.StartMilliseconds == value.Start.ToUnixTimeMilliseconds());
                if (bucket is null || bucket.EndMilliseconds != value.End.ToUnixTimeMilliseconds()) throw Failure(400, "invalid_health_bucket");
                var excluded = await ExcludedAsync(owner, bucket, cancellationToken);
                if (bucket.Revision != value.Revision || !value.ExcludedIds.Order().SequenceEqual(excluded)) retry[(bucket.Metric, bucket.TimeZoneId, bucket.StartMilliseconds)] = bucket;
                else
                {
                    if (bucket.Dirty || bucket.Value != aggregate.Value) { account.Revision++; bucket.Revision = account.Revision; }
                    bucket.Value = aggregate.Value; bucket.Dirty = false;
                }
            }
            if (retry.Count > 2000) throw Failure(413, "health_sync_limit");
            var required = new List<HealthSyncBucketData>();
            foreach (var bucket in retry.Values) required.Add(Bucket(bucket, await ExcludedAsync(owner, bucket, cancellationToken)));
            if (required.Sum(x => x.ExcludedIds.Length) > 10_000) throw Failure(413, "health_sync_limit");
            var acknowledgement = new HealthSyncAcknowledgement(batch.BatchId, batch.Sequence, required.ToArray());
            account.UpdatedAtMilliseconds = clock.GetUtcNow().ToUnixTimeMilliseconds();
            device.Sequence = batch.Sequence; device.BatchId = batch.BatchId; device.Hash = hash;
            device.Acknowledgement = JsonSerializer.Serialize(acknowledgement, HealthSyncJson.Options);
            await database.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return acknowledgement;
        }
        finally { database.ChangeTracker.Clear(); }
    }

    /// <summary>Возвращает общую историю аккаунта; исходные шаги разных устройств не суммируются.</summary>
    public async Task<HealthDataSnapshot> ReadAsync(string owner, DateTimeOffset start, DateTimeOffset end, string[] metrics, TimeZoneInfo zone, CancellationToken cancellationToken)
    {
        if (start < DateTimeOffset.MinValue.AddDays(8) || end <= start || end > clock.GetUtcNow().AddDays(1) || end - start > TimeSpan.FromDays(32) || metrics.Length == 0 || metrics.Distinct().Count() != metrics.Length || metrics.Except(_metrics).Any()) throw Failure(400, "invalid_health_request");
        await PrepareBucketsAsync(owner, start, end, metrics, zone, cancellationToken);
        var first = start.ToUnixTimeMilliseconds(); var last = end.ToUnixTimeMilliseconds();
        await using var transaction = await database.Database.BeginTransactionAsync(database.Database.IsNpgsql() ? IsolationLevel.RepeatableRead : IsolationLevel.Serializable, cancellationToken);
        var rows = await database.Set<HealthSyncSample>().AsNoTracking().Where(x => x.OwnerId == owner && !x.Deleted && metrics.Contains(x.Metric) && !_additive.Contains(x.Metric) && x.StartMilliseconds <= last && x.EndMilliseconds >= first)
            .OrderBy(x => x.StartMilliseconds).ThenBy(x => x.Id).Take(100_001).ToListAsync(cancellationToken);
        var totals = await database.Set<HealthSyncBucket>().AsNoTracking().Where(x => x.OwnerId == owner && metrics.Contains(x.Metric) && x.TimeZoneId == zone.Id && !x.Dirty && x.Value != null && x.StartMilliseconds < last && x.EndMilliseconds > first).ToListAsync(cancellationToken);
        if (rows.Count + totals.Count > 100_000) throw Failure(502, "health_history_too_large");
        var account = await database.Set<HealthSyncOwner>().AsNoTracking().SingleOrDefaultAsync(x => x.OwnerId == owner, cancellationToken);
        var quantities = rows.Where(x => x.Metric != "sleep").Select(x => new HealthQuantity(x.Id, x.Metric, Date(x.StartMilliseconds), Date(x.EndMilliseconds), x.Value!.Value, x.SourceId, x.SourceName))
            .Concat(totals.Select(x => new HealthQuantity(BucketId(x), x.Metric, Date(x.StartMilliseconds), Date(x.EndMilliseconds), x.Value!.Value, "appleHealth", "Apple Health"))).ToArray();
        var sleep = SleepRecords(rows.Where(x => x.Metric == "sleep").ToArray(), zone);
        await transaction.CommitAsync(cancellationToken);
        return new("appleHealth", start, end, account is null ? clock.GetUtcNow() : Date(account.UpdatedAtMilliseconds), metrics, quantities, sleep);
    }

    /// <summary>Даёт передающему iPhone запросы пересчёта, в том числе из часовых поясов других устройств.</summary>
    public async Task<HealthSyncBucketData[]> PendingAsync(string owner, CancellationToken cancellationToken)
    {
        var rows = await database.Set<HealthSyncBucket>().AsNoTracking().Where(x => x.OwnerId == owner && x.Dirty)
            .OrderBy(x => x.StartMilliseconds).ThenBy(x => x.Metric).ThenBy(x => x.TimeZoneId).Take(100).ToArrayAsync(cancellationToken);
        var result = new List<HealthSyncBucketData>();
        var count = 0;
        foreach (var row in rows)
        {
            var excluded = await ExcludedAsync(owner, row, cancellationToken);
            if (result.Count > 0 && count + excluded.Length > 10_000) break;
            result.Add(Bucket(row, excluded)); count += excluded.Length;
        }
        return result.ToArray();
    }

    /// <summary>Новый часовой пояс запрашивает нативную сводку; сервер не пересчитывает её суммированием сырых источников.</summary>
    private async Task PrepareBucketsAsync(string owner, DateTimeOffset start, DateTimeOffset end, string[] metrics, TimeZoneInfo zone, CancellationToken cancellationToken)
    {
        var additive = metrics.Intersect(_additive).ToArray();
        if (additive.Length == 0) return;
        await using var transaction = await database.Database.BeginTransactionAsync(
            database.Database.IsNpgsql() ? IsolationLevel.ReadCommitted : IsolationLevel.Serializable, cancellationToken);
        try
        {
            if (database.Database.IsNpgsql()) await database.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({owner}, 0))", cancellationToken);
            var account = await database.Set<HealthSyncOwner>().FindAsync([owner], cancellationToken);
            if (account is null) return;
            var firstDay = TimeZoneInfo.ConvertTime(start, zone).Date;
            var lastDay = TimeZoneInfo.ConvertTime(end.AddTicks(-1), zone).Date;
            var existing = await database.Set<HealthSyncBucket>().Where(x => x.OwnerId == owner && x.TimeZoneId == zone.Id && x.EndMilliseconds >= start.ToUnixTimeMilliseconds() && x.StartMilliseconds <= end.ToUnixTimeMilliseconds()).ToListAsync(cancellationToken);
            var count = 0;
            foreach (var metric in additive)
                for (var day = firstDay; day <= lastDay; day = day.AddDays(1))
                {
                    var first = UtcDay(day, zone); var last = UtcDay(day.AddDays(1), zone);
                    if (last <= first || existing.Any(x => x.Metric == metric && x.StartMilliseconds == first)) continue;
                    if (!await database.Set<HealthSyncSample>().AnyAsync(x => x.OwnerId == owner && !x.Deleted && x.Metric == metric && x.StartMilliseconds < last && x.EndMilliseconds >= first, cancellationToken)) continue;
                    account.Revision++;
                    database.Add(new HealthSyncBucket { OwnerId = owner, Metric = metric, TimeZoneId = zone.Id, StartMilliseconds = first, EndMilliseconds = last, Revision = account.Revision });
                    count++;
                }
            if (count + await database.Set<HealthSyncBucket>().CountAsync(x => x.OwnerId == owner, cancellationToken) > 20_000) throw Failure(409, "health_sync_limit");
            await database.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        }
        finally { database.ChangeTracker.Clear(); }
    }

    /// <summary>Проверяет типы, границы и календарные интервалы до начала записи.</summary>
    private TimeZoneInfo Validate(HealthSyncBatch batch)
    {
        if (batch is null || batch.DeviceId == Guid.Empty || batch.BatchId == Guid.Empty || batch.Sequence < 1 || batch.ObservedAt > clock.GetUtcNow().AddMinutes(5) ||
            batch.TimeZoneId is not { Length: > 0 and <= 80 } || batch.Quantities is null || batch.Sleep is null || batch.DeletedIds is null || batch.Aggregates is null || batch.Aggregates.Length > 100) throw Failure(400, "invalid_health_sync");
        TimeZoneInfo zone;
        try { zone = TimeZoneInfo.FindSystemTimeZoneById(batch.TimeZoneId); }
        catch (TimeZoneNotFoundException) { throw Failure(400, "invalid_health_sync"); }
        catch (InvalidTimeZoneException) { throw Failure(400, "invalid_health_sync"); }
        var ids = batch.Quantities.Select(x => x?.Id ?? Guid.Empty).Concat(batch.Sleep.Select(x => x?.Id ?? Guid.Empty)).Concat(batch.DeletedIds).ToArray();
        if (ids.Length > 1000 || ids.Contains(Guid.Empty) || ids.Distinct().Count() != ids.Length || batch.Aggregates.Any(x => x is null || x.Bucket is null) ||
            batch.Aggregates.Select(x => (x.Bucket.Metric, x.Bucket.TimeZoneId, x.Bucket.Start)).Distinct().Count() != batch.Aggregates.Length) throw Failure(400, "invalid_health_sync");
        foreach (var value in batch.Quantities)
        {
            if (value is null || !_metrics.Contains(value.Metric) || value.Metric == "sleep" || !Accepts(value.Metric, value.Value)) throw Failure(400, "invalid_health_sync");
            ValidateSample(value.Start, value.End, value.SourceId, value.SourceName);
        }
        foreach (var value in batch.Sleep)
        {
            if (value is null || value.End <= value.Start || value.AsleepSeconds is not null || value.Segments is not { Count: 1 } || value.Segments[0] is not { } phase ||
                phase.Id != value.Id || phase.Start != value.Start || phase.End != value.End || phase.Stage is not ("inBed" or "awake" or "core" or "deep" or "rem" or "unspecified")) throw Failure(400, "invalid_health_sync");
            ValidateSample(value.Start, value.End, value.SourceId, value.SourceName);
        }
        foreach (var value in batch.Aggregates)
        {
            var bucket = value.Bucket;
            if (!_additive.Contains(bucket.Metric) || bucket.Revision < 1 || bucket.ExcludedIds is null || bucket.ExcludedIds.Length > 10_000 || bucket.ExcludedIds.Distinct().Count() != bucket.ExcludedIds.Length || bucket.TimeZoneId != zone.Id || bucket.End <= bucket.Start || bucket.End - bucket.Start > TimeSpan.FromHours(26) ||
                UtcDay(TimeZoneInfo.ConvertTime(bucket.Start, zone).Date, zone) != bucket.Start.ToUnixTimeMilliseconds() ||
                UtcDay(TimeZoneInfo.ConvertTime(bucket.Start, zone).Date.AddDays(1), zone) != bucket.End.ToUnixTimeMilliseconds() || value.Value is { } number && !Accepts(bucket.Metric, number)) throw Failure(400, "invalid_health_bucket");
        }
        return zone;
    }
    /// <summary>Проверяет единицы и реальные границы величины.</summary>
    private static bool Accepts(string metric, double value) => double.IsFinite(value) && metric switch
    {
        "steps" => value >= 0 && value <= 1_000_000 && Math.Truncate(value) == value,
        "bodyWeight" => value > 0 && value <= 1000,
        "heartRate" or "restingHeartRate" => value >= 1 && value <= 300,
        "bodyFatPercentage" or "bloodOxygen" => value >= 0 && value <= 100,
        "distance" => value >= 0 && value <= 10_000_000,
        _ => value >= 0 && value <= 100_000
    };
    /// <summary>Не допускает неограниченный источник, будущее измерение или некорректную длительность.</summary>
    private void ValidateSample(DateTimeOffset start, DateTimeOffset end, string source, string name)
    {
        if (start < DateTimeOffset.MinValue.AddDays(8) || end < start || end - start > TimeSpan.FromDays(7) || end > clock.GetUtcNow().AddMinutes(5) || source is not { Length: > 0 and <= 1024 } || name is not { Length: > 0 and <= 200 }) throw Failure(400, "invalid_health_sync");
    }
    /// <summary>Создаёт запись численного sample, не преобразуя дневную статистику в исходный замер.</summary>
    private static HealthSyncSample Sample(string owner, HealthQuantity value) => new() { OwnerId = owner, Id = value.Id, Metric = value.Metric, StartMilliseconds = value.Start.ToUnixTimeMilliseconds(), EndMilliseconds = value.End.ToUnixTimeMilliseconds(), Value = value.Value, SourceId = value.SourceId, SourceName = value.SourceName };
    /// <summary>Сохраняет реальную фазу с исходным UUID HealthKit.</summary>
    private static HealthSyncSample Sample(string owner, HealthSleepRecord value) => new() { OwnerId = owner, Id = value.Id, Metric = "sleep", StartMilliseconds = value.Start.ToUnixTimeMilliseconds(), EndMilliseconds = value.End.ToUnixTimeMilliseconds(), Stage = value.Segments[0].Stage, SourceId = value.SourceId, SourceName = value.SourceName };
    /// <summary>Нативные HealthKit samples неизменяемы; изменение требует нового UUID.</summary>
    private static bool Same(HealthSyncSample a, HealthSyncSample b) => a.Metric == b.Metric && a.StartMilliseconds == b.StartMilliseconds && a.EndMilliseconds == b.EndMilliseconds && a.Value == b.Value && a.SourceId == b.SourceId && a.Stage == b.Stage;
    /// <summary>Формирует сравнимую версию дневного интервала.</summary>
    private static HealthSyncBucketData Bucket(HealthSyncBucket value, Guid[] excluded) => new(value.Metric, Date(value.StartMilliseconds), Date(value.EndMilliseconds), value.TimeZoneId, value.Revision, excluded);
    /// <summary>Точные UUID удалений позволяют HealthKit исключить их до завершения межустройственной доставки iCloud.</summary>
    private async Task<Guid[]> ExcludedAsync(string owner, HealthSyncBucket bucket, CancellationToken cancellationToken)
    {
        var ids = await database.Set<HealthSyncSample>().AsNoTracking().Where(x => x.OwnerId == owner && x.Deleted && x.Metric == bucket.Metric && x.StartMilliseconds < bucket.EndMilliseconds && x.EndMilliseconds >= bucket.StartMilliseconds)
            .Select(x => x.Id).Take(10_001).ToArrayAsync(cancellationToken);
        if (ids.Length > 10_000) throw Failure(413, "health_sync_limit");
        return ids.Order().ToArray();
    }
    /// <summary>Стабилизирует UUID сводки между устройствами и повторными чтениями.</summary>
    private static Guid BucketId(HealthSyncBucket value) => new(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes($"appleHealth|{value.Metric}|{value.TimeZoneId}|{value.StartMilliseconds}"))[..16]);
    /// <summary>Преобразует начало локального дня в UTC, учитывая timezone.</summary>
    private static long UtcDay(DateTime value, TimeZoneInfo zone)
    {
        var local = DateTime.SpecifyKind(value, DateTimeKind.Unspecified);
        for (var minute = 0; zone.IsInvalidTime(local) && minute < 2880; minute++) local = local.AddMinutes(1);
        var offset = zone.IsAmbiguousTime(local) ? zone.GetAmbiguousTimeOffsets(local).Max() : zone.GetUtcOffset(local);
        return new DateTimeOffset(local, offset).ToUnixTimeMilliseconds();
    }
    /// <summary>Собирает только фактические интервалы в отчёты от полудня до полудня, сохраняя все источники.</summary>
    private static HealthSleepRecord[] SleepRecords(HealthSyncSample[] rows, TimeZoneInfo zone)
    {
        var groups = new Dictionary<(string Source, long Start, long End), List<HealthSleepSegment>>();
        var names = rows.GroupBy(x => x.SourceId).ToDictionary(x => x.Key, x => x.First().SourceName);
        foreach (var row in rows)
        {
            var local = TimeZoneInfo.ConvertTime(Date(row.StartMilliseconds), zone).DateTime;
            var first = local.Hour < 12 ? local.Date.AddDays(-1) : local.Date;
            for (var date = first; UtcDay(date.AddHours(12), zone) < row.EndMilliseconds; date = date.AddDays(1))
            {
                var firstMillisecond = UtcDay(date.AddHours(12), zone);
                var lastMillisecond = UtcDay(date.AddDays(1).AddHours(12), zone);
                var start = Math.Max(firstMillisecond, row.StartMilliseconds); var end = Math.Min(lastMillisecond, row.EndMilliseconds);
                if (end <= start) continue;
                var key = (row.SourceId, firstMillisecond, lastMillisecond);
                if (!groups.TryGetValue(key, out var phases)) { phases = []; groups.Add(key, phases); }
                phases.Add(new(row.Id, Date(start), Date(end), row.Stage!));
                if (phases.Count > 10_000) throw Failure(502, "health_history_too_large");
            }
        }
        if (groups.Count > 1000 || groups.Values.Sum(x => x.Count) > 100_000) throw Failure(502, "health_history_too_large");
        return groups.Select(pair => new HealthSleepRecord(new Guid(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes($"appleHealth|sleep|{pair.Key.Source}|{pair.Key.Start}"))[..16]),
            pair.Value.Min(x => x.Start), pair.Value.Max(x => x.End), null, pair.Key.Source, names[pair.Key.Source], pair.Value.OrderBy(x => x.Start).ThenBy(x => x.Id).ToArray())).ToArray();
    }
    /// <summary>Возвращает миллисекундную дату из структурированного столбца.</summary>
    private static DateTimeOffset Date(long value) => DateTimeOffset.FromUnixTimeMilliseconds(value);
    /// <summary>Не раскрывает значения health data во внешнем ответе.</summary>
    private static HealthDataException Failure(int status, string code) => new(status, code);
}

/// <summary>Читает синхронизированную историю HealthKit через тот же контракт, что Mi Fitness.</summary>
public sealed class AppleHealthHistoryProvider(HealthSyncStorage storage) : IHealthDataProvider
{
    /// <summary>Идентификатор источника в общем Swift/C# контракте.</summary>
    public string Id => "appleHealth";
    /// <summary>Предоставляет только данные владельца, проверенного Backend.</summary>
    public Task<HealthDataSnapshot> ReadAsync(string owner, DateTimeOffset start, DateTimeOffset end, string[] metrics, TimeZoneInfo timeZone, CancellationToken cancellationToken) => storage.ReadAsync(owner, start, end, metrics, timeZone, cancellationToken);
}
