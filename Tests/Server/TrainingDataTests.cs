using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Согласует тестовые запросы и архивы с JSON, сгенерированным настоящим Swift Core.</summary>
internal static class TrainingFixture
{
    /// <summary>Создаёт текущий полный v4 архив из реального Swift fixture без пульса.</summary>
    internal static byte[] Archive(IEnumerable<TrainingMutation> mutations)
    {
        var values = mutations.ToList();
        return JsonSerializer.SerializeToUtf8Bytes(new
        {
            format = "com.fitlife.archive",
            version = 4,
            exportedAt = 1700000000.1234567,
            workouts = values.Where(x => x.Kind == TrainingKinds.Workout).Select(x => x.Value),
            templates = values.Where(x => x.Kind == TrainingKinds.Template).Select(x => x.Value),
            bodyWeights = values.Where(x => x.Kind == TrainingKinds.BodyWeight).Select(x => x.Value)
        }, TrainingJson.Options);
    }

    /// <summary>Читает воспроизводимый fixture действующего Core и создаёт мутации с исходными UUID.</summary>
    internal static List<TrainingMutation> Mutations()
    {
        using var document = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "Fixtures", "training-contract.json")));
        return document.RootElement.EnumerateArray().Select(entry =>
        {
            var kind = entry.GetProperty("kind").GetString()!;
            var value = entry.GetProperty("value");
            return new TrainingMutation
            {
                Kind = kind,
                Id = value.GetProperty(kind == TrainingKinds.HeartRate ? "workoutID" : "id").GetGuid(),
                BaseRevision = 0,
                Deleted = false,
                Value = value.Clone()
            };
        }).ToList();
    }
}

/// <summary>Проверяет настоящий защищённый API и нормализованное хранение данных действующего Swift Core.</summary>
[Trait("Category", "HTTP")]
public sealed class TrainingDataTests
{
    /// <summary>Сохраняет и возвращает новую мышцу в синхронизируемом шаблоне.</summary>
    [Theory]
    [InlineData("tibialis anterior")]
    [InlineData("hip flexors")]
    public async Task DetailedMuscleSelectionRoundTripsThroughTrainingSyncAsync(string muscle)
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var initial = TrainingFixture.Mutations().Single(x => x.Kind == TrainingKinds.Template);
        var value = JsonNode.Parse(initial.Value!.Value.GetRawText())!.AsObject();
        value["muscles"] = new JsonArray(muscle);
        var mutation = initial with { Value = JsonSerializer.SerializeToElement(value, TrainingJson.Options) };

