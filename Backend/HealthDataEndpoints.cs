using System.Text.Json;

namespace FitLife.Backend;

/// <summary>Публикует общий контракт чтения health providers через существующую проверку сессии.</summary>
internal static class HealthDataEndpoints
{
    /// <summary>Owner берётся только из JWT; неизвестный провайдер не превращается в произвольный исходящий URL.</summary>
    internal static void MapHealthData(this WebApplication app)
    {
        app.MapGet("/v1/health/providers/{provider}/data", async (string provider, DateTimeOffset start, DateTimeOffset end,
            string metrics, string zoneName, IEnumerable<IHealthDataProvider> providers, HttpContext context, CancellationToken cancellationToken) =>
        {
            var implementation = providers.SingleOrDefault(item => item.Id == provider);
            if (implementation is null) return Results.NotFound();
            try
            {
                var timeZone = TimeZoneInfo.FindSystemTimeZoneById(zoneName);
                var value = await implementation.ReadAsync(context.User.FindFirst("sub")!.Value, start, end,
                    metrics.Split(',', StringSplitOptions.RemoveEmptyEntries), timeZone, cancellationToken);
                var bytes = JsonSerializer.SerializeToUtf8Bytes(value, new JsonSerializerOptions(JsonSerializerDefaults.Web));
                if (bytes.Length > 30 * 1024 * 1024)
                    throw new HealthDataException(502, "health_history_too_large");
                return Results.Bytes(bytes, "application/json");
            }
            catch (TimeZoneNotFoundException) { return Results.BadRequest(new { code = "invalid_health_request" }); }
            catch (InvalidTimeZoneException) { return Results.BadRequest(new { code = "invalid_health_request" }); }
            catch (HealthDataException error) { return Results.Json(new { code = error.Code }, statusCode: error.Status); }
        }).RequireAuthorization("backend").RequireRateLimiting("health").AddEndpointFilter<ActiveSessionFilter>();
    }
}
