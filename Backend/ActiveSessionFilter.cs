namespace FitLife.Backend;

/// <summary>Проверяет отзыв после JWT, прав и rate limit, до чтения/изменения резервных копий.</summary>
internal sealed class ActiveSessionFilter(TokenIntrospection introspection) : IEndpointFilter
{
    /// <summary>Отозванная сессия получает 401; недоступный Auth — 503 без доступа к обработчику API.</summary>
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        var http = context.HttpContext;
        var authorization = http.Request.Headers.Authorization.ToString();
        if (!authorization.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return Results.Unauthorized();
        try
        {
            if (!await introspection.IsActiveAsync(authorization[7..].Trim(), http.RequestAborted))
            {
                http.Response.Headers.WWWAuthenticate = "Bearer error=\"invalid_token\"";
                return Results.Unauthorized();
            }
        }
        catch (AuthenticationUnavailableException)
        {
            return Results.Json(new { code = "authentication_unavailable" }, statusCode: StatusCodes.Status503ServiceUnavailable);
        }
        return await next(context);
    }
}
