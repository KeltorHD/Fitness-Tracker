using MapsterMapper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace FitnessTracker.Authentication.Controllers;

/// <summary>Маппит парольные формы в команды сервиса и безопасные MVC-результаты.</summary>
[EnableRateLimiting("credentials")]
public sealed class PasswordController(PasswordService service, IMapper mapper) : Controller
{
    /// <summary>Отображает форму регистрации без credentials.</summary>
    [HttpGet("/register")]
    public IActionResult Register([FromQuery] NavigationRequest request) =>
        View(mapper.Map<RegistrationPage>(service.GetPage(mapper.Map<NavigationInput>(request))));

    /// <summary>Делегирует регистрацию сервису и маппит результат без возврата пароля.</summary>
    [HttpPost("/register"), RequestSizeLimit(16_384)]
    public async Task<IActionResult> RegisterAsync([FromForm] PasswordRegistrationRequest request,
        CancellationToken cancellationToken) =>
        mapper.Map<PasswordRegistrationOutcome, IActionResult>(await service.RegisterAsync(
            mapper.Map<PasswordRegistrationInput>(request), cancellationToken));

    /// <summary>Делегирует парольный вход сервису и маппит PRG-переход.</summary>
    [HttpPost("/login/password"), RequestSizeLimit(16_384)]
    public async Task<IActionResult> LoginAsync([FromForm] PasswordLoginRequest request,
        CancellationToken cancellationToken) =>
        mapper.Map<PasswordLoginOutcome, IActionResult>(await service.LoginAsync(
            mapper.Map<PasswordLoginInput>(request), cancellationToken));
}
