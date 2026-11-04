namespace FitnessTracker.Authentication.Controllers;

/// <summary>HTTP-параметр продолжения; сервер самостоятельно проверяет локальность URL.</summary>
public sealed record NavigationRequest(string? ReturnUrl = "/account");

/// <summary>HTTP-форма внешнего входа без доверенных идентификаторов пользователя.</summary>
public sealed record ExternalLoginRequest(string? ReturnUrl = "/account", bool Link = false);

/// <summary>HTTP-форма регистрации; credentials не выводятся через ToString.</summary>
public sealed record PasswordRegistrationRequest(string? Email = null, string? Password = null,
    string? ConfirmPassword = null, string? ReturnUrl = "/account")
{
    /// <summary>Скрывает приватные поля формы в строковом представлении.</summary>
    public override string ToString() => nameof(PasswordRegistrationRequest);
}

/// <summary>HTTP-форма входа; credentials не выводятся через ToString.</summary>
public sealed record PasswordLoginRequest(string? Email = null, string? Password = null, string? ReturnUrl = "/account")
{
    /// <summary>Скрывает приватные поля формы в строковом представлении.</summary>
    public override string ToString() => nameof(PasswordLoginRequest);
}

/// <summary>HTTP-форма начала регистрации passkey.</summary>
public sealed record PasskeyRegistrationRequest(string? Email = null);

/// <summary>HTTP-форма WebAuthn с исходным JSON браузера.</summary>
public sealed record PasskeyRequest(string? Credential = null, string? Name = null, string? ReturnUrl = "/account")
{
    /// <summary>Не раскрывает данные аутентификатора в строковом представлении.</summary>
    public override string ToString() => nameof(PasskeyRequest);
}

/// <summary>HTTP-форма удаления собственного ключа без owner ID.</summary>
public sealed record PasskeyRemovalRequest(string? CredentialId = null, string? ReturnUrl = "/account");

/// <summary>Безопасные сведения о passkey для страницы управления аккаунтом.</summary>
public sealed record PasskeySummary(string CredentialId, string Name);

/// <summary>Модель Razor страницы аккаунта без секретов и EF entities.</summary>
public sealed record AccountPage(string Name, string ReturnUrl, string[] Logins, string[] Providers,
    bool HasPassword, PasskeySummary[] Passkeys);

/// <summary>Модель Razor страницы выбора входа.</summary>
public sealed record LoginPage(string ReturnUrl, string[] Providers);

/// <summary>Модель Razor регистрации без паролей.</summary>
public sealed record RegistrationPage(string ReturnUrl, string Email = "");

/// <summary>Стабильный JSON-контракт профиля для iOS.</summary>
public sealed record AccountProfileResponse(string Id, string Name, DateTimeOffset CreatedAt, string[] Logins);

/// <summary>Продолжение WebAuthn browser JS с прежним полем redirect.</summary>
public sealed record PasskeyResponse(string Redirect);

/// <summary>Список App ID в формате Apple webcredentials.</summary>
public sealed record AppleWebCredentials(string[] Apps);

/// <summary>Публичный AASA-документ без других возможностей приложения.</summary>
public sealed record AppleAssociationResponse(AppleWebCredentials Webcredentials);
