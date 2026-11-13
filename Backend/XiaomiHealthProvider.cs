using System.Buffers.Binary;
using System.Globalization;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;

namespace FitLife.Backend;

/// <summary>Читает официальный Xiaomi Health API, сохраняя отчётные значения и источник каждого измерения.</summary>
public sealed class XiaomiHealthProvider(HttpClient http, HealthProviderGrants grants, TimeProvider clock) : IHealthDataProvider
{
    /// <summary>Стабильное имя провайдера в Swift/C# контракте.</summary>
    public string Id => "miFitness";
    private static readonly IReadOnlyDictionary<string, string[]> _types = new Dictionary<string, string[]>
    {
        ["com.xiaomi.weight.instantaneous"] = ["bodyWeight", "bodyFatPercentage"],
        ["com.xiaomi.heart_rate.delta"] = ["heartRate"],
        ["com.xiaomi.resting_heart_rate.instantaneous"] = ["restingHeartRate"],
        ["com.xiaomi.spo2.instantaneous"] = ["bloodOxygen"]
    };

    /// <summary>Получает только выданные категории; один снимок заменяет прежнее окно, не добавляя дубликаты.</summary>
    public async Task<HealthDataSnapshot> ReadAsync(string owner, DateTimeOffset start, DateTimeOffset end,
        string[] metrics, TimeZoneInfo timeZone, CancellationToken cancellationToken)
    {
        if (end <= start || end - start > TimeSpan.FromDays(32) || end > clock.GetUtcNow().AddMinutes(1) ||
            metrics.Length == 0 || metrics.Length > 10 || metrics.Distinct().Count() != metrics.Length ||
            metrics.Except(_types.Values.SelectMany(value => value).Concat(["steps", "totalEnergy", "sleep"])).Any())
            throw new HealthDataException(400, "invalid_health_request");
        var grant = await grants.GetAsync(owner, cancellationToken);
        var allowed = metrics.Intersect(grant.Metrics).Order().ToArray();
        if (allowed.Length == 0) throw new HealthDataException(403, "health_permission_required");
        var quantities = new Dictionary<Guid, (HealthQuantity Value, long Modified)>();
        var sleep = new Dictionary<Guid, (HealthSleepRecord Value, long Modified)>();
        // API ограничивает sampling и health records тридцатью сутками, даже если diary окно пересекает DST.
        for (var cursor = start; cursor < end;)
        {
            var until = cursor.AddDays(29) < end ? cursor.AddDays(29) : end;
            foreach (var (type, categories) in _types.Where(item => item.Value.Intersect(allowed).Any()))
            {
                await ReadPagesAsync("healthkit/dataSources/dataPoints", type, cursor, until, grant, root =>
                {
                    foreach (var point in Points(root))
                    {
                        if (String(point, "dataTypeName") != type) throw Invalid();
                        foreach (var metric in categories.Intersect(allowed)) AddQuantity(quantities, point, metric);
                    }
                }, cancellationToken);
            }
            if (allowed.Contains("sleep"))
                await ReadPagesAsync("healthkit/healthRecords", "com.xiaomi.sleep.health", cursor, until, grant, root =>
                {
                    foreach (var record in Array(root, "healthRecords")) AddSleep(sleep, record);
                }, cancellationToken);
            cursor = until;
        }
        if (allowed.Contains("steps") || allowed.Contains("totalEnergy"))
            await ReadDailyAsync(start, end, allowed, grant, timeZone, quantities, cancellationToken);
        return new(Id, start, end, clock.GetUtcNow(), allowed,
            quantities.Values.Select(item => item.Value).Where(item => item.Start <= end && item.End >= start &&
                (item.Metric is "steps" or "totalEnergy" || item.End <= end))
                .OrderBy(item => item.Start).ThenBy(item => item.Id).ToArray(),
            sleep.Values.Select(item => item.Value).Where(item => item.Start < end && item.End > start && item.End <= end)
                .OrderBy(item => item.Start).ThenBy(item => item.Id).ToArray());
    }

