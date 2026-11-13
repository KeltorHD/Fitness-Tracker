using MapsterMapper;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using OpenIddict.Abstractions;
using OpenIddict.Client.AspNetCore;

namespace FitLife.Authentication.Controllers;

/// <summary>Публикует управление OAuth-источниками здоровья и защищённый внутренний контракт Backend.</summary>
public sealed class HealthConnectionsController(HealthConnectionService connections, IMapper mapper) : Controller
{
    /// <summary>Открывает управление источниками в существующей защищённой browser session.</summary>
    [Authorize, HttpGet("/account/health")]
    public async Task<IActionResult> PageAsync([FromQuery] NavigationRequest request, CancellationToken cancellationToken)
        => View("Connections", await connections.GetPageAsync(User, mapper.Map<NavigationInput>(request), cancellationToken));

    /// <summary>Запускает явное подключение без использования Xiaomi как способа входа в FitLife.</summary>
    [Authorize, HttpPost("/account/health/mi-fitness/connect"), EnableRateLimiting("credentials")]
    public async Task<IActionResult> ConnectAsync([FromForm] NavigationRequest request, CancellationToken cancellationToken) =>
        Challenge(await connections.StartAsync(User, mapper.Map<NavigationInput>(request), cancellationToken),
            OpenIddictClientAspNetCoreDefaults.AuthenticationScheme);

    /// <summary>OpenIddict проверяет callback, а сервис связывает его с актуальным Identity-пользователем.</summary>
    [HttpGet("/callback/health/mi-fitness"), IgnoreAntiforgeryToken]
    public async Task<IActionResult> CallbackAsync(CancellationToken cancellationToken) =>
        LocalRedirect(await connections.CompleteAsync(User, cancellationToken));

    /// <summary>Отзывает разрешение из браузера и сохраняет безопасное продолжение входа приложения.</summary>
    [Authorize, HttpPost("/account/health/mi-fitness/disconnect"), EnableRateLimiting("credentials")]
    public async Task<IActionResult> DisconnectAsync([FromForm] NavigationRequest request, CancellationToken cancellationToken)
        => LocalRedirect(await connections.DisconnectBrowserAsync(User, mapper.Map<NavigationInput>(request), cancellationToken));

    /// <summary>Возвращает iOS только состояния и категории разрешений, без внешних credentials.</summary>
    [Authorize(Policy = "account"), HttpGet("/v1/health/connections")]
    public async Task<IActionResult> StatusAsync(CancellationToken cancellationToken) =>
        Ok(await connections.StatusAsync(User.GetClaim(OpenIddictConstants.Claims.Subject)!, cancellationToken));

    /// <summary>Позволяет iOS явно отключить свой источник по проверенному bearer subject.</summary>
    [Authorize(Policy = "account"), HttpDelete("/v1/health/connections/mi-fitness"), IgnoreAntiforgeryToken]
    public async Task<IActionResult> DisconnectAPIAsync(CancellationToken cancellationToken)
    {
        await connections.DisconnectAsync(User.GetClaim(OpenIddictConstants.Claims.Subject)!, cancellationToken);
        return NoContent();
    }

    /// <summary>Доступен только внутри сети сервисов; внешний reverse proxy запрещает /internal.</summary>
    [HttpPost("/internal/health/mi-fitness/{owner:guid}/grant"), IgnoreAntiforgeryToken]
    public async Task<IActionResult> GrantAsync(Guid owner, CancellationToken cancellationToken)
        => Ok(await connections.GrantForBackendAsync(owner, Request.Headers["X-Service-Key"].ToString(), cancellationToken));
}
