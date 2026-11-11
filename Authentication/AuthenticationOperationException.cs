namespace FitLife.Authentication;

/// <summary>Ожидаемые отказы пользовательского сценария, без привязки к MVC result types.</summary>
public enum AuthenticationFailure
{
    /// <summary>Не подтверждён текущий пользователь.</summary>
    Unauthorized,
    /// <summary>Объект или доступный способ входа отсутствует.</summary>
    NotFound,
    /// <summary>Операция недоступна этому аккаунту.</summary>
    Forbidden,
    /// <summary>Операция конфликтует с текущими способами входа.</summary>
    Conflict,
    /// <summary>Входные данные или WebAuthn-подтверждение не прошли проверку.</summary>
    InvalidInput,
    /// <summary>Не завершена необходимая серверная конфигурация.</summary>
    Unavailable
}

/// <summary>Передаёт ожидаемый отказ сервисов на HTTP-границу без внутренних исключений и payloads.</summary>
public sealed class AuthenticationOperationException(AuthenticationFailure failure,
    string? message = null) : Exception(message ?? "Не удалось выполнить действие.")
{
    /// <summary>Категория отказа, которую MVC преобразует в HTTP status.</summary>
    public AuthenticationFailure Failure { get; } = failure;

    /// <summary>Безопасный публичный текст; отсутствие текста сохраняет HTTP-ответ без тела.</summary>
    public string? Title { get; } = message;
}
