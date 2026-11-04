using Microsoft.AspNetCore.Authentication.JwtBearer;

namespace FitnessTracker.Backend;

/// <summary>Отличает сбой discovery/JWKS от неверного JWT, чтобы временный отказ Auth не завершал сессию iOS.</summary>
internal sealed class DependencyAwareJwtBearerEvents : JwtBearerEvents
{
    /// <summary>Проверяет доступность первоначального discovery до IdentityModel, который может скрыть его отказ за ошибкой подписи.</summary>
    public override async Task MessageReceived(MessageReceivedContext context)
    {
        var authorization = context.Request.Headers.Authorization.ToString();
        if (!authorization.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) ||
            string.IsNullOrWhiteSpace(authorization[7..]) || context.Options.ConfigurationManager is null)
            return;
        try
        {
            // Сам manager кеширует только metadata/JWKS; статус токена здесь не кешируется.
            await context.Options.ConfigurationManager.GetConfigurationAsync(context.HttpContext.RequestAborted);
        }
        catch (Exception error) when (!context.HttpContext.RequestAborted.IsCancellationRequested && IsUnavailable(error))
        {
            context.Fail(new AuthenticationUnavailableException());
        }
    }

    /// <summary>Сохраняет обычный 401 для ошибок токена, преобразуя ошибки получения конфигурации Auth в зависимость.</summary>
    public override Task AuthenticationFailed(AuthenticationFailedContext context)
    {
        context.HttpContext.RequestAborted.ThrowIfCancellationRequested();
        if (IsUnavailable(context.Exception)) context.Fail(new AuthenticationUnavailableException());
        return Task.CompletedTask;
    }

    /// <summary>Не выдаёт invalid_token при недоступном Auth; клиент может повторить запрос с прежними credentials.</summary>
    public override async Task Challenge(JwtBearerChallengeContext context)
    {
        if (context.AuthenticateFailure is not AuthenticationUnavailableException) return;
        context.HandleResponse();
        context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
        await context.Response.WriteAsJsonAsync(new { code = "authentication_unavailable" }, context.HttpContext.RequestAborted);
    }

    /// <summary>Проверяет также вложенные ошибки IdentityModel, не разбирая сообщения или содержимое JWT.</summary>
    private static bool IsUnavailable(Exception? error) => error switch
    {
        null => false,
        AuthenticationUnavailableException or HttpRequestException or IOException or TimeoutException or
            OperationCanceledException or InvalidOperationException => true,
        AggregateException aggregate => aggregate.InnerExceptions.Any(IsUnavailable),
        _ => IsUnavailable(error.InnerException)
    };
}
