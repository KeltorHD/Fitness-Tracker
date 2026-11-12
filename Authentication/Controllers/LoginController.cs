using MapsterMapper;
using Microsoft.AspNetCore.Mvc;
using OpenIddict.Client.AspNetCore;

namespace FitLife.Authentication.Controllers;

/// <summary>Маппит browser login HTTP-контракты и делегирует внешние входы сервису.</summary>
public sealed class LoginController(ExternalLoginService service, IMapper mapper) : Controller
{
    /// <summary>Открывает браузерный аккаунт.</summary>
    [HttpGet("/")]
    public IActionResult Index() => Redirect("/account");

    /// <summary>Отображает доступные провайдеры и безопасное продолжение.</summary>
    [HttpGet("/login")]
    public IActionResult Login([FromQuery] NavigationRequest request) =>
        View(mapper.Map<LoginPage>(service.GetPage(mapper.Map<NavigationInput>(request))));

    /// <summary>Передаёт подготовленные сервисом свойства штатному OpenIddict challenge.</summary>
    [HttpPost("/login/{provider}")]
    public async Task<IActionResult> StartAsync(string provider, [FromForm] ExternalLoginRequest request,
        CancellationToken cancellationToken) =>
        Challenge(await service.StartAsync(provider, mapper.Map<ExternalLoginInput>(request), User, cancellationToken),
            OpenIddictClientAspNetCoreDefaults.AuthenticationScheme);

    /// <summary>Передаёт проверку callback сервису и выполняет только локальный HTTP-переход.</summary>
    [HttpGet("/callback/login/{provider}"), HttpPost("/callback/login/{provider}"), IgnoreAntiforgeryToken]
    public async Task<IActionResult> CallbackAsync(CancellationToken cancellationToken) =>
        LocalRedirect(await service.CompleteAsync(User, cancellationToken));
}
