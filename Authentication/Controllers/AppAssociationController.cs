using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;

namespace FitnessTracker.Authentication.Controllers;

/// <summary>Публикует привязку приложения к домену после настройки настоящего Apple App ID.</summary>
public sealed partial class AppAssociationController(IConfiguration config) : ControllerBase
{
    /// <summary>Возвращает только настроенный идентификатор; до регистрации приложения отвечает 404.</summary>
    [HttpGet("/.well-known/apple-app-site-association")]
    public IActionResult Association()
    {
        var identifier = config["Auth:AppleAppIdentifier"];
        if (string.IsNullOrWhiteSpace(identifier)) return NotFound();
        if (!AppIdentifierPattern().IsMatch(identifier))
            return Problem(statusCode: 503, title: "Привязка приложения ещё не настроена.");
        return Ok(new { webcredentials = new { apps = new[] { identifier } } });
    }

    /// <summary>Не отражает authorization code в HTML, если система не перехватила HTTPS callback.</summary>
    [HttpGet("/ios/oauth/callback")]
    public IActionResult Callback() => new ContentResult
    {
        StatusCode = StatusCodes.Status400BadRequest,
        ContentType = "text/plain; charset=utf-8",
        Content = "Не удалось вернуться в приложение. Откройте FitnessTracker и повторите вход."
    };

    /// <summary>Ограничивает значение форматом App ID Prefix.Bundle ID без подстановки вымышленных ID.</summary>
    [GeneratedRegex(@"\A[A-Z0-9]{10}\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z")]
    private static partial Regex AppIdentifierPattern();
}
