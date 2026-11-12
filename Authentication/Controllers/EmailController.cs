using MapsterMapper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace FitLife.Authentication.Controllers;

/// <summary>Маппит формы почты; выдача токенов, SMTP и проверки принадлежат сервису.</summary>
[EnableRateLimiting("credentials")]
public sealed class EmailController(EmailConfirmationService service, IMapper mapper) : Controller
{
    /// <summary>Отображает ожидание письма и форму повторной отправки.</summary>
    [HttpGet("/email/verify")]
    public IActionResult Pending([FromQuery] NavigationRequest request) =>
        View(mapper.Map<EmailPendingPage>(service.GetPending(mapper.Map<NavigationInput>(request))));

    /// <summary>Повторяет отправку с одинаковым публичным ответом для всех адресов.</summary>
    [HttpPost("/email/resend"), RequestSizeLimit(16_384)]
    public async Task<IActionResult> ResendAsync([FromForm] EmailResendRequest request, CancellationToken cancellationToken) =>
        View("Pending", mapper.Map<EmailPendingPage>(await service.ResendAsync(mapper.Map<EmailResendInput>(request), cancellationToken)));

    /// <summary>GET показывает форму без изменения аккаунта.</summary>
    [HttpGet("/email/confirm")]
    public IActionResult Confirm([FromQuery] EmailConfirmationRequest request) =>
        View(mapper.Map<EmailConfirmPage>(service.GetConfirmationPage(mapper.Map<EmailConfirmationInput>(request))));

    /// <summary>Подтверждает адрес только после явного POST с antiforgery token.</summary>
    [HttpPost("/email/confirm"), RequestSizeLimit(16_384)]
    public async Task<IActionResult> ConfirmAsync([FromForm] EmailConfirmationRequest request, CancellationToken cancellationToken) =>
        View("Complete", mapper.Map<EmailCompletePage>(await service.ConfirmAsync(mapper.Map<EmailConfirmationInput>(request), cancellationToken)));
}
