using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Caching.Memory;

namespace FitnessTracker.Authentication;

/// <summary>Ограничивает срок и одноразовое использование WebAuthn challenges сверх защищённой cookie Identity.</summary>
public sealed class PasskeyChallenges : IDisposable
{
    private readonly MemoryCache _cache = new(new MemoryCacheOptions { SizeLimit = 10_000 });
    private readonly object _gate = new();

    /// <summary>Запоминает назначение выданного Identity challenge на пять минут.</summary>
    public void Issue(string optionsJson, string purpose)
    {
        using var options = JsonDocument.Parse(optionsJson);
        var challenge = options.RootElement.GetProperty("challenge").GetString()
            ?? throw new InvalidOperationException("Identity did not produce a challenge.");
        lock (_gate)
            _cache.Set(challenge, purpose, new MemoryCacheEntryOptions
            { AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5), Size = 1 });
    }

    /// <summary>Атомарно забирает challenge; подпись, origin и cookie проверяет штатный Identity.</summary>
    public bool Consume(string credentialJson, string purpose)
    {
        try
        {
            using var credential = JsonDocument.Parse(credentialJson);
            var encoded = credential.RootElement.GetProperty("response").GetProperty("clientDataJSON").GetString();
            if (encoded is not { Length: > 0 and <= 8192 }) return false;
            using var data = JsonDocument.Parse(WebEncoders.Base64UrlDecode(encoded));
            var challenge = data.RootElement.GetProperty("challenge").GetString();
            if (challenge is not { Length: > 0 and <= 128 }) return false;
            lock (_gate)
            {
                if (!_cache.TryGetValue<string>(challenge, out var saved) || saved != purpose) return false;
                _cache.Remove(challenge);
                return true;
            }
        }
        catch (Exception exception) when (exception is JsonException or FormatException or KeyNotFoundException or InvalidOperationException)
        {
            return false;
        }
    }

    /// <summary>Освобождает ограниченное хранилище при завершении процесса.</summary>
    public void Dispose() => _cache.Dispose();
}
