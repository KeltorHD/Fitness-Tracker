using System.Diagnostics;
using Microsoft.AspNetCore.Routing;

namespace FitLife.Backend;

/// <summary>Пишет результат HTTP по шаблону маршрута без query, UUID, headers, credentials и health payloads.</summary>
public sealed class BackendRequestLoggingMiddleware(RequestDelegate next, ILogger<BackendRequestLoggingMiddleware> logger)
{
    /// <summary>Измеряет обработку запроса и различает отказ приложения и отмену клиентом.</summary>
    public async Task InvokeAsync(HttpContext context)
    {
        var started = Stopwatch.GetTimestamp();
        var failed = false;
        var cancelled = false;
        try { await next(context); }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
        {
            cancelled = true;
            throw;
        }
        catch
        {
            failed = true;
            throw;
        }
        finally
        {
            var route = (context.GetEndpoint() as RouteEndpoint)?.RoutePattern.RawText ?? "unmatched";
            var status = cancelled ? 499 : failed ? 500 : context.Response.StatusCode;
            var level = status >= 500 ? LogLevel.Error : LogLevel.Information;
            // Успешные health probes не засоряют журнал; неуспешные остаются видимы.
            if (route != "/health" || status >= 400)
            {
                var method = context.Request.Method is "GET" or "POST" or "PUT" or "DELETE" or "PATCH" or "HEAD" or "OPTIONS"
                    ? context.Request.Method : "OTHER";
                logger.Log(level, new EventId(4107, "BackendHttpCompleted"),
                    "HTTP {Method} {Route} returned {StatusCode} in {ElapsedMilliseconds:F1} ms.",
                    method, route, status, Stopwatch.GetElapsedTime(started).TotalMilliseconds);
            }
        }
    }
}
