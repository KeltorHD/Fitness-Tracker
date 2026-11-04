using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using OpenIddict.Abstractions;

namespace FitnessTracker.Authentication.Controllers;

/// <summary>Безопасные сведения о passkey для страницы управления аккаунтом.</summary>
public sealed record PasskeySummary(string CredentialId, string Name);

/// <summary>Способы входа и продолжение OAuth без секретов и ключевого материала.</summary>
public sealed record AccountPage(string Name, string ReturnUrl, string[] Logins, string[] Providers,
    bool HasPassword, PasskeySummary[] Passkeys);

public sealed class AccountController(UserManager<ApplicationUser> users, SignInManager<ApplicationUser> signIn,
    ExternalAccounts accounts, IConfiguration config, BackupCleanup cleanup,
    IOpenIddictAuthorizationManager authorizations, IOpenIddictTokenManager tokens, AuthDbContext database) : Controller
{
    [Authorize, HttpGet("/account")]
    public async Task<IActionResult> Account(string returnUrl = "/account")
    {
        var user = await users.GetUserAsync(User);
        if (user is null) return Unauthorized();
        var logins = (await users.GetLoginsAsync(user)).Select(login => login.LoginProvider).ToArray();
        var passkeys = (await users.GetPasskeysAsync(user)).Select(key => new PasskeySummary(
            Microsoft.AspNetCore.WebUtilities.WebEncoders.Base64UrlEncode(key.CredentialId), key.Name ?? "Passkey")).ToArray();
        return View(new AccountPage(user.DisplayName, Url.IsLocalUrl(returnUrl) ? returnUrl : "/account",
            logins, new[] { "Apple", "Google", "Yandex" }.Where(name =>
                AuthConfiguration.Enabled(config, name) && !logins.Contains(name)).ToArray(),
            await users.HasPasswordAsync(user), passkeys));
    }

    [Authorize, HttpPost("/account/unlink/{provider}")]
    public async Task<IActionResult> Unlink(string provider, CancellationToken cancellationToken, string returnUrl = "/account")
    {
        var user = await users.GetUserAsync(User);
        if (user is null) return Unauthorized();
        if (!await accounts.Unlink(user, provider, cancellationToken))
            return Problem(statusCode: 409, title: "Нельзя отключить последний способ входа.");
        await signIn.RefreshSignInAsync(user);
        return Redirect("/account" + QueryString.Create("returnUrl", Url.IsLocalUrl(returnUrl) ? returnUrl : "/account"));
    }

    [Authorize, HttpPost("/account/logout")]
    public async Task<IActionResult> Logout()
    {
        await signIn.SignOutAsync();
        return Redirect("/login");
    }

    [Authorize(Policy = "account"), HttpGet("/v1/account")]
    public async Task<IActionResult> Profile()
    {
        var subject = User.GetClaim(OpenIddictConstants.Claims.Subject);
        var user = subject is null ? null : await users.FindByIdAsync(subject);
        if (user is null) return Unauthorized();
        var methods = (await users.GetLoginsAsync(user)).Select(login => login.LoginProvider).ToList();
        if (await users.HasPasswordAsync(user)) methods.Add("Email");
        if ((await users.GetPasskeysAsync(user)).Count > 0) methods.Add("Passkey");
        return Ok(new
        {
            id = user.Id,
            name = user.DisplayName,
            createdAt = user.CreatedAt,
            logins = methods
        });
    }

    [Authorize(Policy = "account"), HttpDelete("/v1/account"), IgnoreAntiforgeryToken]
    public async Task<IActionResult> Delete(CancellationToken cancellationToken)
    {
        var subject = User.GetClaim(OpenIddictConstants.Claims.Subject);
        var user = subject is null ? null : await users.FindByIdAsync(subject);
        if (user is null) return Unauthorized();
        // Keep the identity if cleanup fails. The backend tombstone makes retries safe and blocks stale JWTs.
        await cleanup.Delete(user.Id, cancellationToken);
        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        await authorizations.RevokeBySubjectAsync(user.Id, cancellationToken);
        await tokens.RevokeBySubjectAsync(user.Id, cancellationToken);
        // Remove encrypted session payloads as well as the Identity profile. Buffer before deleting:
        // PostgreSQL cannot execute another command while the async query reader is open.
        var sessions = new List<object>();
        await foreach (var token in tokens.FindBySubjectAsync(user.Id, cancellationToken)) sessions.Add(token);
        foreach (var token in sessions) await tokens.DeleteAsync(token, cancellationToken);
        var grants = new List<object>();
        await foreach (var grant in authorizations.FindBySubjectAsync(user.Id, cancellationToken)) grants.Add(grant);
        foreach (var grant in grants) await authorizations.DeleteAsync(grant, cancellationToken);
        ExternalAccounts.Check(await users.DeleteAsync(user));
        await transaction.CommitAsync(cancellationToken);
        await signIn.SignOutAsync();
        return NoContent();
    }
}
