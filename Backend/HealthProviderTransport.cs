using System.Net;
using System.Text.Json;

namespace FitLife.Backend;

/// <summary>Ограничивает чтение недоверенных ответов облака и внутреннего сервиса.</summary>
internal static class HealthProviderTransport
{
    /// <summary>Не допускает неограниченное тело, malformed JSON и выдачу внешних диагностических сообщений.</summary>
    internal static async Task<JsonDocument> ReadAsync(HttpResponseMessage response, int maximumBytes, CancellationToken cancellationToken)
    {
        if (response.StatusCode == HttpStatusCode.Unauthorized) throw new HealthDataException(403, "health_not_connected");
        if (response.StatusCode == HttpStatusCode.Forbidden) throw new HealthDataException(403, "health_permission_required");
        if (response.StatusCode == HttpStatusCode.TooManyRequests) throw new HealthDataException(429, "health_rate_limited");
        if (!response.IsSuccessStatusCode || response.Content.Headers.ContentLength > maximumBytes)
            throw new HealthDataException(503, "health_provider_unavailable");
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var memory = new MemoryStream();
        var buffer = new byte[8192];
        while (true)
        {
            var count = await stream.ReadAsync(buffer, cancellationToken);
            if (count == 0) break;
            if (memory.Length + count > maximumBytes) throw new HealthDataException(502, "invalid_health_response");
            await memory.WriteAsync(buffer.AsMemory(0, count), cancellationToken);
        }
        try
        {
            var document = JsonDocument.Parse(memory.ToArray());
            if (document.RootElement.ValueKind != JsonValueKind.Object) { document.Dispose(); throw new HealthDataException(502, "invalid_health_response"); }
            return document;
        }
        catch (JsonException) { throw new HealthDataException(502, "invalid_health_response"); }
    }
}

/// <summary>Получает access token у Authentication по закрытому HTTP-контракту, не читая Auth-БД.</summary>
public sealed class HealthProviderGrants(HttpClient http, IConfiguration configuration)
{
    /// <summary>Принимает только UUID владельца; refresh token и секрет Xiaomi остаются в Authentication.</summary>
    internal async Task<HealthProviderGrant> GetAsync(string owner, CancellationToken cancellationToken)
    {
        if (!Guid.TryParse(owner, out var id)) throw new HealthDataException(400, "invalid_health_request");
        var root = configuration["HealthProviders:AuthenticationUrl"] ?? "http://authentication:8080/";
        if (!Uri.TryCreate(root, UriKind.Absolute, out var address) || address.Scheme is not ("http" or "https") ||
            address.UserInfo.Length > 0 || address.Query.Length > 0 || address.Fragment.Length > 0 || address.AbsolutePath != "/")
            throw new HealthDataException(503, "health_provider_unavailable");
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(address, $"internal/health/mi-fitness/{id}/grant"));
        request.Headers.Add("X-Service-Key", configuration["Backend:ServiceKey"]);
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(20));
        try
        {
            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode == HttpStatusCode.NotFound) throw new HealthDataException(403, "health_not_connected");
            // Внутренний 401 означает ошибку настройки сервисов, а не выход пользователя из FitLife.
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw new HealthDataException(503, "health_provider_unavailable");
            using var json = await HealthProviderTransport.ReadAsync(response, 65_536, deadline.Token);
            var grant = json.Deserialize<HealthProviderGrant>(JsonSerializerOptions.Web);
            if (grant is null || string.IsNullOrEmpty(grant.AccessToken) || grant.AccessToken.Length > 32768 ||
                !long.TryParse(grant.ClientId, out var clientId) || clientId <= 0 || grant.Metrics is null)
                throw new HealthDataException(502, "invalid_health_response");
            return grant;
        }
        catch (JsonException) { throw new HealthDataException(502, "invalid_health_response"); }
        catch (HttpRequestException) { throw new HealthDataException(503, "health_provider_unavailable"); }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) { throw new HealthDataException(503, "health_provider_unavailable"); }
    }
}
