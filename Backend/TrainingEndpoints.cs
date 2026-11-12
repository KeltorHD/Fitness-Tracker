using System.Text.Json;

namespace FitLife.Backend;

internal static class TrainingEndpoints
{
    internal static void MapTraining(this WebApplication app)
    {
        var group = app.MapGroup("/v1/training").RequireAuthorization("backend")
            .RequireRateLimiting("training").AddEndpointFilter<ActiveSessionFilter>();
        group.MapGet("/changes", async (HttpContext context, TrainingStorage storage, long? after, int? limit, CancellationToken ct) =>
        {
            try
            {
                var page = await storage.ChangesAsync(Owner(context), after ?? 0, limit ?? 50, ct);
                return Results.Json(page, TrainingJson.Options);
            }
            catch (TrainingException error) { return Failure(error); }
        });
        group.MapPost("/changes", async (HttpContext context, TrainingStorage storage, CancellationToken ct) =>
        {
            if (!context.Request.HasJsonContentType()) return Results.StatusCode(415);
            var data = await ReadBodyAsync(context.Request, ct);
            if (data is null) return Results.StatusCode(413);
            try
            {
                var changes = JsonSerializer.Deserialize<List<TrainingMutation>>(data, TrainingJson.Options);
                if (changes is null) return Results.BadRequest(new { code = "invalid_training_batch" });
                return Results.Json(await storage.ApplyBatchAsync(Owner(context), changes, ct), TrainingJson.Options);
            }
            catch (JsonException) { return Results.BadRequest(new { code = "invalid_training_data" }); }
            catch (TrainingException error) { return Failure(error); }
        });
    }

    private static IResult Failure(TrainingException error) => Results.Json(
        new { code = error.Code, current = error.Current }, TrainingJson.Options, statusCode: error.Status);

    private static string Owner(HttpContext context) => context.User.FindFirst("sub")!.Value;

    private static async Task<byte[]?> ReadBodyAsync(HttpRequest request, CancellationToken ct)
    {
        if (request.ContentLength > TrainingStorage.MaximumBytes) return null;
        using var result = new MemoryStream();
        var buffer = new byte[81_920];
        while (true)
        {
            var read = await request.Body.ReadAsync(buffer.AsMemory(0,
                (int)Math.Min(buffer.Length, TrainingStorage.MaximumBytes + 1 - result.Length)), ct);
            if (read == 0) return result.ToArray();
            await result.WriteAsync(buffer.AsMemory(0, read), ct);
            if (result.Length > TrainingStorage.MaximumBytes) return null;
        }
    }
}
