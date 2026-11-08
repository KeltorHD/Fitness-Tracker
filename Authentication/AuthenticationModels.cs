using System.Security.Claims;

namespace FitnessTracker.Authentication;

/// <summary>Продолжение браузерного сценария, проверяемое сервисом навигации.</summary>
public sealed record NavigationInput(string? ReturnUrl);

/// <summary>Параметры явного внешнего входа или привязки.</summary>
public sealed record ExternalLoginInput(string? ReturnUrl, bool Link);

/// <summary>Данные регистрации; строковое представление исключает credentials.</summary>
public sealed record PasswordRegistrationInput(string? Email, string? Password, string? ConfirmPassword, string? ReturnUrl)
{
    /// <summary>Скрывает пароль и адрес при случайном строковом логировании.</summary>
    public override string ToString() => nameof(PasswordRegistrationInput);
}

/// <summary>Данные парольного входа без раскрытия credentials в строковом представлении.</summary>
public sealed record PasswordLoginInput(string? Email, string? Password, string? ReturnUrl)
{
    /// <summary>Скрывает пароль и адрес при случайном строковом логировании.</summary>
    public override string ToString() => nameof(PasswordLoginInput);
}

/// <summary>Адрес нового passkey-аккаунта, который будет связан с защищённым challenge.</summary>
public sealed record PasskeyRegistrationInput(string? Email);

/// <summary>Исходный WebAuthn payload и пользовательское название; проверка остаётся в Identity.</summary>
public sealed record PasskeySubmission(string? CredentialJson, string? Name, string? ReturnUrl)
{
    /// <summary>Не раскрывает WebAuthn payload при строковом логировании.</summary>
    public override string ToString() => nameof(PasskeySubmission);
}

/// <summary>Идентификатор удаляемого ключа без возможности задавать владельца.</summary>
public sealed record PasskeyRemovalInput(string? CredentialId, string? ReturnUrl);

/// <summary>Разрешённые сведения ключа для браузерного аккаунта.</summary>
public sealed record AccountPasskeyData(byte[] CredentialId, string Name);

/// <summary>Сведения страницы аккаунта без EF entities и ключевого материала.</summary>
public sealed record AccountPageData(string Name, string ReturnUrl, string[] Logins, string[] Providers,
    bool HasPassword, AccountPasskeyData[] Passkeys);

/// <summary>Публичный профиль для bearer API.</summary>
public sealed record AccountProfileData(string Id, string Name, DateTimeOffset CreatedAt, string[] Logins);

/// <summary>Выбор доступных внешних способов входа.</summary>
public sealed record LoginPageData(string ReturnUrl, string[] Providers);

/// <summary>Страница регистрации без пароля.</summary>
public sealed record RegistrationPageData(string ReturnUrl, string Email, string[] Providers, bool EmailRegistrationAvailable);

/// <summary>Результат регистрации: безопасные поля формы и ошибка либо разрешённое продолжение.</summary>
public sealed record PasswordRegistrationOutcome(string ReturnUrl, string Email, string? Error, string[] Providers, bool EmailRegistrationAvailable);

/// <summary>Форма повтора письма без раскрытия существования аккаунта.</summary>
public sealed record EmailResendInput(string? Email, string? ReturnUrl)
{
    /// <summary>Исключает адрес из строкового логирования.</summary>
    public override string ToString() => nameof(EmailResendInput);
}

/// <summary>Защищённый токен подтверждения; не предназначен для логирования.</summary>
public sealed record EmailConfirmationInput(string? UserId, string? Code)
{
    /// <summary>Исключает токен из строкового логирования.</summary>
    public override string ToString() => nameof(EmailConfirmationInput);
}

/// <summary>Страница ожидания и повторной отправки без приватных полей.</summary>
public sealed record EmailPendingPageData(string ReturnUrl, bool Available, bool Submitted);

/// <summary>Сведения формы явного подтверждения после перехода по ссылке.</summary>
public sealed record EmailConfirmPageData(string UserId, string Code, bool CanConfirm)
{
    /// <summary>Не раскрывает токен при строковом логировании.</summary>
    public override string ToString() => nameof(EmailConfirmPageData);
}

/// <summary>Результат подтверждения без автоматического входа.</summary>
public sealed record EmailConfirmationOutcome(bool Succeeded);

/// <summary>Продолжение парольного входа и безопасное сообщение для браузера.</summary>
public sealed record PasswordLoginOutcome(string ReturnUrl, string? Error);

/// <summary>Локальный переход после успешно проверенного passkey.</summary>
public sealed record PasskeyDestination(string Redirect);

/// <summary>Настроенные Apple App ID для публикации webcredentials.</summary>
public sealed record AppAssociationData(string[] Apps);

/// <summary>Статический текст для неперехваченного HTTPS callback, без данных запроса.</summary>
public sealed record CallbackMessage(string Message);

/// <summary>Решение OAuth-сервиса; MVC-результат формируется отдельно.</summary>
public abstract record OAuthDecision;

/// <summary>Проверенный principal для штатной выдачи кода или токенов OpenIddict.</summary>
public sealed record OAuthSignIn(ClaimsPrincipal Principal) : OAuthDecision;

/// <summary>Переход к браузерному входу или управлению аккаунтом.</summary>
public sealed record OAuthRedirect(string ReturnUrl) : OAuthDecision;

/// <summary>Протокольный отказ, который OpenIddict преобразует в стандартный OAuth error.</summary>
public sealed record OAuthDenied(string Error) : OAuthDecision;
