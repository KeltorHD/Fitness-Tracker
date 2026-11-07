using MapsterMapper;
using Microsoft.AspNetCore.Mvc;

namespace FitnessTracker.Authentication.Controllers;

/// <summary>Маппит проверенную конфигурацию Apple в публичные HTTP-документы.</summary>
public sealed class AppAssociationController(AppAssociationService service, IMapper mapper) : ControllerBase
{
    /// <summary>Возвращает AASA только после успешной проверки конфигурации сервисом.</summary>
    [HttpGet("/.well-known/apple-app-site-association")]
    public IActionResult Association() => Ok(mapper.Map<AppleAssociationResponse>(service.GetAssociation()));

    /// <summary>Маппит статическое fallback сообщение без отражения данных запроса.</summary>
    [HttpGet("/ios/oauth/callback")]
    public IActionResult Callback() => mapper.Map<ContentResult>(service.GetCallbackMessage());
}
