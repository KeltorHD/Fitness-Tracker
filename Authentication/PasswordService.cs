using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace FitnessTracker.Authentication;

/// <summary>Выполняет регистрацию и парольный вход, сохраняя lockout и разделение локальных/внешних аккаунтов.</summary>
public sealed class PasswordService(UserManager<ApplicationUser> users, SignInManager<ApplicationUser> signIn,
    EmailAccounts accounts, UnknownPasswordCheck unknownPassword, BrowserNavigation navigation)
{
    /// <summary>Готовит безопасные поля страницы регистрации без credentials.</summary>
    public RegistrationPageData GetPage(NavigationInput input) => new(navigation.LocalReturn(input.ReturnUrl), "");

    /// <summary>Создаёт локальный аккаунт без писем; возвращает только безопасные данные формы.</summary>
    public async Task<PasswordRegistrationOutcome> RegisterAsync(PasswordRegistrationInput input,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var address = EmailAccounts.ValidateEmail(input.Email);
        var returnUrl = navigation.LocalReturn(input.ReturnUrl);
        if (address is null || input.Password is not { Length: >= 12 and <= 128 } || input.Password != input.ConfirmPassword)
            return new(returnUrl, address ?? "", "Укажите email и одинаковые пароли длиной от 12 до 128 символов.");
        var user = accounts.NewUser(address);
        IdentityResult result;
        try { result = await users.CreateAsync(user, input.Password); }
        catch (DbUpdateException exception) when (exception.InnerException is Npgsql.PostgresException { SqlState: "23505" })
        {
            return RegistrationFailure(returnUrl, address);
        }
        if (!result.Succeeded) return RegistrationFailure(returnUrl, address);
        await signIn.SignInAsync(user, isPersistent: false);
        return new(returnUrl, address, null);
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
            }
        }
        else unknownPassword.Verify(validPassword ? input.Password! : "invalid-password");
        return new("/login" + QueryString.Create("returnUrl", navigation.LocalReturn(input.ReturnUrl)),
            "Не удалось войти. Проверьте email и пароль или попробуйте позже.");
    }

    /// <summary>Не раскрывает причину конфликта регистрации и не возвращает пароль.</summary>
    private static PasswordRegistrationOutcome RegistrationFailure(string returnUrl, string address) =>
        new(returnUrl, address, "Не удалось зарегистрироваться. Проверьте данные или попробуйте войти.");
}
