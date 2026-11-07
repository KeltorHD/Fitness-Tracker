using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using OpenIddict.Abstractions;

namespace FitnessTracker.Authentication;

/// <summary>Управляет аккаунтом и удалением данных, не формируя HTTP-ответов.</summary>
public sealed class AccountService(UserManager<ApplicationUser> users, SignInManager<ApplicationUser> signIn,
    ExternalAccounts accounts, IConfiguration config, BackupCleanup cleanup, BrowserNavigation navigation,
    IOpenIddictAuthorizationManager authorizations, IOpenIddictTokenManager tokens, AuthDbContext database)
{
    /// <summary>Возвращает разрешённые сведения о способах входа текущего cookie-пользователя.</summary>
    public async Task<AccountPageData> GetPageAsync(ClaimsPrincipal principal, NavigationInput input,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var user = await users.GetUserAsync(principal)
            ?? throw new AuthenticationOperationException(AuthenticationFailure.Unauthorized);
        var logins = (await users.GetLoginsAsync(user)).Select(login => login.LoginProvider).ToArray();
        var passkeys = (await users.GetPasskeysAsync(user))
            .Select(key => new AccountPasskeyData(key.CredentialId, key.Name ?? "Passkey"))
            .ToArray();
        var providers = new[] { "Apple", "Google", "Yandex" }
            .Where(name => AuthConfiguration.Enabled(config, name) && !logins.Contains(name))
            .ToArray();
        return new AccountPageData(user.DisplayName, navigation.LocalReturn(input.ReturnUrl), logins,
            providers, await users.HasPasswordAsync(user), passkeys);
    }

    /// <summary>Отключает внешний вход с отзывом сессий; защищает последний доступный credential.</summary>
    public async Task<string> UnlinkAsync(ClaimsPrincipal principal, string provider, NavigationInput input,
        CancellationToken cancellationToken)
    {
        var user = await users.GetUserAsync(principal)
            ?? throw new AuthenticationOperationException(AuthenticationFailure.Unauthorized);
        if (!await accounts.Unlink(user, provider, cancellationToken))
            throw new AuthenticationOperationException(AuthenticationFailure.Conflict, "Нельзя отключить последний способ входа.");
        await signIn.RefreshSignInAsync(user);
        return navigation.AccountReturn(input.ReturnUrl);
    }

    /// <summary>Завершает только браузерную cookie-сессию, сохраняя прежний контракт выхода.</summary>
    public async Task LogoutAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await signIn.SignOutAsync();
    }

    /// <summary>Читает публичный профиль по проверенному bearer subject, без owner ID из запроса.</summary>
    public async Task<AccountProfileData> GetProfileAsync(ClaimsPrincipal principal, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var subject = principal.GetClaim(OpenIddictConstants.Claims.Subject);
        var user = subject is null ? null : await users.FindByIdAsync(subject);
        if (user is null) throw new AuthenticationOperationException(AuthenticationFailure.Unauthorized);
        var methods = (await users.GetLoginsAsync(user)).Select(login => login.LoginProvider).ToList();
        if (await users.HasPasswordAsync(user)) methods.Add("Email");
        if ((await users.GetPasskeysAsync(user)).Count > 0) methods.Add("Passkey");
        return new AccountProfileData(user.Id, user.DisplayName, user.CreatedAt, methods.ToArray());
    }

    /// <summary>Сначала удаляет копии; затем атомарно отзывает и удаляет Identity и OAuth данные.</summary>
    public async Task DeleteAsync(ClaimsPrincipal principal, CancellationToken cancellationToken)
    {
        var subject = principal.GetClaim(OpenIddictConstants.Claims.Subject);
        var user = subject is null ? null : await users.FindByIdAsync(subject);
        if (user is null) throw new AuthenticationOperationException(AuthenticationFailure.Unauthorized);
        // При отказе Backend аккаунт остаётся для повтора; tombstone запрещает новые uploads.
        await cleanup.Delete(user.Id, cancellationToken);
        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        await authorizations.RevokeBySubjectAsync(user.Id, cancellationToken);
        await tokens.RevokeBySubjectAsync(user.Id, cancellationToken);
        // PostgreSQL требует закрыть query reader перед удалением строк.
        var sessions = new List<object>();
        await foreach (var token in tokens.FindBySubjectAsync(user.Id, cancellationToken)) sessions.Add(token);
        foreach (var token in sessions) await tokens.DeleteAsync(token, cancellationToken);
        var grants = new List<object>();
        await foreach (var grant in authorizations.FindBySubjectAsync(user.Id, cancellationToken)) grants.Add(grant);
        foreach (var grant in grants) await authorizations.DeleteAsync(grant, cancellationToken);
        ExternalAccounts.Check(await users.DeleteAsync(user));
        await transaction.CommitAsync(cancellationToken);
        await signIn.SignOutAsync();
    }
}
