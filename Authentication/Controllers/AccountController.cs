using MapsterMapper;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace FitnessTracker.Authentication.Controllers;

/// <summary>Маппит HTTP-контракты аккаунта и делегирует операции сервису.</summary>
public sealed class AccountController(AccountService service, IMapper mapper) : Controller
{
    /// <summary>Отображает разрешённые сведения текущего аккаунта.</summary>
    [Authorize, HttpGet("/account")]
    public async Task<IActionResult> AccountAsync([FromQuery] NavigationRequest request, CancellationToken cancellationToken) =>
        View("Account", mapper.Map<AccountPage>(await service.GetPageAsync(User,
            mapper.Map<NavigationInput>(request), cancellationToken)));

    /// <summary>Передаёт сервису явное отключение внешнего способа входа.</summary>
    [Authorize, HttpPost("/account/unlink/{provider}")]
    public async Task<IActionResult> UnlinkAsync(string provider, [FromForm] NavigationRequest request,
        CancellationToken cancellationToken) =>
        Redirect(await service.UnlinkAsync(User, provider, mapper.Map<NavigationInput>(request), cancellationToken));

    /// <summary>Завершает браузерную сессию через сервис.</summary>
    [Authorize, HttpPost("/account/logout")]
    public async Task<IActionResult> LogoutAsync(CancellationToken cancellationToken)
    {
        await service.LogoutAsync(cancellationToken);
        return Redirect("/login");
    }

    /// <summary>Маппит разрешённые поля bearer-профиля в стабильный JSON-контракт.</summary>
    [Authorize(Policy = "account"), HttpGet("/v1/account")]
    public async Task<IActionResult> ProfileAsync(CancellationToken cancellationToken) =>
        Ok(mapper.Map<AccountProfileResponse>(await service.GetProfileAsync(User, cancellationToken)));

    /// <summary>Передаёт удаление аккаунта сервису, сохраняя прежний HTTP-контракт.</summary>
    [Authorize(Policy = "account"), HttpDelete("/v1/account"), IgnoreAntiforgeryToken]
    public async Task<IActionResult> DeleteAsync(CancellationToken cancellationToken)
    {
        await service.DeleteAsync(User, cancellationToken);
        return NoContent();
    }
}
