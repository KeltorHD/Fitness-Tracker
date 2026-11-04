using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;

namespace FitnessTracker.Authentication.Controllers;

/// <summary>Параметры страницы регистрации без хранения пароля в модели ответа.</summary>
public sealed record RegistrationPage(string ReturnUrl, string Email = "");

/// <summary>Регистрирует локальные аккаунты и выполняет парольный вход через Identity.</summary>
[EnableRateLimiting("credentials")]
public sealed class PasswordController(UserManager<ApplicationUser> users, SignInManager<ApplicationUser> signIn,
    EmailAccounts accounts, UnknownPasswordCheck unknownPassword) : Controller
{
    /// <summary>Показывает форму регистрации; переход после входа ограничен локальными URL.</summary>
    [HttpGet("/register")]
    public IActionResult Register(string returnUrl = "/account") =>
        View(new RegistrationPage(LocalReturn(returnUrl)));

    /// <summary>Создаёт аккаунт с hash пароля; не отправляет письма и не подтверждает адрес.</summary>
    [HttpPost("/register"), RequestSizeLimit(16_384)]
    public async Task<IActionResult> RegisterAsync(string? email, string? password, string? confirmPassword,
        string returnUrl = "/account", CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var address = EmailAccounts.ValidateEmail(email);
        if (address is null || password is not { Length: >= 12 and <= 128 } || password != confirmPassword)
            return RegistrationError(returnUrl, address, "Укажите email и одинаковые пароли длиной от 12 до 128 символов.");
        var user = accounts.NewUser(address);
        IdentityResult result;
        try { result = await users.CreateAsync(user, password); }
        catch (DbUpdateException exception) when (exception.InnerException is Npgsql.PostgresException { SqlState: "23505" })
        {
            return RegistrationError(returnUrl, address, "Не удалось зарегистрироваться. Проверьте данные или попробуйте войти.");
        }
        if (!result.Succeeded)
            return RegistrationError(returnUrl, address, "Не удалось зарегистрироваться. Проверьте данные или попробуйте войти.");
        await signIn.SignInAsync(user, isPersistent: false);
        return LocalRedirect(LocalReturn(returnUrl));
    }

    /// <summary>Проверяет пароль с lockout; не раскрывает наличие адреса в системе.</summary>
    [HttpPost("/login/password"), RequestSizeLimit(16_384)]
    public async Task<IActionResult> LoginAsync(string? email, string? password, string returnUrl = "/account",
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var address = EmailAccounts.ValidateEmail(email);
        var user = address is null ? null : await users.FindByNameAsync(accounts.UserName(address));
        var validPassword = password is { Length: > 0 and <= 128 };
        if (user is not null && validPassword && await users.HasPasswordAsync(user))
        {
            if (await users.IsLockedOutAsync(user))
            {
                unknownPassword.Verify(password!);
                TempData["LoginError"] = "Не удалось войти. Проверьте email и пароль или попробуйте позже.";
                return LocalRedirect("/login" + QueryString.Create("returnUrl", LocalReturn(returnUrl)));
            }
            var result = await signIn.PasswordSignInAsync(user, password!, isPersistent: false, lockoutOnFailure: true);
            if (result.Succeeded) return LocalRedirect(LocalReturn(returnUrl));
        }
        else unknownPassword.Verify(validPassword ? password! : "invalid-password");
        TempData["LoginError"] = "Не удалось войти. Проверьте email и пароль или попробуйте позже.";
        return LocalRedirect("/login" + QueryString.Create("returnUrl", LocalReturn(returnUrl)));
    }

    /// <summary>Возвращает безопасную ошибку регистрации без повторного отображения пароля.</summary>
    private IActionResult RegistrationError(string returnUrl, string? email, string message)
    {
        ModelState.Clear();
        ModelState.AddModelError("", message);
        Response.StatusCode = StatusCodes.Status400BadRequest;
        return View("Register", new RegistrationPage(LocalReturn(returnUrl), email ?? ""));
    }

    /// <summary>Ограничивает переходы адресами внутри Authentication.</summary>
    private string LocalReturn(string value) => Url.IsLocalUrl(value) ? value : "/account";
}
