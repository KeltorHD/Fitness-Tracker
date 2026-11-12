using MapsterMapper;
using Microsoft.AspNetCore.Mvc;

namespace FitLife.Authentication.Controllers;

/// <summary>Маппит решения OAuth-сервиса в штатные MVC/OpenIddict результаты.</summary>
public sealed class AuthorizationController(AuthorizationService service, IMapper mapper) : Controller
{
    /// <summary>Передаёт PKCE authorize сервису без бизнес-проверок в контроллере.</summary>
    [HttpGet("/connect/authorize")]
    public async Task<IActionResult> AuthorizeAsync(CancellationToken cancellationToken) =>
        mapper.Map<OAuthDecision, IActionResult>(await service.AuthorizeAsync(cancellationToken));

    /// <summary>Передаёт code/refresh exchange сервису, сохраняя обработку протокола OpenIddict.</summary>
    [HttpPost("/connect/token"), IgnoreAntiforgeryToken]
    public async Task<IActionResult> TokenAsync(CancellationToken cancellationToken) =>
        mapper.Map<OAuthDecision, IActionResult>(await service.ExchangeAsync(cancellationToken));
}
