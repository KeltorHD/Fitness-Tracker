using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace FitnessTracker.Authentication;

/// <summary>Выполняет регистрацию и парольный вход, сохраняя lockout и разделение локальных/внешних аккаунтов.</summary>
public sealed class PasswordService(UserManager<ApplicationUser> users, SignInManager<ApplicationUser> signIn,
    EmailAccounts accounts, UnknownPasswordCheck unknownPassword, BrowserNavigation navigation, IConfiguration config,
    EmailConfirmationService emailConfirmation)
{
    /// <summary>Готовит безопасные поля страницы регистрации без credentials.</summary>
    public RegistrationPageData GetPage(NavigationInput input) => new(navigation.LocalReturn(input.ReturnUrl), "", GetProviders(), emailConfirmation.IsAvailable);

    /// <summary>Создаёт ожидающий подтверждения аккаунт и отправляет письмо без автоматического входа.</summary>
    public async Task<PasswordRegistrationOutcome> RegisterAsync(PasswordRegistrationInput input,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var address = EmailAccounts.ValidateRegistrationEmail(input.Email);
        var returnUrl = navigation.LocalReturn(input.ReturnUrl);
        if (!emailConfirmation.IsAvailable)
            return new(returnUrl, "", "Регистрация по email временно недоступна.", GetProviders(), false);
        if (address is null || input.Password is not { Length: >= 12 and <= 128 } || input.Password != input.ConfirmPassword)
            return new(returnUrl, address ?? "", "Укажите email и одинаковые пароли длиной от 12 до 128 символов.", GetProviders(), true);
        var user = accounts.NewUser(address);
        IdentityResult result;
        try { result = await users.CreateAsync(user, input.Password); }
        catch (DbUpdateException exception) when (exception.InnerException is Npgsql.PostgresException { SqlState: "23505" })
        {
            return RegistrationFailure(returnUrl, address);
        }
        if (!result.Succeeded) return RegistrationFailure(returnUrl, address);
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

    /// <summary>Не раскрывает причину конфликта регистрации и не возвращает пароль.</summary>
    private PasswordRegistrationOutcome RegistrationFailure(string returnUrl, string address) =>
        new(returnUrl, address, "Не удалось зарегистрироваться. Проверьте данные или попробуйте войти.", GetProviders(), emailConfirmation.IsAvailable);

    /// <summary>Сохраняет доступность внешних способов входа при открытии и повторном показе регистрации.</summary>
    private string[] GetProviders() => new[] { "Apple", "Google", "Yandex" }
        .Where(name => AuthConfiguration.Enabled(config, name))
        .ToArray();
}
