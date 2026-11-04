using System.Security.Claims;
using Microsoft.AspNetCore;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using OpenIddict.Abstractions;
using OpenIddict.Server.AspNetCore;
using static OpenIddict.Abstractions.OpenIddictConstants;

namespace FitnessTracker.Authentication.Controllers;

public sealed class AuthorizationController(UserManager<ApplicationUser> users,
    SignInManager<ApplicationUser> signIn, IOpenIddictApplicationManager applications,
    IOpenIddictAuthorizationManager authorizations) : Controller
{
    [HttpGet("/connect/authorize")]
    public async Task<IActionResult> Authorize(CancellationToken cancellationToken)
    {
        var request = HttpContext.GetOpenIddictServerRequest() ?? throw new InvalidOperationException();
        var cookie = await HttpContext.AuthenticateAsync(IdentityConstants.ApplicationScheme);
        var user = cookie.Principal is null ? null : await users.GetUserAsync(cookie.Principal);
        var chooseAccount = request.HasPromptValue(PromptValues.SelectAccount) || request.HasPromptValue(PromptValues.Login);
        if (!cookie.Succeeded || user is null || !await signIn.CanSignInAsync(user) || chooseAccount)
        {
            if (request.HasPromptValue(PromptValues.None)) return Deny(Errors.LoginRequired);
            if (chooseAccount) await signIn.SignOutAsync();
            var returnUrl = Request.Path + QueryString.Create(Request.Query.Where(item => item.Key != "prompt"));
            return Redirect("/login" + QueryString.Create("returnUrl", returnUrl));
        }
        if (request.GetParameter("screen")?.ToString() == "account")
        {
            var returnUrl = Request.Path + QueryString.Create(Request.Query.Where(item => item.Key != "screen"));
            return Redirect("/account" + QueryString.Create("returnUrl", returnUrl));
        }
        var application = await applications.FindByClientIdAsync(request.ClientId!, cancellationToken)
            ?? throw new InvalidOperationException();
        var identity = CreateIdentity(user);
        identity.SetScopes(request.GetScopes());
        identity.SetResources(AuthConfiguration.Audience);
        // One authorization per device sign-in gives refresh tokens a revocable session family.
        var authorization = await authorizations.CreateAsync(identity, user.Id,
            (await applications.GetIdAsync(application, cancellationToken))!, AuthorizationTypes.Permanent,
            identity.GetScopes(), cancellationToken);
        identity.SetAuthorizationId(await authorizations.GetIdAsync(authorization, cancellationToken));
        return SignIn(new ClaimsPrincipal(identity), OpenIddictServerAspNetCoreDefaults.AuthenticationScheme);
    }

    [HttpPost("/connect/token"), IgnoreAntiforgeryToken]
    public async Task<IActionResult> Token()
    {
        var request = HttpContext.GetOpenIddictServerRequest() ?? throw new InvalidOperationException();
        if (!request.IsAuthorizationCodeGrantType() && !request.IsRefreshTokenGrantType())
            return Deny(Errors.UnsupportedGrantType);
        var ticket = await HttpContext.AuthenticateAsync(OpenIddictServerAspNetCoreDefaults.AuthenticationScheme);
        var subject = ticket.Principal?.GetClaim(Claims.Subject);
        var user = subject is null ? null : await users.FindByIdAsync(subject);
        if (!ticket.Succeeded || user is null || !await signIn.CanSignInAsync(user))
            return Deny(Errors.InvalidGrant);
        var identity = new ClaimsIdentity(ticket.Principal!.Claims, "Bearer", Claims.Name, Claims.Role);
        identity.SetClaim(Claims.Name, user.DisplayName);
        SetDestinations(identity);
        return SignIn(new ClaimsPrincipal(identity), OpenIddictServerAspNetCoreDefaults.AuthenticationScheme);
    }

    private static ClaimsIdentity CreateIdentity(ApplicationUser user)
    {
        var identity = new ClaimsIdentity("Bearer", Claims.Name, Claims.Role);
        identity.SetClaim(Claims.Subject, user.Id).SetClaim(Claims.Name, user.DisplayName);
        SetDestinations(identity);
        return identity;
    }

    private static void SetDestinations(ClaimsIdentity identity) => identity.SetDestinations(claim =>
        claim.Type == Claims.Name ? [Destinations.AccessToken, Destinations.IdentityToken] :
            Array.Empty<string>());

    private ForbidResult Deny(string error) => Forbid(new AuthenticationProperties(
        new Dictionary<string, string?> { [OpenIddictServerAspNetCoreConstants.Properties.Error] = error }),
        OpenIddictServerAspNetCoreDefaults.AuthenticationScheme);
}
