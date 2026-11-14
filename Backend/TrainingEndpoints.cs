using System.Text.Json;

namespace FitLife.Backend;

/// <summary>Регистрирует HTTP-контракт структурированного журнала и безопасные ошибки.</summary>
internal static class TrainingEndpoints
{
    /// <summary>Регистрирует JWT-защищённый change feed с проверкой отзыва сессии и лимитом запросов.</summary>
    internal static void MapTraining(this WebApplication app)
    {
        var group = app.MapGroup("/v1/training").RequireAuthorization("backend")
            .RequireRateLimiting("training").AddEndpointFilter<ActiveSessionFilter>();
        group.MapGet("/changes", async (HttpContext context, TrainingStorage storage, long? after, int? limit, string? kinds, CancellationToken cancellationToken) =>
        {
            try
            {
                var selected = kinds?.Split(',') ?? [TrainingKinds.Workout, TrainingKinds.Template, TrainingKinds.BodyWeight, TrainingKinds.HeartRate];
                if (selected.Length is < 1 or > 10 || selected.Any(x => !TrainingKinds.Contains(x)))
                    return Results.BadRequest(new { code = "invalid_training_kind" });
                var page = await storage.ChangesAsync(Owner(context), after ?? 0, limit ?? 50, selected, cancellationToken);
                return Results.Json(page, TrainingJson.Options);
            }
            catch (TrainingException error) { return Failure(error); }
        });
        group.MapPost("/changes", async (HttpContext context, TrainingStorage storage, CancellationToken cancellationToken) =>
        {
            if (!context.Request.HasJsonContentType()) return Results.StatusCode(415);
            var data = await ReadBodyAsync(context.Request, cancellationToken);
            if (data is null) return Results.StatusCode(413);
            try
            {
                var changes = JsonSerializer.Deserialize<List<TrainingMutation>>(data, TrainingJson.Options);
                if (changes is null) return Results.BadRequest(new { code = "invalid_training_batch" });
                return Results.Json(await storage.ApplyBatchAsync(Owner(context), changes, cancellationToken), TrainingJson.Options);
            }
            catch (JsonException) { return Results.BadRequest(new { code = "invalid_training_data" }); }
            catch (TrainingException error) { return Failure(error); }
        });
    }

    /// <summary>Преобразует ожидаемый отказ в безопасный JSON с текущей версией при конфликте.</summary>
    private static IResult Failure(TrainingException error) => Results.Json(
        new { code = error.Code, current = error.Current }, TrainingJson.Options, statusCode: error.Status);

    /// <summary>Возвращает UUID из principal, уже проверенного политикой Backend.</summary>
    private static string Owner(HttpContext context) => context.User.FindFirst("sub")!.Value;

    /// <summary>Читает JSON с отменой и пределом 30 MiB, включая запрос без Content-Length.</summary>
    private static async Task<byte[]?> ReadBodyAsync(HttpRequest request, CancellationToken cancellationToken)
    {
        if (request.ContentLength > TrainingStorage.MaximumBytes) return null;
        using var result = new MemoryStream();
        var buffer = new byte[81_920];
        while (true)
        {
            var read = await request.Body.ReadAsync(buffer.AsMemory(0,
                (int)Math.Min(buffer.Length, TrainingStorage.MaximumBytes + 1 - result.Length)), cancellationToken);
            if (read == 0) return result.ToArray();
            await result.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            if (result.Length > TrainingStorage.MaximumBytes) return null;
        }
    }
}
