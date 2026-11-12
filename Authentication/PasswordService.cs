using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace FitLife.Authentication;

/// <summary>Выполняет регистрацию и парольный вход, сохраняя lockout и разделение локальных/внешних аккаунтов.</summary>
public sealed class PasswordService(UserManager<ApplicationUser> users, SignInManager<ApplicationUser> signIn,
    EmailAccounts accounts, UnknownPasswordCheck unknownPassword, BrowserNavigation navigation, IConfiguration config,
    EmailConfirmationService emailConfirmation, PendingRegistrationCleanup pendingRegistrations, ILogger<PasswordService> logger)
{
    private const string REGISTRATION_FAILURE = "Не удалось создать аккаунт. Если вы уже регистрировались, войдите или запросите новое письмо подтверждения.";

    /// <summary>Готовит безопасные поля страницы регистрации без credentials.</summary>
    public RegistrationPageData GetPage(NavigationInput input) => new(navigation.LocalReturn(input.ReturnUrl), "", GetProviders(), emailConfirmation.IsAvailable);

    /// <summary>Создаёт ожидающий подтверждения аккаунт и отправляет письмо без автоматического входа.</summary>
    public async Task<PasswordRegistrationOutcome> RegisterAsync(PasswordRegistrationInput input,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var attemptId = Guid.NewGuid().ToString("N");
        logger.LogInformation(new EventId(4300, "PasswordRegistrationRequested"),
            "Password registration requested; attempt {AttemptId}.", attemptId);
        var address = EmailAccounts.ValidateRegistrationEmail(input.Email);
        var returnUrl = navigation.LocalReturn(input.ReturnUrl);
        if (!emailConfirmation.IsAvailable)
            return Reject(returnUrl, "", attemptId, "smtp_disabled", "Регистрация по email временно недоступна.");
        if (address is null)
            return Reject(returnUrl, "", attemptId, "invalid_email", "Укажите корректный email.");
        if (input.Password is not { Length: >= 12 and <= 128 })
            return Reject(returnUrl, address, attemptId, "password_length", "Пароль должен содержать от 12 до 128 символов.");
        if (input.Password != input.ConfirmPassword)
            return Reject(returnUrl, address, attemptId, "password_mismatch", "Пароли не совпадают.");
        await pendingRegistrations.DeleteForRegistrationAsync(users.NormalizeName(accounts.UserName(address)), cancellationToken);
        var user = accounts.NewUser(address);
        IdentityResult result;
        try { result = await users.CreateAsync(user, input.Password); }
        catch (DbUpdateException exception) when (exception.InnerException is Npgsql.PostgresException { SqlState: "23505" })
        {
            return Reject(returnUrl, address, attemptId, "account_conflict", REGISTRATION_FAILURE, databaseCode: "23505");
        }
        if (!result.Succeeded)
            return RegistrationFailure(returnUrl, address, attemptId, result.Errors.Select(error => SafeIdentityCode(error.Code)).ToArray());
        logger.LogInformation(new EventId(4302, "PasswordRegistrationCreated"),
            "Password registration account created; email confirmation required; attempt {AttemptId}.", attemptId);
        await emailConfirmation.SendForNewUserAsync(user, cancellationToken);
        return new(emailConfirmation.PendingUrl(returnUrl), "", null, GetProviders(), true);
    }

    /// <summary>Проверяет пароль с lockout, не блокируя passkey-only аккаунт через парольные попытки.</summary>
    public async Task<PasswordLoginOutcome> LoginAsync(PasswordLoginInput input, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var address = EmailAccounts.ValidateEmail(input.Email);
        var user = address is null ? null : await users.FindByNameAsync(accounts.UserName(address));
        var validPassword = input.Password is { Length: > 0 and <= 128 };
        if (user is not null && validPassword && await users.HasPasswordAsync(user))
        {
            if (await users.IsLockedOutAsync(user)) unknownPassword.Verify(input.Password!);
            else
            {
                var result = await signIn.PasswordSignInAsync(user, input.Password!, isPersistent: false, lockoutOnFailure: true);
                if (result.Succeeded) return new(navigation.LocalReturn(input.ReturnUrl), null);
                if (result.IsNotAllowed && user.EmailConfirmationRequired && !user.EmailConfirmed)
                {
                    // Identity проверяет CanSignIn до пароля: сохраняем проверку и lockout для ожидающих аккаунтов.
                    if (await users.CheckPasswordAsync(user, input.Password!))
                        return new(emailConfirmation.PendingUrl(input.ReturnUrl), null);
                    await users.AccessFailedAsync(user);
                }
            }
        }
        else unknownPassword.Verify(validPassword ? input.Password! : "invalid-password");
        return new("/login" + QueryString.Create("returnUrl", navigation.LocalReturn(input.ReturnUrl)),
            "Не удалось войти. Проверьте email и пароль или попробуйте позже.");
    }

    /// <summary>Показывает требования к данным и пути продолжения, не раскрывая наличие аккаунта постороннему.</summary>
    private PasswordRegistrationOutcome RegistrationFailure(string returnUrl, string address, string attemptId, string[] codes)
    {
        var reason = codes.Contains("DuplicateUserName") || codes.Contains("DuplicateEmail") ? "account_conflict"
            : codes.Any(code => code.StartsWith("Password", StringComparison.Ordinal)) ? "password_policy" : "identity_rejected";
        var message = codes.Contains("PasswordRequiresUniqueChars") ? "Пароль должен содержать минимум 4 разных символа."
            : reason == "password_policy" ? "Пароль не соответствует требованиям. Проверьте длину и состав пароля."
            : REGISTRATION_FAILURE;
        return Reject(returnUrl, address, attemptId, reason, message,
            string.Join(",", codes.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).Take(8)));
    }

    /// <summary>Записывает только безопасную причину и случайный ID; email, пароль и описания Identity не логируются.</summary>
    private PasswordRegistrationOutcome Reject(string returnUrl, string address, string attemptId, string reason,
        string message, string identityCodes = "none", string databaseCode = "none")
    {
        logger.LogInformation(new EventId(4301, "PasswordRegistrationRejected"),
            "Password registration rejected: {Reason}; Identity codes {IdentityCodes}; database code {DatabaseCode}; attempt {AttemptId}.",
            reason, identityCodes, databaseCode, attemptId);
        return new(returnUrl, address, message, GetProviders(), emailConfirmation.IsAvailable);
    }

    /// <summary>Разрешает только известные коды: пользовательские validators могут поместить секреты даже в Code.</summary>
    private static string SafeIdentityCode(string code) => code switch
    {
        "DuplicateUserName" or "DuplicateEmail" or "InvalidEmail" or "InvalidUserName" or
        "PasswordTooShort" or "PasswordRequiresUniqueChars" or "PasswordRequiresDigit" or
        "PasswordRequiresLower" or "PasswordRequiresUpper" or "PasswordRequiresNonAlphanumeric" => code,
        _ => "unknown_identity_error"
    };

    /// <summary>Сохраняет доступность внешних способов входа при открытии и повторном показе регистрации.</summary>
    private string[] GetProviders() => new[] { "Apple", "Google", "Yandex" }
        .Where(name => AuthConfiguration.Enabled(config, name))
        .ToArray();
}