        var saved = await SendAsync(client, mutation);
        Assert.Equal(muscle, saved.Value!.Value.GetProperty("muscles")[0].GetString());
        using var response = await client.GetAsync("/v1/training/changes?after=0&limit=100");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var page = await response.Content.ReadFromJsonAsync<TrainingPage>(TrainingJson.Options);
        var restored = Assert.Single(Assert.IsType<TrainingPage>(page).Changes);
        Assert.Equal(muscle, restored.Value!.Value.GetProperty("muscles")[0].GetString());
    }

    /// <summary>Отклоняет запись, чей канонический ответ вырос за 30 MiB после добавления необязательных null-полей.</summary>
    [Fact]
    public async Task CanonicalGrowthCannotStoreAnUndownloadableRecordAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var initial = TrainingFixture.Mutations()[0];
        var value = JsonNode.Parse(initial.Value!.Value.GetRawText())!.AsObject();
        value["notes"] = "";
        var mutation = initial with { Value = JsonSerializer.SerializeToElement(value, TrainingJson.Options) };
        var overhead = JsonSerializer.SerializeToUtf8Bytes(new[] { mutation }, TrainingJson.Options).Length;
        value["notes"] = new string('a', TrainingStorage.MaximumBytes - overhead);
        mutation = initial with { Value = JsonSerializer.SerializeToElement(value, TrainingJson.Options) };
        var body = JsonSerializer.SerializeToUtf8Bytes(new[] { mutation }, TrainingJson.Options);
        Assert.Equal(TrainingStorage.MaximumBytes, body.Length);
        var canonical = TrainingValidation.Canonical(mutation.Kind, mutation.Id, mutation.Value!.Value);
        Assert.True(Encoding.UTF8.GetByteCount(canonical.GetRawText()) > TrainingStorage.MaximumBytes);

        using var request = new ByteArrayContent(body);
        request.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        using var response = await client.PostAsync("/v1/training/changes", request);

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<BackupDbContext>();
        Assert.Empty(await database.TrainingRecords.ToListAsync());
        Assert.Empty(await database.Workouts.ToListAsync());
    }

    /// <summary>Проверяет все поля Core через настоящий HTTP host и нормализованные таблицы без архивных blob.</summary>
    [Fact]
    public async Task SwiftContractRoundTripsEveryTrainingFeatureWithoutArchivePayloadAsync()
    {
        // Arrange: JSON сгенерирован настоящим Swift Core, включая все сохраняемые варианты данных.
        using var factory = new BackendFactory();
        var owner = Guid.NewGuid().ToString();
        using var client = factory.Client(owner);
        var mutations = TrainingFixture.Mutations();

        // Act: весь граф сохраняется одним пакетом и читается через change feed.
        using var saved = await client.PostAsJsonAsync("/v1/training/changes", mutations, TrainingJson.Options);
        Assert.Equal(HttpStatusCode.OK, saved.StatusCode);
        using var listed = await client.GetAsync("/v1/training/changes?after=0&limit=100");
        Assert.Equal(HttpStatusCode.OK, listed.StatusCode);
        var page = await listed.Content.ReadFromJsonAsync<TrainingPage>(TrainingJson.Options);
        Assert.NotNull(page);
        Assert.False(page.HasMore);
        Assert.Equal(mutations.Count, page.Changes.Count);

        // Assert: сравниваем каждый JSON-field с DTO исходного Swift fixture, а не только количество строк.
        foreach (var (expected, actual) in mutations.Zip(page.Changes))
        {
            Assert.Equal(expected.Kind, actual.Kind);
            Assert.Equal(expected.Id, actual.Id);
            Assert.False(actual.Deleted);
            Assert.True(actual.Revision > 0);
            var canonical = TrainingValidation.Canonical(expected.Kind, expected.Id, expected.Value!.Value);
            Assert.True(JsonElement.DeepEquals(canonical, actual.Value!.Value), expected.Kind);
        }
        Assert.Equal(page.Changes[^1].Revision, page.Cursor);
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<BackupDbContext>();
        Assert.Empty(await database.Backups.ToListAsync());
        Assert.Equal(4, await database.Workouts.CountAsync());
        Assert.Equal(1, await database.Templates.CountAsync());
        Assert.Equal(2, await database.BodyWeights.CountAsync());
        Assert.Equal(2, await database.HeartRateRecordings.CountAsync());
        Assert.Equal(4, await database.Set<TrainingHeartRateReading>().CountAsync());
        Assert.Equal(3, await database.Set<TrainingDropStage>().CountAsync());
    }

    /// <summary>Проверяет повтор после потери ответа и возврат текущей версии при устаревшей записи.</summary>
    [Fact]
    public async Task RetryIsIdempotentAndStaleUpdateReturnsCurrentValueWithoutOverwritingAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var initial = TrainingFixture.Mutations()[0];
        var created = await SendAsync(client, initial);
        var repeated = await SendAsync(client, initial);
        Assert.Equal(created.Revision, repeated.Revision);
        Assert.True(JsonElement.DeepEquals(created.Value!.Value, repeated.Value!.Value));
        var json = JsonNode.Parse(initial.Value!.Value.GetRawText())!.AsObject();
        json["name"] = "Изменено на другом устройстве";
        var edited = initial with { BaseRevision = created.Revision, Value = JsonSerializer.SerializeToElement(json) };
        var updated = await SendAsync(client, edited);
        Assert.True(updated.Revision > created.Revision);
        var acknowledged = await SendAsync(client, edited);
        Assert.Equal(updated.Revision, acknowledged.Revision);
        Assert.True(JsonElement.DeepEquals(updated.Value!.Value, acknowledged.Value!.Value));
        json["name"] = "Не затирать сервер этой устаревшей записью";
        using var stale = await client.PostAsJsonAsync("/v1/training/changes",
            new[] { edited with { Value = JsonSerializer.SerializeToElement(json) } }, TrainingJson.Options);
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        using var error = JsonDocument.Parse(await stale.Content.ReadAsByteArrayAsync());
        Assert.Equal("training_conflict", error.RootElement.GetProperty("code").GetString());
        Assert.Equal(updated.Revision, error.RootElement.GetProperty("current").GetProperty("revision").GetInt64());
        var page = await client.GetFromJsonAsync<TrainingPage>("/v1/training/changes", TrainingJson.Options);
        Assert.Equal("Изменено на другом устройстве", page!.Changes.Single().Value!.Value.GetProperty("name").GetString());
    }

    /// <summary>Проверяет сохранность пульса при правке, каскад удаления и независимость взвешиваний.</summary>
    [Fact]
    public async Task WorkoutEditsPreservePulseAndDeletionTombstonesPulseButPreservesWeighInsAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var mutations = TrainingFixture.Mutations();
        using var saved = await client.PostAsJsonAsync("/v1/training/changes", mutations, TrainingJson.Options);
        saved.EnsureSuccessStatusCode();
        var first = (await saved.Content.ReadFromJsonAsync<List<TrainingChange>>(TrainingJson.Options))![0];
        var json = JsonNode.Parse(mutations[0].Value!.Value.GetRawText())!.AsObject();
        json["notes"] = "Исправленная заметка";
        var edited = await SendAsync(client, mutations[0] with { BaseRevision = first.Revision, Value = JsonSerializer.SerializeToElement(json) });
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<BackupDbContext>();
        Assert.Equal(2, await database.HeartRateRecordings.CountAsync());
        Assert.Equal(4, await database.Set<TrainingHeartRateReading>().CountAsync());
        var deleted = await SendAsync(client, mutations[0] with { BaseRevision = edited.Revision, Deleted = true, Value = null });
        var page = await client.GetFromJsonAsync<TrainingPage>($"/v1/training/changes?after={edited.Revision}", TrainingJson.Options);
        Assert.Equal(2, page!.Changes.Count);
        Assert.All(page.Changes, change => Assert.True(change.Deleted));
        Assert.Equal(TrainingKinds.Workout, page.Changes[0].Kind);
        Assert.Equal(TrainingKinds.HeartRate, page.Changes[1].Kind);
        Assert.Equal(deleted.Revision, page.Changes[0].Revision);
        Assert.Equal(1, await database.HeartRateRecordings.CountAsync());
        Assert.Equal(2, await database.BodyWeights.CountAsync());
        Assert.Contains(await database.BodyWeights.ToListAsync(), x => x.WorkoutID == first.Id);
    }

    /// <summary>Проверяет полный откат пакета при ошибке поздней записи, включая счётчик версий.</summary>
    [Fact]
    public async Task FailedBatchRollsBackEarlierGraphsAndRevisionCounterAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var mutations = TrainingFixture.Mutations();
        var corrupt = JsonNode.Parse(mutations[1].Value!.Value.GetRawText())!.AsObject();
        corrupt["pausedSeconds"] = 999;
        using var response = await client.PostAsJsonAsync("/v1/training/changes", new[]
        { mutations[0], mutations[1] with { Value = JsonSerializer.SerializeToElement(corrupt) } }, TrainingJson.Options);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<BackupDbContext>();
        Assert.Empty(await database.TrainingOwners.ToListAsync());
        Assert.Empty(await database.TrainingRecords.ToListAsync());
        Assert.Empty(await database.Workouts.ToListAsync());
        Assert.Empty(await database.Exercises.ToListAsync());
        Assert.Empty(await database.Set<TrainingSet>().ToListAsync());
    }

    /// <summary>Проверяет изоляцию UUID владельцев, обязательный вход и немедленный запрет отозванной сессии.</summary>
    [Fact]
    public async Task OwnerIsolationAndRevocationApplyBeforeReadingOrMutatingTrainingAsync()
    {
        using var factory = new BackendFactory();
        using var first = factory.Client(Guid.NewGuid().ToString());
        using var second = factory.Client(Guid.NewGuid().ToString());
        using var anonymous = factory.Client();
        var mutation = TrainingFixture.Mutations()[0];
        await SendAsync(first, mutation);
        var other = await second.GetFromJsonAsync<TrainingPage>("/v1/training/changes", TrainingJson.Options);
        Assert.Empty(other!.Changes);
        var secondChange = await SendAsync(second, mutation);
        Assert.Equal(1, secondChange.Revision);
        using var unauthenticated = await anonymous.GetAsync("/v1/training/changes");
        Assert.Equal(HttpStatusCode.Unauthorized, unauthenticated.StatusCode);
        factory.Introspection.Active = false;
        using var revoked = await first.GetAsync("/v1/training/changes");
        Assert.Equal(HttpStatusCode.Unauthorized, revoked.StatusCode);
        using var denied = await first.PostAsJsonAsync("/v1/training/changes", new[] { mutation }, TrainingJson.Options);
        Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
    }

    /// <summary>Отправляет одну проверяемую мутацию через HTTP и требует единственное подтверждение.</summary>
    private static async Task<TrainingChange> SendAsync(HttpClient client, TrainingMutation mutation)
    {
        using var response = await client.PostAsJsonAsync("/v1/training/changes", new[] { mutation }, TrainingJson.Options);
        response.EnsureSuccessStatusCode();
        return Assert.Single((await response.Content.ReadFromJsonAsync<List<TrainingChange>>(TrainingJson.Options))!);
    }
}
