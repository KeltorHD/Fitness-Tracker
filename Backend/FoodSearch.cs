using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace FitnessTracker.Backend;

/// <summary>Проксирует публичный каталог perek.us, хранит ключ только на сервере и ограничивает общий бюджет.</summary>
internal sealed class FoodSearch(IHttpClientFactory clients, IConfiguration config, TimeProvider time) : IDisposable
{
    private readonly SemaphoreSlim _gate = new(1);
    private readonly Dictionary<string, (DateTimeOffset Expires, FoodSearchResult Result)> _cache = [];
    private readonly Queue<DateTimeOffset> _calls = new();
    private DateTimeOffset _blockedUntil;
    private DateOnly _day;
    private int _dailyCalls;

    /// <summary>Ищет название или точный штрихкод; неудачные и неполные ответы не становятся вымышленными КБЖУ.</summary>
    public async Task<FoodSearchResult> SearchAsync(string query, CancellationToken cancellationToken)
    {
        query = query.Trim();
        var barcode = query.All(char.IsAsciiDigit);
        if (query.Length is < 2 or > 100 || (barcode && query.Length is < 8 or > 14))
            return new(400, []);
        var key = config["FoodSearch:PerekApiKey"];
        if (string.IsNullOrWhiteSpace(key)) return new(503, []);
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var now = time.GetUtcNow();
            foreach (var expired in _cache.Where(x => x.Value.Expires <= now).Select(x => x.Key).ToArray()) _cache.Remove(expired);
            if (_cache.TryGetValue(query, out var cached)) return cached.Result;
            if (now < _blockedUntil) return new(429, [], Math.Max(1, (int)Math.Ceiling((_blockedUntil - now).TotalSeconds)));
            var day = DateOnly.FromDateTime(now.UtcDateTime);
            if (day != _day) { _day = day; _dailyCalls = 0; }
            while (_calls.TryPeek(out var call) && now - call >= TimeSpan.FromMinutes(1)) _calls.Dequeue();
            if (_dailyCalls >= 450 || _calls.Count >= 18) return new(429, [], 60);
            _calls.Enqueue(now);
            _dailyCalls++;
            var path = barcode ? $"barcode/{query}" : $"search?q={Uri.EscapeDataString(query)}&market=ru&limit=20";
            using var request = new HttpRequestMessage(HttpMethod.Get, "https://perek.us/api/v1/foods/" + path);
            request.Headers.Add("X-Api-Key", key);
            using var response = await clients.CreateClient("perek").SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                var retry = response.Headers.RetryAfter?.Delta ??
                    (response.Headers.RetryAfter?.Date - now) ?? TimeSpan.FromMinutes(1);
                retry = TimeSpan.FromSeconds(Math.Clamp(retry.TotalSeconds, 1, 86400));
                _blockedUntil = now + retry;
                return new(429, [], (int)Math.Ceiling(retry.TotalSeconds));
            }
            if (response.StatusCode == HttpStatusCode.NotFound) return new(200, []);
            if (!response.IsSuccessStatusCode) return new(503, []);
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var bytes = new MemoryStream();
            var buffer = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(buffer, cancellationToken)) > 0)
            {
                if (bytes.Length + count > 1_000_000) return new(502, []);
                bytes.Write(buffer, 0, count);
            }
            var payload = JsonSerializer.Deserialize<PerekResponse>(bytes.ToArray());
            if (payload is null || (barcode ? payload.Food is null : payload.Foods is null)) return new(502, []);
            var products = ((barcode ? new[] { payload.Food } : payload.Foods) ?? [])
                .OfType<PerekProduct>().Select(p => Convert(p, barcode ? query : null)).OfType<FoodSearchProduct>().DistinctBy(p => p.Id).Take(20).ToArray();
            var result = new FoodSearchResult(200, products);
            // Ограниченный кеш — только ответы пользовательских запросов, не отдельный общий справочник.
            if (_cache.Count < 512) _cache[query] = (now.AddHours(1), result);
            return result;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) { return new(503, []); }
        catch (HttpRequestException) { return new(503, []); }
        catch (JsonException) { return new(502, []); }
        finally { _gate.Release(); }
    }

    /// <summary>Проверяет единицы, полноту КБЖУ и источник до передачи карточки клиенту.</summary>
    private static FoodSearchProduct? Convert(PerekProduct product, string? barcode)
    {
        var values = product.Per100;
        var unit = product.Unit switch { "г" => "grams", "мл" => "milliliters", _ => null };
        var limit = unit == "milliliters" ? 1000 : 100;
        if (unit is null || string.IsNullOrWhiteSpace(product.Name) || product.Name.Length > 300 ||
            product.Brand?.Name?.Length > 300 || values is null ||
            !Valid(values.Kcal, limit * 10) || !Valid(values.Protein, limit) || !Valid(values.Fat, limit) || !Valid(values.Carbs, limit) ||
            values.Protein + values.Fat + values.Carbs > limit * 1.05) return null;
        var code = barcode ?? product.Barcodes?.FirstOrDefault(x => x.Length is >= 8 and <= 14 && x.All(char.IsAsciiDigit));
        var identity = product.Id ?? code;
        if (string.IsNullOrWhiteSpace(identity)) return null;
        var url = Uri.TryCreate(product.Url, UriKind.Absolute, out var source) && source.Scheme == "https" &&
            source.Host == "perek.us" && source.UserInfo.Length == 0 ? source.AbsoluteUri : "https://perek.us/food/shtrihkod";
        return new("perek:" + System.Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(identity))),
            product.Name, product.Brand?.Name ?? "", unit,
            new(values.Kcal!.Value, values.Protein!.Value, values.Fat!.Value, values.Carbs!.Value), url, code);
    }

    /// <summary>Не допускает отсутствующие, отрицательные и нечисловые нутриенты.</summary>
    private static bool Valid(double? value, double maximum) => value is { } number && double.IsFinite(number) && number >= 0 && number <= maximum;

    /// <summary>Освобождает шлюз при остановке сервера.</summary>
    public void Dispose() => _gate.Dispose();

    /// <summary>Ответ поставщика для поиска или точного штрихкода.</summary>
    private sealed record PerekResponse([property: JsonPropertyName("food")] PerekProduct? Food, [property: JsonPropertyName("foods")] PerekProduct[]? Foods);
    /// <summary>Необязательные поля исходной карточки поставщика.</summary>
    private sealed record PerekProduct(
        [property: JsonPropertyName("id")] string? Id,
        [property: JsonPropertyName("name")] string? Name,
        [property: JsonPropertyName("brand")] PerekBrand? Brand,
        [property: JsonPropertyName("unit")] string? Unit,
        [property: JsonPropertyName("per100")] PerekValues? Per100,
        [property: JsonPropertyName("url")] string? Url,
        [property: JsonPropertyName("barcodes")] string[]? Barcodes);
    /// <summary>Имя производителя из ответа поставщика.</summary>
    private sealed record PerekBrand([property: JsonPropertyName("name")] string? Name);
    /// <summary>Нутриенты на 100 г или 100 мл без подстановки отсутствующих значений.</summary>
    private sealed record PerekValues(
        [property: JsonPropertyName("kcal")] double? Kcal,
        [property: JsonPropertyName("protein")] double? Protein,
        [property: JsonPropertyName("fat")] double? Fat,
        [property: JsonPropertyName("carbs")] double? Carbs);
}

/// <summary>Проверенные значения на 100 граммов либо миллилитров для клиента iOS.</summary>
internal sealed record FoodSearchNutrients(double Calories, double Protein, double Fat, double Carbohydrates);
/// <summary>Карточка с устойчивым идентификатором, точным штрихкодом и обязательным источником.</summary>
internal sealed record FoodSearchProduct(string Id, string Name, string Brand, string Unit, FoodSearchNutrients Per100Units, string SourceURL, string? Barcode);
/// <summary>Результат прокси без секретов и внутренних сообщений поставщика.</summary>
internal sealed record FoodSearchResult(int Status, FoodSearchProduct[] Products, int RetryAfter = 0);
