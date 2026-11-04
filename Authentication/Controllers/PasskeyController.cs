using MapsterMapper;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace FitnessTracker.Authentication.Controllers;

/// <summary>Маппит формы passkey и делегирует WebAuthn/Identity проверки сервису.</summary>
[EnableRateLimiting("credentials"), RequestSizeLimit(65_536)]
public sealed class PasskeyController(PasskeyService service, IMapper mapper) : Controller
{
    /// <summary>Передаёт начало регистрации сервису, сохраняя штатный JSON WebAuthn.</summary>
    [HttpPost("/passkeys/register/options")]
    public async Task<IActionResult> RegistrationOptionsAsync([FromForm] PasskeyRegistrationRequest request,
        CancellationToken cancellationToken) =>
        Content(await service.StartRegistrationAsync(User, mapper.Map<PasskeyRegistrationInput>(request), cancellationToken),
            "application/json");

    /// <summary>Маппит регистрацию с passkey в команду и прежний JSON redirect.</summary>
    [HttpPost("/passkeys/register")]
    public async Task<IActionResult> RegisterAsync([FromForm] PasskeyRequest request, CancellationToken cancellationToken) =>
        Ok(mapper.Map<PasskeyResponse>(await service.RegisterAsync(User, mapper.Map<PasskeySubmission>(request), cancellationToken)));

    /// <summary>Передаёт начало discoverable входа сервису.</summary>
    [HttpPost("/passkeys/login/options")]
    public async Task<IActionResult> LoginOptionsAsync(CancellationToken cancellationToken) =>
        Content(await service.StartLoginAsync(cancellationToken), "application/json");

    /// <summary>Маппит завершение входа без разбора или изменения WebAuthn payload.</summary>
    [HttpPost("/passkeys/login")]
    public async Task<IActionResult> LoginAsync([FromForm] PasskeyRequest request, CancellationToken cancellationToken) =>
        Ok(mapper.Map<PasskeyResponse>(await service.LoginAsync(mapper.Map<PasskeySubmission>(request), cancellationToken)));

    /// <summary>Передаёт сервису начало добавления ключа к текущему аккаунту.</summary>
    [Authorize, HttpPost("/account/passkeys/options")]
    public async Task<IActionResult> EnrollmentOptionsAsync(CancellationToken cancellationToken) =>
        Content(await service.StartEnrollmentAsync(User, cancellationToken), "application/json");

    /// <summary>Маппит форму добавления ключа и безопасное продолжение.</summary>
    [Authorize, HttpPost("/account/passkeys")]
    public async Task<IActionResult> EnrollAsync([FromForm] PasskeyRequest request, CancellationToken cancellationToken) =>
        Ok(mapper.Map<PasskeyResponse>(await service.EnrollAsync(User, mapper.Map<PasskeySubmission>(request), cancellationToken)));

    /// <summary>Маппит удаление своего ключа; владельца определяет сервис из проверенного principal.</summary>
    [Authorize, HttpPost("/account/passkeys/remove")]
    public async Task<IActionResult> RemoveAsync([FromForm] PasskeyRemovalRequest request, CancellationToken cancellationToken) =>
        LocalRedirect(await service.RemoveAsync(User, mapper.Map<PasskeyRemovalInput>(request), cancellationToken));
}
