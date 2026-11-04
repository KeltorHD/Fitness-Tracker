using System.Data;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using OpenIddict.Abstractions;

namespace FitnessTracker.Authentication.Controllers;

/// <summary>Создаёт и проверяет passkey через штатный WebAuthn Identity без выдачи приватных ключей серверу.</summary>
[EnableRateLimiting("credentials"), RequestSizeLimit(65_536)]
public sealed class PasskeyController(UserManager<ApplicationUser> users, SignInManager<ApplicationUser> signIn,
    EmailAccounts accounts, PasskeyChallenges challenges, AuthDbContext database,
    IOpenIddictAuthorizationManager authorizations, IOpenIddictTokenManager tokens) : Controller
{
    /// <summary>Начинает регистрацию без пароля, связывая адрес и новый ID с защищённым состоянием Identity.</summary>
    [HttpPost("/passkeys/register/options")]
    public async Task<IActionResult> RegistrationOptionsAsync(string? email, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (User.Identity?.IsAuthenticated == true) return Conflict();
        var address = EmailAccounts.ValidateEmail(email);
        if (address is null) return Failure("Укажите корректный email.");
        var options = await signIn.MakePasskeyCreationOptionsAsync(new PasskeyUserEntity
        { Id = Guid.NewGuid().ToString(), Name = address, DisplayName = address });
        challenges.Issue(options, "register");
        return Content(options, "application/json");
    }

    /// <summary>Создаёт пользователя только после проверки attestation; email берётся из защищённого состояния.</summary>
    [HttpPost("/passkeys/register")]
    public async Task<IActionResult> RegisterAsync(string? credential, string returnUrl = "/account",
        CancellationToken cancellationToken = default)
    {
        if (User.Identity?.IsAuthenticated == true) return Conflict();
        if (!await ConsumeAsync(credential, "register", "Attestation", cancellationToken)) return Failure();
        var result = await signIn.PerformPasskeyAttestationAsync(credential!);
        if (!result.Succeeded || EmailAccounts.ValidateEmail(result.UserEntity.Name) is not { } address ||
            !Guid.TryParse(result.UserEntity.Id, out _)) return Failure();
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);
        var user = accounts.NewUser(address, result.UserEntity.Id);
        if (await users.FindByPasskeyIdAsync(result.Passkey.CredentialId) is not null) return Failure();
        IdentityResult created;
        try { created = await users.CreateAsync(user); }
        catch (DbUpdateException exception) when (exception.InnerException is Npgsql.PostgresException { SqlState: "23505" })
        {
            return Failure("Не удалось зарегистрироваться. Проверьте данные или попробуйте войти.");
        }
        if (!created.Succeeded) return Failure("Не удалось зарегистрироваться. Проверьте данные или попробуйте войти.");
        result.Passkey.Name = "Passkey";
        if (!(await users.AddOrUpdatePasskeyAsync(user, result.Passkey)).Succeeded) return Failure();
        await transaction.CommitAsync(cancellationToken);
        await signIn.SignInAsync(user, isPersistent: false);
        return Ok(new { redirect = LocalReturn(returnUrl) });
    }

    /// <summary>Начинает вход с discoverable passkey без поиска пользователя по неподтверждённому email.</summary>
    [HttpPost("/passkeys/login/options")]
    public async Task<IActionResult> LoginOptionsAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var options = await signIn.MakePasskeyRequestOptionsAsync(null);
        challenges.Issue(options, "login");
        return Content(options, "application/json");
    }

    /// <summary>Проверяет origin, подпись, UV и счётчик средствами Identity и устанавливает сессионную cookie.</summary>
    [HttpPost("/passkeys/login")]
    public async Task<IActionResult> LoginAsync(string? credential, string returnUrl = "/account",
        CancellationToken cancellationToken = default)
    {
        if (!await ConsumeAsync(credential, "login", "Assertion", cancellationToken)) return Failure();
        var result = await signIn.PasskeySignInAsync(credential!);
        return result.Succeeded ? Ok(new { redirect = LocalReturn(returnUrl) }) : Failure();
    }

    /// <summary>Готовит добавление passkey только для текущего авторизованного пользователя.</summary>
    [Authorize, HttpPost("/account/passkeys/options")]
    public async Task<IActionResult> EnrollmentOptionsAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var user = await users.GetUserAsync(User);
        if (user is null || await users.IsLockedOutAsync(user)) return Unauthorized();
        if ((await users.GetPasskeysAsync(user)).Count >= 10) return Failure("Можно сохранить до 10 passkey.");
        var options = await signIn.MakePasskeyCreationOptionsAsync(new PasskeyUserEntity
        { Id = user.Id, Name = user.Email ?? user.DisplayName, DisplayName = user.DisplayName });
        challenges.Issue(options, "enroll:" + user.Id);
        return Content(options, "application/json");
    }

    /// <summary>Добавляет passkey атомарно, проверяя владельца attestation, credential ID и лимит.</summary>
    [Authorize, HttpPost("/account/passkeys")]
    public async Task<IActionResult> EnrollAsync(string? credential, string? name, string returnUrl = "/account",
        CancellationToken cancellationToken = default)
    {
        var user = await users.GetUserAsync(User);
        if (user is null || await users.IsLockedOutAsync(user)) return Unauthorized();
        if (!await ConsumeAsync(credential, "enroll:" + user.Id, "Attestation", cancellationToken)) return Failure();
        var result = await signIn.PerformPasskeyAttestationAsync(credential!);
        if (!result.Succeeded || result.UserEntity.Id != user.Id || name is { Length: > 64 }) return Failure();
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);
        if ((await users.GetPasskeysAsync(user)).Count >= 10 ||
            await users.FindByPasskeyIdAsync(result.Passkey.CredentialId) is not null) return Failure();
        result.Passkey.Name = string.IsNullOrWhiteSpace(name) ? "Passkey" : name.Trim();
        if (!(await users.AddOrUpdatePasskeyAsync(user, result.Passkey)).Succeeded) return Failure();
        await transaction.CommitAsync(cancellationToken);
        return Ok(new { redirect = AccountReturn(returnUrl) });
    }

    /// <summary>Удаляет свой passkey, сохраняя последний способ входа и отзывая старые сессии.</summary>
    [Authorize, HttpPost("/account/passkeys/remove")]
    public async Task<IActionResult> RemoveAsync(string? credentialId, string returnUrl = "/account",
        CancellationToken cancellationToken = default)
    {
        var user = await users.GetUserAsync(User);
        if (user is null) return Unauthorized();
        if (credentialId is not { Length: > 0 and <= 1366 }) return Failure();
        byte[] id;
        try { id = WebEncoders.Base64UrlDecode(credentialId); }
        catch (FormatException) { return Failure(); }
        if (id.Length is 0 or > 1024) return Failure();
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);
        var keys = await users.GetPasskeysAsync(user);
        if (!keys.Any(key => key.CredentialId.SequenceEqual(id))) return NotFound();
        if (keys.Count <= 1 && !await users.HasPasswordAsync(user) && (await users.GetLoginsAsync(user)).Count == 0)
            return Problem(statusCode: 409, title: "Нельзя отключить последний способ входа.");
        ExternalAccounts.Check(await users.RemovePasskeyAsync(user, id));
        ExternalAccounts.Check(await users.UpdateSecurityStampAsync(user));
        await authorizations.RevokeBySubjectAsync(user.Id, cancellationToken);
        await tokens.RevokeBySubjectAsync(user.Id, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        await signIn.RefreshSignInAsync(user);
        return LocalRedirect(AccountReturn(returnUrl));
    }

    /// <summary>Требует живую защищённую cookie нужного типа и одноразовый серверный challenge.</summary>
    private async Task<bool> ConsumeAsync(string? credential, string purpose, string operation, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (credential is not { Length: > 0 and <= 60_000 }) return false;
        var state = await HttpContext.AuthenticateAsync(IdentityConstants.TwoFactorUserIdScheme);
        if (!state.Succeeded || state.Properties?.Items.TryGetValue("PasskeyOperation", out var saved) != true ||
            saved != operation) return false;
        return challenges.Consume(credential, purpose);
    }

    /// <summary>Возвращает безопасную ошибку без сырых WebAuthn payloads.</summary>
    private ObjectResult Failure(string message = "Не удалось подтвердить passkey. Повторите попытку.") =>
        Problem(statusCode: 400, title: message);

    /// <summary>Ограничивает переходы адресами внутри Authentication.</summary>
    private string LocalReturn(string value) => Url.IsLocalUrl(value) ? value : "/account";

    /// <summary>Сохраняет продолжение OAuth после управления passkey.</summary>
    private string AccountReturn(string value) => "/account" + QueryString.Create("returnUrl", LocalReturn(value));
}
