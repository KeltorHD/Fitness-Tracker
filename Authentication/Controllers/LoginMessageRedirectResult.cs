using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ViewFeatures;

namespace FitnessTracker.Authentication.Controllers;

/// <summary>Сохраняет сообщение PRG-перехода в TempData на HTTP-границе, вне парольного сервиса.</summary>
public sealed class LoginMessageRedirectResult(string url, string? message) : LocalRedirectResult(url)
{
    /// <summary>Использует штатную MVC инфраструктуру TempData и выполняет локальный redirect.</summary>
    public override Task ExecuteResultAsync(ActionContext context)
    {
        if (message is not null)
        {
            var factory = context.HttpContext.RequestServices.GetRequiredService<ITempDataDictionaryFactory>();
            factory.GetTempData(context.HttpContext)["LoginError"] = message;
        }
        return base.ExecuteResultAsync(context);
    }
}