    /// <summary>Статистику шагов получает уже объединённой Xiaomi; данные разных устройств не суммируются повторно.</summary>
    private async Task ReadDailyAsync(DateTimeOffset start, DateTimeOffset end, string[] metrics, HealthProviderGrant grant,
        TimeZoneInfo timeZone, Dictionary<Guid, (HealthQuantity Value, long Modified)> quantities, CancellationToken cancellationToken)
    {
        var first = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(start, timeZone).DateTime);
        var last = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(end.AddTicks(-1), timeZone).DateTime);
        var types = new List<string>();
        if (metrics.Contains("steps")) types.Add("com.xiaomi.steps.total");
        if (metrics.Contains("totalEnergy")) types.Add("com.xiaomi.calories.total");
        for (var day = first; day <= last;)
        {
            var until = day.AddDays(6) < last ? day.AddDays(6) : last;
            using var response = await GetAsync("healthkit/aggregate/dailies", new()
            {
                ["startDay"] = day.ToString("yyyyMMdd", CultureInfo.InvariantCulture),
                ["endDay"] = until.ToString("yyyyMMdd", CultureInfo.InvariantCulture),
                ["dataTypes"] = string.Join(',', types),
                ["zoneName"] = timeZone.Id
            }, grant, cancellationToken);
            foreach (var point in Points(response.RootElement))
            {
                var type = String(point, "dataTypeName");
                if (type == "com.xiaomi.steps.total" && metrics.Contains("steps")) AddQuantity(quantities, point, "steps", fused: true);
                if (type == "com.xiaomi.calories.total" && metrics.Contains("totalEnergy")) AddQuantity(quantities, point, "totalEnergy", fused: true);
            }
            day = until.AddDays(1);
        }
    }

    /// <summary>Ограничивает страницы, обнаруживает повтор cursor и передаёт отмену каждому HTTP-запросу.</summary>
    private async Task ReadPagesAsync(string path, string type, DateTimeOffset start, DateTimeOffset end,
        HealthProviderGrant grant, Action<JsonElement> consume, CancellationToken cancellationToken)
    {
        string? cursor = null;
        var seen = new HashSet<string>();
        for (var page = 0; page < 128; page++)
        {
            var query = new Dictionary<string, string?>
            {
                ["startTime"] = start.ToUnixTimeMilliseconds().ToString(CultureInfo.InvariantCulture),
                ["endTime"] = end.ToUnixTimeMilliseconds().ToString(CultureInfo.InvariantCulture),
                ["dataTypeName"] = type,
                ["limit"] = "1000"
            };
            if (cursor is not null) query["cursor"] = cursor;
            using var response = await GetAsync(path, query, grant, cancellationToken);
            consume(response.RootElement);
            var next = response.RootElement.TryGetProperty("cursor", out var token) ? token.ValueKind switch
            {
                JsonValueKind.String => token.GetString(),
                JsonValueKind.Number => token.GetRawText(),
                JsonValueKind.Null => null,
                _ => throw Invalid()
            } : null;
            var hasMore = response.RootElement.TryGetProperty("hasMore", out var more) ? more.ValueKind switch
            {
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                _ => throw Invalid()
            } : !string.IsNullOrEmpty(next);
            if (!hasMore) return;
            if (string.IsNullOrEmpty(next) || next.Length > 1000 || !seen.Add(next)) throw Invalid();
            cursor = next;
        }
        throw new HealthDataException(502, "health_history_too_large");
    }

    /// <summary>Отправляет credentials только фиксированному HTTPS origin Xiaomi, с новым nonce каждого запроса.</summary>
    private async Task<JsonDocument> GetAsync(string path, Dictionary<string, string?> query, HealthProviderGrant grant,
        CancellationToken cancellationToken)
    {
        var url = QueryHelpers.AddQueryString("https://hlthopen.io.mi.com/" + path, query);
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", grant.AccessToken);
        request.Headers.Add("X-Client-ID", grant.ClientId);
        var nonce = RandomNumberGenerator.GetBytes(12);
        BinaryPrimitives.WriteUInt32BigEndian(nonce.AsSpan(8), checked((uint)(clock.GetUtcNow().ToUnixTimeSeconds() / 60)));
        request.Headers.Add("X-Client-Nonce", WebEncoders.Base64UrlEncode(nonce));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(20));
        try
        {
            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            var json = await HealthProviderTransport.ReadAsync(response, 4 * 1024 * 1024, deadline.Token);
            if (json.RootElement.TryGetProperty("code", out var code) && (code.ValueKind != JsonValueKind.Number || !code.TryGetInt64(out var value) || value != 0))
            {
                json.Dispose();
                throw new HealthDataException(503, "health_provider_unavailable");
            }
            return json;
        }
        catch (HttpRequestException) { throw new HealthDataException(503, "health_provider_unavailable"); }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) { throw new HealthDataException(503, "health_provider_unavailable"); }
    }

    /// <summary>Извлекает группы из документированного ответа dataPoints/dailies без обхода произвольного JSON.</summary>
    private static IEnumerable<JsonElement> Points(JsonElement root) => Array(root, "group")
        .SelectMany(group => Array(group, "dataSet")).SelectMany(set => Array(set, "dataPoints"));

    /// <summary>Отсутствующая коллекция считается повреждённым ответом, а не успешным пустым чтением.</summary>
    private static JsonElement.ArrayEnumerator Array(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var array) && array.ValueKind == JsonValueKind.Array ? array.EnumerateArray() : throw Invalid();

    /// <summary>Читает текст строго, не преобразуя чужие JSON-типы в значения.</summary>
    private static string? String(JsonElement element, string name) => element.ValueKind != JsonValueKind.Object ? throw Invalid() :
        element.TryGetProperty(name, out var field) ? field.ValueKind == JsonValueKind.String ? field.GetString() : throw Invalid() : null;

    /// <summary>Ищет значение по имени поля; отсутствие optional поля остаётся null.</summary>
    private static double? Number(JsonElement point, string name)
    {
        var fields = Array(point, "value").Where(item => String(item, "fieldName") == name).ToArray();
        if (fields.Length == 0) return null;
        if (fields.Length != 1) throw Invalid();
        var field = fields[0];
        var integer = field.TryGetProperty("integerValue", out var intValue);
        var floating = field.TryGetProperty("floatValue", out var floatValue);
        if (integer == floating) throw Invalid();
        var value = integer ? intValue : floatValue;
        if (value.ValueKind != JsonValueKind.Number || !value.TryGetDouble(out var number) || !double.IsFinite(number)) throw Invalid();
        return number;
    }

    /// <summary>Переводит миллисекундную дату без предположения, что Unix seconds имеют тот же масштаб.</summary>
    private static DateTimeOffset Date(JsonElement element, string name)
    {
        if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty(name, out var field) || field.ValueKind != JsonValueKind.Number || !field.TryGetInt64(out var value)) throw Invalid();
        try { return DateTimeOffset.FromUnixTimeMilliseconds(value); }
        catch (ArgumentOutOfRangeException) { throw Invalid(); }
    }

    /// <summary>Сохраняет постоянную identity точки и выбирает только более новую исправленную версию.</summary>
    private static void AddQuantity(Dictionary<Guid, (HealthQuantity Value, long Modified)> result, JsonElement point, string metric, bool fused = false)
    {
        var field = metric switch
        {
            "steps" => "steps",
            "totalEnergy" => "calories_total",
            "bodyWeight" => "weight",
            "bodyFatPercentage" => "body_fat_rate",
            "heartRate" or "restingHeartRate" => "bpm",
            "bloodOxygen" => "spo2",
            _ => throw Invalid()
        };
        var value = Number(point, field);
        if (value is null) return;
        var valid = metric switch
        {
            "steps" => value >= 0 && value <= 1_000_000 && Math.Truncate(value.Value) == value,
            "bodyWeight" => value > 0 && value <= 1000,
            "heartRate" or "restingHeartRate" => value >= 1 && value <= 300,
            "bodyFatPercentage" or "bloodOxygen" => value >= 0 && value <= 100,
            _ => value >= 0 && value <= 100_000
        };
        var start = Date(point, "startTime");
        var end = Date(point, "endTime");
        if (!valid || end < start) throw Invalid();
        var source = fused ? "miFitness" : String(point, "originDataSourceId") ?? "miFitness";
        if (source.Length == 0 || source.Length > 1024) throw Invalid();
        var id = Identity(metric, source, start, end);
        var candidate = new HealthQuantity(id, metric, start, end, value.Value, source, "Mi Fitness");
        var modified = Modified(point);
        if (result.TryGetValue(id, out var previous))
        {
            if (modified < previous.Modified) return;
            if (modified == previous.Modified && previous.Value != candidate) throw Invalid();
        }
        result[id] = (candidate, modified);
        if (result.Count > 100_000) throw new HealthDataException(502, "health_history_too_large");
    }

    /// <summary>Переносит общий отчёт сна и реальные подинтервалы; неизвестные состояния не превращает в сон.</summary>
    private static void AddSleep(Dictionary<Guid, (HealthSleepRecord Value, long Modified)> result, JsonElement record)
    {
        if (String(record, "dataTypeName") != "com.xiaomi.sleep.health") throw Invalid();
        var start = Milliseconds(Number(record, "bedtime")) ?? Date(record, "startTime");
        var end = Milliseconds(Number(record, "wakeup_time")) ?? Date(record, "endTime");
        var duration = Number(record, "all_sleep_duration") * 60;
        if (end <= start || end - start > TimeSpan.FromDays(7) || duration < 0 || duration > (end - start).TotalSeconds) throw Invalid();
        var source = String(record, "originDataSourceId") ?? "miFitness";
        if (source.Length == 0 || source.Length > 1024) throw Invalid();
        var id = Identity("sleep", source, start, end);
        var segments = new Dictionary<Guid, HealthSleepSegment>();
        if (record.TryGetProperty("subData", out var data) && data.ValueKind != JsonValueKind.Object) throw Invalid();
        if (record.TryGetProperty("subData", out data) && data.TryGetProperty("com.xiaomi.sleep_state.delta", out var phases))
        {
            foreach (var phase in Array(phases, "dataPoints"))
            {
                var state = Number(phase, "sleep_state");
                var stage = state switch { 0 or 5 => "awake", 2 => "deep", 3 => "core", 4 => "rem", _ => null };
                if (stage is null) continue;
                var phaseStart = Date(phase, "startTime");
                var phaseEnd = Date(phase, "endTime");
                if (phaseStart < start || phaseEnd > end || phaseEnd <= phaseStart) throw Invalid();
                var segmentId = Identity("sleep:" + stage, source, phaseStart, phaseEnd);
                segments[segmentId] = new(segmentId, phaseStart, phaseEnd, stage);
                if (segments.Count > 10_000) throw new HealthDataException(502, "health_history_too_large");
            }
        }
        var candidate = new HealthSleepRecord(id, start, end, duration, source, "Mi Fitness", segments.Values.OrderBy(item => item.Start).ThenBy(item => item.Id).ToArray());
        var modified = Modified(record);
        if (result.TryGetValue(id, out var previous))
        {
            if (modified < previous.Modified) return;
            if (modified == previous.Modified && (previous.Value with { Segments = candidate.Segments } != candidate ||
                !previous.Value.Segments.SequenceEqual(candidate.Segments))) throw Invalid();
        }
        result[id] = (candidate, modified);
        if (result.Values.Sum(item => item.Value.Segments.Count) > 100_000)
            throw new HealthDataException(502, "health_history_too_large");
        if (result.Count > 1000) throw new HealthDataException(502, "health_history_too_large");
    }

    /// <summary>Проверяет необязательный timestamp внутри value массива до преобразования в long.</summary>
    private static DateTimeOffset? Milliseconds(double? value)
    {
        if (value is null) return null;
        if (Math.Truncate(value.Value) != value || value < DateTimeOffset.MinValue.ToUnixTimeMilliseconds() || value > DateTimeOffset.MaxValue.ToUnixTimeMilliseconds()) throw Invalid();
        return DateTimeOffset.FromUnixTimeMilliseconds((long)value.Value);
    }

    /// <summary>Отсутствие modifyTime не означает разрешение произвольно смешивать противоречивые версии.</summary>
    private static long Modified(JsonElement point) => point.ValueKind != JsonValueKind.Object ? throw Invalid() : point.TryGetProperty("modifyTime", out var value)
        ? value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var time) ? time : throw Invalid() : 0;

    /// <summary>Хеш включает категорию, источник и обе границы; значение может исправляться без смены UUID.</summary>
    private static Guid Identity(string metric, string source, DateTimeOffset start, DateTimeOffset end) =>
        new(SHA256.HashData(Encoding.UTF8.GetBytes($"miFitness\n{metric}\n{source}\n{start.ToUnixTimeMilliseconds()}\n{end.ToUnixTimeMilliseconds()}"))[..16]);

    /// <summary>Не включает детали внешнего ответа в ошибку.</summary>
    private static HealthDataException Invalid() => new(502, "invalid_health_response");
}
