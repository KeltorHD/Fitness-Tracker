using System.Text.Json;

namespace FitLife.Backend;

/// <summary>Публикует общий контракт чтения health providers через существующую проверку сессии.</summary>
internal static class HealthDataEndpoints
{
    /// <summary>Owner берётся только из JWT; неизвестный провайдер не превращается в произвольный исходящий URL.</summary>
    internal static void MapHealthData(this WebApplication app)
    {
        app.MapGet("/v1/health/providers/appleHealth/pending", async (HttpContext context, HealthSyncStorage storage, CancellationToken cancellationToken) =>
        {
            try { return Results.Json(new { buckets = await storage.PendingAsync(context.User.FindFirst("sub")!.Value, cancellationToken) }, HealthSyncJson.Options); }
            catch (HealthDataException error) { return Results.Json(new { code = error.Code }, statusCode: error.Status); }
        }).RequireAuthorization("backend").RequireRateLimiting("healthSync").AddEndpointFilter<ActiveSessionFilter>();
        app.MapPost("/v1/health/providers/appleHealth/changes", async (HttpContext context, HealthSyncStorage storage, CancellationToken cancellationToken) =>
        {
            if (!context.Request.HasJsonContentType()) return Results.StatusCode(415);
            const int maximumBytes = 4 * 1024 * 1024;
            if (context.Request.ContentLength > maximumBytes) return Results.StatusCode(413);
            using var memory = new MemoryStream();
            var buffer = new byte[8192];
            while (true)
            {
                var read = await context.Request.Body.ReadAsync(buffer.AsMemory(0, (int)Math.Min(buffer.Length, maximumBytes + 1 - memory.Length)), cancellationToken);
                if (read == 0) break;
                await memory.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                if (memory.Length > maximumBytes) return Results.StatusCode(413);
            }
            try
            {
                var batch = JsonSerializer.Deserialize<HealthSyncBatch>(memory.ToArray(), HealthSyncJson.Options);
                if (batch is null) return Results.BadRequest(new { code = "invalid_health_sync" });
                return Results.Json(await storage.ApplyAsync(context.User.FindFirst("sub")!.Value, batch, cancellationToken), HealthSyncJson.Options);
            }
            catch (JsonException) { return Results.BadRequest(new { code = "invalid_health_sync" }); }
            catch (HealthDataException error) { return Results.Json(new { code = error.Code }, statusCode: error.Status); }
        }).RequireAuthorization("backend").RequireRateLimiting("healthSync").AddEndpointFilter<ActiveSessionFilter>();
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
