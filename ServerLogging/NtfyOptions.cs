using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace FitnessTracker.ServerLogging;

/// <summary>Настройки необязательной отправки логов, в том числе через Ntfy__* environment keys.</summary>
public sealed class NtfyOptions
{
    /// <summary>По умолчанию сеть и отправка полностью отключены.</summary>
    public bool Enabled { get; init; }
    /// <summary>Корневой HTTPS-адрес ntfy без topic, credentials, query и fragment.</summary>
    public string ServerUrl { get; init; } = "";
    /// <summary>Topic из 1–64 ASCII-букв, цифр, дефисов или подчёркиваний.</summary>
    public string Topic { get; init; } = "";
    /// <summary>Необязательный bearer token; не включается в журналы и URL.</summary>
    public string Token { get; init; } = "";
    /// <summary>Независимый от console минимальный уровень; None отключает доставку.</summary>
    public LogLevel MinimumLevel { get; init; } = LogLevel.Warning;
    /// <summary>Размер очереди в памяти; переполнение не блокирует ILogger.Log.</summary>
    public int QueueCapacity { get; init; } = 128;
    /// <summary>Тайм-аут одного HTTP-запроса в секундах.</summary>
    public int TimeoutSeconds { get; init; } = 5;

    /// <summary>Читает стандартную конфигурацию и проверяет только включённую интеграцию без раскрытия значений.</summary>
    internal static NtfyOptions Read(IConfiguration configuration)
    {
        var section = configuration.GetSection("Ntfy");
        if (!section.GetValue<bool>(nameof(Enabled))) return new();
        var options = section.Get<NtfyOptions>() ?? new();
        options.Validate();
        return options;
    }

    /// <summary>Отклоняет ошибочные/небезопасные параметры до открытия HTTP listener.</summary>
    internal void Validate()
    {
        if (!Enabled) return;
        if (!Enum.IsDefined(MinimumLevel)) throw new InvalidOperationException("Ntfy:MinimumLevel is invalid.");
        if (QueueCapacity is < 1 or > 1024) throw new InvalidOperationException("Ntfy:QueueCapacity must be between 1 and 1024.");
        if (TimeoutSeconds is < 1 or > 30) throw new InvalidOperationException("Ntfy:TimeoutSeconds must be between 1 and 30.");
        if (MinimumLevel == LogLevel.None) return;
        if (!Uri.TryCreate(ServerUrl, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps ||
            uri.UserInfo.Length != 0 || uri.Query.Length != 0 || uri.Fragment.Length != 0)
            throw new InvalidOperationException("Ntfy:ServerUrl must be an HTTPS URL without credentials, query or fragment.");
        if (Topic.Length is < 1 or > 64 || Topic.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '-' and not '_'))
            throw new InvalidOperationException("Ntfy:Topic must contain 1-64 ASCII letters, digits, hyphens or underscores.");
        if (Token.Any(c => !char.IsAscii(c) || char.IsControl(c) || char.IsWhiteSpace(c)))
            throw new InvalidOperationException("Ntfy:Token must contain ASCII characters without whitespace or controls.");
    }
}
