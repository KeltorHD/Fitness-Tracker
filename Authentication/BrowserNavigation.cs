using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.Routing;

namespace FitLife.Authentication;

/// <summary>Проверяет браузерные продолжения штатным URL validator MVC.</summary>
public sealed class BrowserNavigation(IUrlHelperFactory urls, IHttpContextAccessor contexts)
{
    /// <summary>Отклоняет внешние, protocol-relative и некорректные URL без собственной реализации парсинга.</summary>
    public string LocalReturn(string? value)
    {
        var context = contexts.HttpContext ?? throw new InvalidOperationException("A browser HTTP context is required.");
        var action = new ActionContext(context, context.GetRouteData(),
            context.GetEndpoint()?.Metadata.GetMetadata<ActionDescriptor>() ?? new ActionDescriptor());
        return urls.GetUrlHelper(action).IsLocalUrl(value) ? value! : "/account";
    }

    /// <summary>Сохраняет безопасное продолжение OAuth после управления аккаунтом.</summary>
    public string AccountReturn(string? value) => "/account" + QueryString.Create("returnUrl", LocalReturn(value));
}
