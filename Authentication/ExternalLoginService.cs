using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using OpenIddict.Abstractions;
using OpenIddict.Client.AspNetCore;

namespace FitnessTracker.Authentication;

/// <summary>Координирует внешние входы и явные привязки после протокольной проверки OpenIddict.</summary>
public sealed class ExternalLoginService(IConfiguration config, UserManager<ApplicationUser> users,
    SignInManager<ApplicationUser> signIn, ExternalAccounts accounts, BrowserNavigation navigation,
    IHttpContextAccessor contexts)
{
    /// <summary>Возвращает доступные внешние провайдеры и безопасное продолжение.</summary>
    public LoginPageData GetPage(NavigationInput input) => new(navigation.LocalReturn(input.ReturnUrl),
        new[] { "Apple", "Google", "Yandex" }.Where(name => AuthConfiguration.Enabled(config, name)).ToArray());

    /// <summary>Готовит challenge только для разрешённого провайдера; привязка связана с текущим пользователем.</summary>
    public async Task<AuthenticationProperties> StartAsync(string provider, ExternalLoginInput input,
        ClaimsPrincipal principal, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var name = new[] { "Apple", "Google", "Yandex" }.SingleOrDefault(item =>
            string.Equals(item, provider, StringComparison.OrdinalIgnoreCase));
        if (name is null || !AuthConfiguration.Enabled(config, name))
            throw new AuthenticationOperationException(AuthenticationFailure.NotFound);
        var properties = new AuthenticationProperties { RedirectUri = navigation.LocalReturn(input.ReturnUrl) };
        properties.Items[OpenIddictClientAspNetCoreConstants.Properties.ProviderName] = name;
        if (input.Link)
        {
            var current = await users.GetUserAsync(principal);
            if (current is null || await users.IsLockedOutAsync(current))
                throw new AuthenticationOperationException(AuthenticationFailure.Unauthorized);
            properties.Items["link_user"] = current.Id;
        }
        return properties;
    }

    /// <summary>Проверяет подтверждённый внешний subject и не объединяет аккаунты по email.</summary>
    public async Task<string> CompleteAsync(ClaimsPrincipal principal, CancellationToken cancellationToken)
    {
        var context = contexts.HttpContext ?? throw new InvalidOperationException("An external login HTTP context is required.");
        // OpenIddict проверяет state, nonce, подписи и одноразовое погашение provider state.
        var result = await context.AuthenticateAsync(OpenIddictClientAspNetCoreDefaults.AuthenticationScheme);
        var subject = result.Principal?.FindFirstValue(ClaimTypes.NameIdentifier);
        var provider = result.Principal?.GetClaim(OpenIddictConstants.Claims.Private.ProviderName);
        if (!result.Succeeded || string.IsNullOrWhiteSpace(subject) || provider is null || !AuthConfiguration.Enabled(config, provider))
            throw new AuthenticationOperationException(AuthenticationFailure.InvalidInput, "Не удалось подтвердить вход. Начните заново.");
        ApplicationUser user;
        if (result.Properties?.Items.TryGetValue("link_user", out var linkUser) == true)
        {
            var current = await users.GetUserAsync(principal);
            if (current is null || current.Id != linkUser || await users.IsLockedOutAsync(current))
                throw new AuthenticationOperationException(AuthenticationFailure.Unauthorized);
            // Identity не позволяет перенести login другого пользователя.
            var linked = await users.AddLoginAsync(current, new UserLoginInfo(provider, subject, provider));
            if (!linked.Succeeded)
                throw new AuthenticationOperationException(AuthenticationFailure.Conflict, "Этот способ входа уже связан с аккаунтом.");
            user = current;
        }
        else user = await accounts.SignIn(provider, subject, result.Principal!, cancellationToken);
        if (!await signIn.CanSignInAsync(user) || await users.IsLockedOutAsync(user))
            throw new AuthenticationOperationException(AuthenticationFailure.Forbidden, "Вход в этот аккаунт недоступен.");
        await signIn.SignInAsync(user, isPersistent: false);
        return navigation.LocalReturn(result.Properties?.RedirectUri);
    }
}
