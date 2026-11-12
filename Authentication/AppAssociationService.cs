using System.Text.RegularExpressions;

namespace FitLife.Authentication;

/// <summary>Проверяет конфигурацию Apple App ID и готовит публичные данные привязки.</summary>
public sealed partial class AppAssociationService(IConfiguration config)
{
    /// <summary>Не публикует вымышленные или некорректно заданные App ID.</summary>
    public AppAssociationData GetAssociation()
    {
        var identifier = config["Auth:AppleAppIdentifier"];
        if (string.IsNullOrWhiteSpace(identifier))
            throw new AuthenticationOperationException(AuthenticationFailure.NotFound);
        if (!AppIdentifierPattern().IsMatch(identifier))
            throw new AuthenticationOperationException(AuthenticationFailure.Unavailable, "Привязка приложения ещё не настроена.");
        return new([identifier]);
    }

    /// <summary>Возвращает статическое сообщение без отражения code, state и произвольных query parameters.</summary>
    public CallbackMessage GetCallbackMessage() => new("Не удалось вернуться в приложение. Откройте FitLife и повторите вход.");

    /// <summary>Проверяет формат App ID Prefix.Bundle ID.</summary>
    [GeneratedRegex(@"\A[A-Z0-9]{10}\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z")]
    private static partial Regex AppIdentifierPattern();
}
