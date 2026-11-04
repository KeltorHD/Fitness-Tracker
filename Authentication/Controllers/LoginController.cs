using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using OpenIddict.Abstractions;
using OpenIddict.Client.AspNetCore;

namespace FitnessTracker.Authentication.Controllers;

public sealed record LoginPage(string ReturnUrl, string[] Providers);

public sealed class LoginController(IConfiguration config, UserManager<ApplicationUser> users,
    SignInManager<ApplicationUser> signIn, ExternalAccounts accounts) : Controller
{
    [HttpGet("/")]
    public IActionResult Index() => Redirect("/account");

    [HttpGet("/login")]
    public IActionResult Login(string returnUrl = "/account") => View(new LoginPage(
        LocalReturn(returnUrl), new[] { "Apple", "Google", "Yandex" }.Where(name =>
            AuthConfiguration.Enabled(config, name)).ToArray()));

    [HttpPost("/login/{provider}")]
    public async Task<IActionResult> Start(string provider, string returnUrl = "/account", bool link = false)
    {
        var name = new[] { "Apple", "Google", "Yandex" }.SingleOrDefault(item =>
            string.Equals(item, provider, StringComparison.OrdinalIgnoreCase));
        if (name is null || !AuthConfiguration.Enabled(config, name)) return NotFound();
        var properties = new AuthenticationProperties { RedirectUri = LocalReturn(returnUrl) };
        properties.Items[OpenIddictClientAspNetCoreConstants.Properties.ProviderName] = name;
        if (link)
        {
            var current = await users.GetUserAsync(User);
            if (current is null) return Unauthorized();
            properties.Items["link_user"] = current.Id;
        }
        return Challenge(properties, OpenIddictClientAspNetCoreDefaults.AuthenticationScheme);
    }

    [HttpGet("/callback/login/{provider}"), HttpPost("/callback/login/{provider}"), IgnoreAntiforgeryToken]
    public async Task<IActionResult> Callback(CancellationToken cancellationToken)
    {
        // OpenIddict validates provider state, nonce, signatures, issuer/audience and one-time state redemption.
        var result = await HttpContext.AuthenticateAsync(OpenIddictClientAspNetCoreDefaults.AuthenticationScheme);
        var subject = result.Principal?.FindFirstValue(ClaimTypes.NameIdentifier);
        var provider = result.Principal?.GetClaim(OpenIddictConstants.Claims.Private.ProviderName);
        if (!result.Succeeded || string.IsNullOrWhiteSpace(subject) || provider is null ||
            !AuthConfiguration.Enabled(config, provider))
            return Problem(statusCode: 400, title: "Не удалось подтвердить вход. Начните заново.");
        ApplicationUser user;
        if (result.Properties?.Items.TryGetValue("link_user", out var linkUser) == true)
        {
            var current = await users.GetUserAsync(User);
            if (current is null || current.Id != linkUser) return Unauthorized();
            // AddLogin enforces unique (LoginProvider, ProviderKey); never move another user's login.
            var linked = await users.AddLoginAsync(current, new UserLoginInfo(provider, subject, provider));
            if (!linked.Succeeded) return Problem(statusCode: 409, title: "Этот способ входа уже связан с аккаунтом.");
            user = current;
        }
        else user = await accounts.SignIn(provider, subject, result.Principal!, cancellationToken);
        await signIn.SignInAsync(user, isPersistent: false);
        return LocalRedirect(LocalReturn(result.Properties?.RedirectUri ?? "/account"));
    }

    private string LocalReturn(string value) => Url.IsLocalUrl(value) ? value : "/account";
}
