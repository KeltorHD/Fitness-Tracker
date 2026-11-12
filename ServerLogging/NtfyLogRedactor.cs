using System.Collections;
using System.Data.Common;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;

namespace FitLife.ServerLogging;

/// <summary>Маскирует известные секреты и приватные поля перед помещением уведомления в очередь.</summary>
internal sealed class NtfyLogRedactor
{
    private const string REDACTED = "[REDACTED]";
    private const int MAXIMUM_SOURCE_LENGTH = 32_768;
    private static readonly TimeSpan _regexTimeout = TimeSpan.FromMilliseconds(100);
    private static readonly Regex _configurationSecretKey = Pattern(
        "password|passwd|(^|:)pwd$|secret|token$|privatekey|connectionstrings|(^|:)topic$");
    private static readonly Regex _sensitiveKey = Pattern(
        "password|passwd|pwd|secret|token|authorization|cookie|credential|assertion|verifier|challenge|privatekey|connectionstrings|(^|[_:])code$|^state$|^nonce$|email|username|userhandle|claims|body|payload|archive|health|commandtext|parameters|headers|request|response|principal|profile");
    private static readonly Regex _privatePayload = Pattern(
        "\"(?:workouts|templates|bodyWeights|heartRates|meals|clientDataJSON|attestationObject|claims|sub)\"\\s*:");
    private static readonly Regex _headers = Pattern(
        "\\b(?:Authorization|Cookie|Set-Cookie)\\b[\\\"' ]*[:=][^\\r\\n]*");
    private static readonly Regex _fields = Pattern(
        "(?<key>\\b(?:password|confirm[_-]?password|new[_-]?password|passwd|pwd|client[_-]?secret|access[_-]?token|refresh[_-]?token|id[_-]?token|token|code[_-]?verifier|__RequestVerificationToken|code|state|nonce|credential|assertion|secret|challenge|email)\\b[\\\"' ]*[:=]\\s*)(?:\"(?:\\\\.|[^\"\\\\])*\"|'[^']*'|[^\\s;,&}]+)");
    private static readonly Regex _bearer = Pattern("\\b(?:Bearer|Basic)\\s+[A-Za-z0-9_+/=.~-]+");
    private static readonly Regex _jwt = Pattern("\\beyJ[A-Za-z0-9_-]+(?:\\.[A-Za-z0-9_-]*){1,4}");
    private static readonly Regex _url = Pattern("[a-z][a-z0-9+.-]*://[^\\s\\\"'<>]+");
    private static readonly Regex _email = Pattern("[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9.-]+\\.[A-Z]{2,}");
    private readonly string[] _secrets;

    /// <summary>Сохраняет только непустые значения секретных настроек, включая варианты JSON/URL encoding.</summary>
    internal NtfyLogRedactor(IConfiguration configuration)
    {
        _secrets = configuration.AsEnumerable()
            .Where(pair => pair.Value is { Length: > 0 } && _configurationSecretKey.IsMatch(pair.Key))
            .SelectMany(pair => ExpandSecret(pair.Key, pair.Value!))
            .SelectMany(value => new[] { value, Uri.EscapeDataString(value), JsonSerializer.Serialize(value)[1..^1] })
            .Distinct(StringComparer.Ordinal)
            .OrderByDescending(value => value.Length)
            .ToArray();
    }

    /// <summary>Извлекает пароль также из connection string, не передавая зависимость от конкретного DB provider.</summary>
    private static IEnumerable<string> ExpandSecret(string key, string value)
    {
        yield return value;
        if (!key.StartsWith("ConnectionStrings:", StringComparison.OrdinalIgnoreCase)) yield break;
        DbConnectionStringBuilder parsed;
        try { parsed = new() { ConnectionString = value }; }
        catch (ArgumentException) { yield break; }
        foreach (string name in parsed.Keys)
            if (_configurationSecretKey.IsMatch(name) && parsed[name]?.ToString() is { Length: > 0 } part)
                yield return part;
    }

    /// <summary>Скрывает также значения чувствительных structured fields; большие payloads не рассылаются.</summary>
    internal string Redact(string message, object? state = null)
    {
        if (message.Length > MAXIMUM_SOURCE_LENGTH) return "[Large log payload omitted]";
        try
        {
            if (state is IEnumerable<KeyValuePair<string, object?>> fields)
                foreach (var (key, value) in fields)
                {
                    if (value is null || key == "{OriginalFormat}" || !_sensitiveKey.IsMatch(key)) continue;
                    if (value is IEnumerable and not string) return "[Sensitive structured payload omitted]";
                    if (value.ToString() is { Length: > 0 } secret)
                        message = message.Replace(secret, REDACTED, StringComparison.Ordinal);
                }
            foreach (var secret in _secrets) message = message.Replace(secret, REDACTED, StringComparison.Ordinal);
            if (_privatePayload.IsMatch(message)) return "[Private archive/credential payload omitted]";
            message = _headers.Replace(message, match => match.Value.Split([':', '='], 2)[0] + ": " + REDACTED);
            message = _url.Replace(message, match =>
            {
                if (!Uri.TryCreate(match.Value, UriKind.Absolute, out var uri)) return "[URL REDACTED]";
                return uri.GetLeftPart(UriPartial.Authority).Replace(uri.UserInfo + "@", "", StringComparison.Ordinal) +
                    uri.AbsolutePath + (uri.Query.Length > 0 || uri.Fragment.Length > 0 ? "?[REDACTED]" : "");
            });
            message = _fields.Replace(message, "${key}" + REDACTED);
            message = _bearer.Replace(message, REDACTED);
            message = _jwt.Replace(message, REDACTED);
            return _email.Replace(message, "[EMAIL REDACTED]");
        }
        catch (Exception error) when (error is RegexMatchTimeoutException or ArgumentException)
        {
            return "[Log omitted: redaction could not complete]";
        }
    }

    /// <summary>Ограничивает время обработки недоверенного текста каждым выражением.</summary>
    private static Regex Pattern(string pattern) => new(pattern,
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, _regexTimeout);
}
