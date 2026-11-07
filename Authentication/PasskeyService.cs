using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using OpenIddict.Abstractions;

namespace FitnessTracker.Authentication;

/// <summary>Проверяет WebAuthn и атомарно изменяет credentials через штатные компоненты Identity.</summary>
public sealed class PasskeyService(UserManager<ApplicationUser> users, SignInManager<ApplicationUser> signIn,
    EmailAccounts accounts, PasskeyChallenges challenges, AuthDbContext database, BrowserNavigation navigation,
    IOpenIddictAuthorizationManager authorizations, IOpenIddictTokenManager tokens, IHttpContextAccessor contexts,
    EmailConfirmationService emailConfirmation)
{
    /// <summary>Связывает email и новый ID с защищённым attestation state без создания пользователя.</summary>
    public async Task<string> StartRegistrationAsync(ClaimsPrincipal principal, PasskeyRegistrationInput input,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!emailConfirmation.IsAvailable) throw new AuthenticationOperationException(AuthenticationFailure.Unavailable, "Регистрация по email временно недоступна.");
        if (principal.Identity?.IsAuthenticated == true)
            throw new AuthenticationOperationException(AuthenticationFailure.Conflict);
        var address = EmailAccounts.ValidateRegistrationEmail(input.Email);
        if (address is null) throw Failure("Укажите корректный email.");
        var options = await signIn.MakePasskeyCreationOptionsAsync(new PasskeyUserEntity
        { Id = Guid.NewGuid().ToString(), Name = address, DisplayName = address });
        challenges.Issue(options, "register");
        return options;
    }

    /// <summary>Создаёт аккаунт только после проверки attestation и защищённой привязки email/ID.</summary>
    public async Task<PasskeyDestination> RegisterAsync(ClaimsPrincipal principal, PasskeySubmission input,
        CancellationToken cancellationToken)
    {
        if (!emailConfirmation.IsAvailable) throw new AuthenticationOperationException(AuthenticationFailure.Unavailable, "Регистрация по email временно недоступна.");
        if (principal.Identity?.IsAuthenticated == true)
            throw new AuthenticationOperationException(AuthenticationFailure.Conflict);
        if (!await ConsumeAsync(input.CredentialJson, "register", "Attestation", cancellationToken)) throw Failure();
        var result = await signIn.PerformPasskeyAttestationAsync(input.CredentialJson!);
        if (!result.Succeeded || EmailAccounts.ValidateRegistrationEmail(result.UserEntity.Name) is not { } address ||
            !Guid.TryParse(result.UserEntity.Id, out _)) throw Failure();
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);
        var user = accounts.NewUser(address, result.UserEntity.Id);
        if (await users.FindByPasskeyIdAsync(result.Passkey.CredentialId) is not null) throw Failure();
        IdentityResult created;
        try { created = await users.CreateAsync(user); }
        catch (DbUpdateException exception) when (exception.InnerException is Npgsql.PostgresException { SqlState: "23505" })
        {
            throw Failure("Не удалось зарегистрироваться. Проверьте данные или попробуйте войти.");
        }
        if (!created.Succeeded) throw Failure("Не удалось зарегистрироваться. Проверьте данные или попробуйте войти.");
        result.Passkey.Name = "Passkey";
        if (!(await users.AddOrUpdatePasskeyAsync(user, result.Passkey)).Succeeded) throw Failure();
        await transaction.CommitAsync(cancellationToken);
        await emailConfirmation.SendForNewUserAsync(user, cancellationToken);
        return new(emailConfirmation.PendingUrl(input.ReturnUrl));
    }

    /// <summary>Начинает discoverable passkey вход без поиска по неподтверждённому email.</summary>
    public async Task<string> StartLoginAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var options = await signIn.MakePasskeyRequestOptionsAsync(null);
        challenges.Issue(options, "login");
        return options;
    }

    /// <summary>Штатный Identity проверяет подпись, origin, RP, user verification и счётчик.</summary>
    public async Task<PasskeyDestination> LoginAsync(PasskeySubmission input, CancellationToken cancellationToken)
    {
        if (!await ConsumeAsync(input.CredentialJson, "login", "Assertion", cancellationToken)) throw Failure();
        var result = await signIn.PasskeySignInAsync(input.CredentialJson!);
        if (result.IsNotAllowed) return new(emailConfirmation.PendingUrl(input.ReturnUrl));
        if (!result.Succeeded) throw Failure();
        return new(navigation.LocalReturn(input.ReturnUrl));
    }

    /// <summary>Готовит новый passkey для текущего разрешённого cookie-пользователя с лимитом количества.</summary>
    public async Task<string> StartEnrollmentAsync(ClaimsPrincipal principal, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var user = await users.GetUserAsync(principal);
        if (user is null || await users.IsLockedOutAsync(user))
            throw new AuthenticationOperationException(AuthenticationFailure.Unauthorized);
        if ((await users.GetPasskeysAsync(user)).Count >= 10) throw Failure("Можно сохранить до 10 passkey.");
        var options = await signIn.MakePasskeyCreationOptionsAsync(new PasskeyUserEntity
        { Id = user.Id, Name = user.Email ?? user.DisplayName, DisplayName = user.DisplayName });
        challenges.Issue(options, "enroll:" + user.Id);
        return options;
    }

    /// <summary>Атомарно добавляет ключ после проверки владельца, credential ID, имени и квоты.</summary>
    public async Task<PasskeyDestination> EnrollAsync(ClaimsPrincipal principal, PasskeySubmission input,
        CancellationToken cancellationToken)
    {
        var user = await users.GetUserAsync(principal);
        if (user is null || await users.IsLockedOutAsync(user))
            throw new AuthenticationOperationException(AuthenticationFailure.Unauthorized);
        if (!await ConsumeAsync(input.CredentialJson, "enroll:" + user.Id, "Attestation", cancellationToken)) throw Failure();
        var result = await signIn.PerformPasskeyAttestationAsync(input.CredentialJson!);
        if (!result.Succeeded || result.UserEntity.Id != user.Id || input.Name is { Length: > 64 }) throw Failure();
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);
        if ((await users.GetPasskeysAsync(user)).Count >= 10 ||
            await users.FindByPasskeyIdAsync(result.Passkey.CredentialId) is not null) throw Failure();
        result.Passkey.Name = string.IsNullOrWhiteSpace(input.Name) ? "Passkey" : input.Name.Trim();
        if (!(await users.AddOrUpdatePasskeyAsync(user, result.Passkey)).Succeeded) throw Failure();
        await transaction.CommitAsync(cancellationToken);
        return new(navigation.AccountReturn(input.ReturnUrl));
    }

    /// <summary>Удаляет только свой ключ, защищая последний credential и отзывая прежние OAuth-сессии.</summary>
    public async Task<string> RemoveAsync(ClaimsPrincipal principal, PasskeyRemovalInput input,
        CancellationToken cancellationToken)
    {
        var user = await users.GetUserAsync(principal)
            ?? throw new AuthenticationOperationException(AuthenticationFailure.Unauthorized);
        if (input.CredentialId is not { Length: > 0 and <= 1366 }) throw Failure();
        byte[] id;
        try { id = WebEncoders.Base64UrlDecode(input.CredentialId); }
        catch (FormatException) { throw Failure(); }
        if (id.Length is 0 or > 1024) throw Failure();
        await using var transaction = await database.Database.BeginTransactionAsync(IsolationLevel.Serializable, cancellationToken);
        var keys = await users.GetPasskeysAsync(user);
        if (!keys.Any(key => key.CredentialId.SequenceEqual(id)))
            throw new AuthenticationOperationException(AuthenticationFailure.NotFound);
        if (keys.Count <= 1 && !await users.HasPasswordAsync(user) && (await users.GetLoginsAsync(user)).Count == 0)
            throw new AuthenticationOperationException(AuthenticationFailure.Conflict, "Нельзя отключить последний способ входа.");
        ExternalAccounts.Check(await users.RemovePasskeyAsync(user, id));
        ExternalAccounts.Check(await users.UpdateSecurityStampAsync(user));
        await authorizations.RevokeBySubjectAsync(user.Id, cancellationToken);
        await tokens.RevokeBySubjectAsync(user.Id, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        await signIn.RefreshSignInAsync(user);
        return navigation.AccountReturn(input.ReturnUrl);
    }

    /// <summary>Требует защищённую cookie нужной операции и атомарно расходует серверный challenge.</summary>
    private async Task<bool> ConsumeAsync(string? credential, string purpose, string operation, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (credential is not { Length: > 0 and <= 60_000 }) return false;
        var context = contexts.HttpContext ?? throw new InvalidOperationException("A passkey HTTP context is required.");
        var state = await context.AuthenticateAsync(IdentityConstants.TwoFactorUserIdScheme);
        if (!state.Succeeded || state.Properties?.Items.TryGetValue("PasskeyOperation", out var saved) != true ||
            saved != operation) return false;
        return challenges.Consume(credential, purpose);
    }

    /// <summary>Передаёт безопасный отказ без сырых данных аутентификатора.</summary>
    private static AuthenticationOperationException Failure(string message = "Не удалось подтвердить passkey. Повторите попытку.") =>
        new(AuthenticationFailure.InvalidInput, message);
}
