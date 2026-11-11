using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace FitLife.Backend;

/// <summary>Конфигурация стандартной introspection; секрет принадлежит только серверным сервисам.</summary>
internal sealed class IntrospectionOptions
{
    /// <summary>Client ID совпадает с audience API, разрешая OpenIddict раскрыть статус его access token.</summary>
    internal const string ClientId = "fitnesstracker-api";
    /// <summary>Корневой HTTPS issuer Authentication.</summary>
    public string Issuer { get; set; } = "";
    /// <summary>Отдельный секрет confidential client, не связанный с ключом удаления копий.</summary>
    public string IntrospectionClientSecret { get; set; } = "";
}

/// <summary>Сообщает о недоступной проверке без сохранения токена, секрета или ответа Auth в исключении.</summary>
internal sealed class AuthenticationUnavailableException() : Exception("Authentication service is unavailable.");

/// <summary>Запрашивает актуальный статус уже проверенного JWT по RFC 7662, без кеша и повторных отправок.</summary>
internal sealed class TokenIntrospection(HttpClient client, IOptions<IntrospectionOptions> options)
{
    private const int MAXIMUM_RESPONSE_BYTES = 16 * 1024;

    /// <summary>Возвращает active; ошибки транспорта, протокола и credentials отличает от отозванного токена.</summary>
    internal async Task<bool> IsActiveAsync(string token, CancellationToken cancellationToken)
    {
        // ResponseHeadersRead завершает HttpClient.Timeout на заголовках;
        // отдельный deadline ограничивает также чтение body и JSON.
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(client.Timeout);
        var settings = options.Value;
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(new Uri(settings.Issuer), "connect/introspect"));
        request.Content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = IntrospectionOptions.ClientId,
            ["client_secret"] = settings.IntrospectionClientSecret,
            ["token"] = token,
            ["token_type_hint"] = "access_token"
        });
        try
        {
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode != System.Net.HttpStatusCode.OK ||
                !string.Equals(response.Content.Headers.ContentType?.MediaType, "application/json", StringComparison.OrdinalIgnoreCase))
                throw new AuthenticationUnavailableException();
            await response.Content.LoadIntoBufferAsync(MAXIMUM_RESPONSE_BYTES, deadline.Token);
            var result = await response.Content.ReadFromJsonAsync<JsonElement>(deadline.Token);
            if (result.ValueKind != JsonValueKind.Object || !result.TryGetProperty("active", out var active) ||
                active.ValueKind is not (JsonValueKind.True or JsonValueKind.False) || result.TryGetProperty("error", out _) ||
                result.EnumerateObject().Count(property => property.NameEquals("active")) != 1)
                throw new AuthenticationUnavailableException();
            return active.GetBoolean();
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new AuthenticationUnavailableException();
        }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or
            NotSupportedException or ArgumentException or InvalidOperationException)
        {
            throw new AuthenticationUnavailableException();
        }
    }
}
