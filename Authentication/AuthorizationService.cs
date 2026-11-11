using System.Security.Claims;
using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using OpenIddict.Abstractions;
using OpenIddict.Server.AspNetCore;
using static OpenIddict.Abstractions.OpenIddictConstants;

namespace FitLife.Authentication;

/// <summary>Выдаёт authorization codes и токены с проверкой актуального состояния Identity-пользователя.</summary>
public sealed class AuthorizationService(UserManager<ApplicationUser> users,
    SignInManager<ApplicationUser> signIn, IOpenIddictApplicationManager applications,
    IOpenIddictAuthorizationManager authorizations, IHttpContextAccessor contexts)
{
    /// <summary>Текущий HTTP-контекст штатного OpenIddict endpoint.</summary>
    private HttpContext HttpContext => contexts.HttpContext
        ?? throw new InvalidOperationException("An OAuth HTTP context is required.");

    /// <summary>Версия учётных данных только в защищённых code/refresh payloads, без публикации в JWT.</summary>
    private const string SECURITY_STAMP_CLAIM = "fitnesstracker:security_stamp";

    /// <summary>Продолжает PKCE-вход либо требует аутентификацию разрешённого пользователя.</summary>
    public async Task<OAuthDecision> AuthorizeAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var request = HttpContext.GetOpenIddictServerRequest() ?? throw new InvalidOperationException();
        var cookie = await HttpContext.AuthenticateAsync(IdentityConstants.ApplicationScheme);
        var user = cookie.Principal is null ? null : await users.GetUserAsync(cookie.Principal);
        var chooseAccount = request.HasPromptValue(PromptValues.SelectAccount) || request.HasPromptValue(PromptValues.Login);
        if (!cookie.Succeeded || user is null || !await signIn.CanSignInAsync(user) ||
            await users.IsLockedOutAsync(user) || chooseAccount)
        {
            if (request.HasPromptValue(PromptValues.None)) return new OAuthDenied(Errors.LoginRequired);
            if (chooseAccount) await signIn.SignOutAsync();
            var returnUrl = HttpContext.Request.Path + QueryString.Create(HttpContext.Request.Query.Where(item => item.Key != "prompt"));
            return new OAuthRedirect("/login" + QueryString.Create("returnUrl", returnUrl));
        }
        if (request.GetParameter("screen")?.ToString() == "account")
        {
            var returnUrl = HttpContext.Request.Path + QueryString.Create(HttpContext.Request.Query.Where(item => item.Key != "screen"));
            return new OAuthRedirect("/account" + QueryString.Create("returnUrl", returnUrl));
        }
        var application = await applications.FindByClientIdAsync(request.ClientId!, cancellationToken)
            ?? throw new InvalidOperationException();
        // Берём stamp из проверенной cookie, а не из заново загруженного профиля:
        // начатый до отвязки запрос не должен получить новую версию учётных данных.
        var identity = CreateIdentity(user,
            cookie.Principal?.FindFirstValue(users.Options.ClaimsIdentity.SecurityStampClaimType));
        identity.SetScopes(request.GetScopes());
        identity.SetResources(AuthConfiguration.Audience);
        // One authorization per device sign-in gives refresh tokens a revocable session family.
        var authorization = await authorizations.CreateAsync(identity, user.Id,
            (await applications.GetIdAsync(application, cancellationToken))!, AuthorizationTypes.Permanent,
            identity.GetScopes(), cancellationToken);
        identity.SetAuthorizationId(await authorizations.GetIdAsync(authorization, cancellationToken));
        return new OAuthSignIn(new ClaimsPrincipal(identity));
    }

    /// <summary>Обменивает code/refresh только пока пользователь существует и не заблокирован.</summary>
    public async Task<OAuthDecision> ExchangeAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var request = HttpContext.GetOpenIddictServerRequest() ?? throw new InvalidOperationException();
        if (!request.IsAuthorizationCodeGrantType() && !request.IsRefreshTokenGrantType())
            return new OAuthDenied(Errors.UnsupportedGrantType);
        var ticket = await HttpContext.AuthenticateAsync(OpenIddictServerAspNetCoreDefaults.AuthenticationScheme);
        var subject = ticket.Principal?.GetClaim(Claims.Subject);
        var user = subject is null ? null : await users.FindByIdAsync(subject);
        if (!ticket.Succeeded || user is null || !await signIn.CanSignInAsync(user) || await users.IsLockedOutAsync(user))
            return new OAuthDenied(Errors.InvalidGrant);
        var stamp = ticket.Principal?.GetClaim(SECURITY_STAMP_CLAIM);
        if (string.IsNullOrEmpty(stamp) || !string.Equals(stamp, await users.GetSecurityStampAsync(user), StringComparison.Ordinal))
            return new OAuthDenied(Errors.InvalidGrant);
        var identity = new ClaimsIdentity(ticket.Principal!.Claims, "Bearer", Claims.Name, Claims.Role);
        identity.SetClaim(Claims.Name, user.DisplayName);
        SetDestinations(identity);
        return new OAuthSignIn(new ClaimsPrincipal(identity));
    }

    /// <summary>Связывает сессию с версией проверенной cookie, включая гонку с массовым отзывом.</summary>
    private static ClaimsIdentity CreateIdentity(ApplicationUser user, string? securityStamp)
    {
        var identity = new ClaimsIdentity("Bearer", Claims.Name, Claims.Role);
        identity.SetClaim(Claims.Subject, user.Id).SetClaim(Claims.Name, user.DisplayName);
        identity.SetClaim(SECURITY_STAMP_CLAIM, securityStamp);
        SetDestinations(identity);
        return identity;
    }

    /// <summary>Оставляет SecurityStamp только в защищённых code/refresh payloads.</summary>
    private static void SetDestinations(ClaimsIdentity identity) => identity.SetDestinations(claim =>
        claim.Type == Claims.Name ? [Destinations.AccessToken, Destinations.IdentityToken] :
            Array.Empty<string>());

}
