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

/// <summary>Проверяет недоверенный wire JSON, границы HTTP и курсоры настоящего change feed.</summary>
[Trait("Category", "HTTP")]
public sealed class TrainingHttpContractTests
{
    /// <summary>Сценарии независимо проверяют envelope, типы и обязательные поля, а не только доменные числа.</summary>
    public static IEnumerable<object[]> InvalidRequests => new[]
    {
        "empty-body", "malformed", "object-root", "null-root", "empty-batch", "null-mutation", "oversized-batch",
        "duplicate-key", "unknown-kind", "negative-revision", "bad-id", "id-mismatch", "deleted-with-value",
        "missing-value", "null-value", "owner-overposting", "unknown-value-field", "missing-kind", "missing-id",
        "missing-revision", "missing-deleted", "missing-weight", "null-weight", "string-weight", "boolean-weight",
        "nonfinite-weight", "incorrect-field-case", "duplicate-json-property"
    }.Select(name => new object[] { name });

    /// <summary>Невалидный HTTP-пакет возвращает 400 и не оставляет даже владельца или версии.</summary>
    [Theory]
    [MemberData(nameof(InvalidRequests))]
    public async Task RejectsInvalidWireDataWithoutAnyWritesAsync(string scenario)
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        using var content = new StringContent(InvalidBody(scenario), Encoding.UTF8, "application/json");

        using var response = await client.PostAsync("/v1/training/changes", content);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<BackupDbContext>();
        Assert.Empty(await database.TrainingOwners.ToListAsync());
        Assert.Empty(await database.TrainingRecords.ToListAsync());
        Assert.Empty(await database.BodyWeights.ToListAsync());
    }

    /// <summary>Ошибочный query не читается как начальный курсор и не создаёт журнал.</summary>
    [Theory]
    [InlineData("after=-1")]
    [InlineData("after=not-a-number")]
    [InlineData("after=9223372036854775808")]
    [InlineData("limit=0")]
    [InlineData("limit=-1")]
    [InlineData("limit=101")]
    [InlineData("limit=NaN")]
    public async Task RejectsInvalidCursorAndPageSizeAsync(string query)
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        using var response = await client.GetAsync("/v1/training/changes?" + query);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    /// <summary>JSON нельзя передавать под видом plain text; отказ не доходит до storage.</summary>
    [Fact]
    public async Task RejectsUnsupportedContentTypeAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        using var response = await client.PostAsync("/v1/training/changes", new StringContent("[]"));
        Assert.Equal(HttpStatusCode.UnsupportedMediaType, response.StatusCode);
    }

    /// <summary>Пустая лента, текущий курсор и курсор из более новой БД имеют разные документированные ответы.</summary>
    [Fact]
    public async Task EmptyFeedAndRestoredDatabaseCursorAreExplicitAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var empty = await PageAsync(client, 0, 1);
        Assert.Empty(empty.Changes);
        Assert.Equal(0, empty.Cursor);
        Assert.False(empty.HasMore);
        var saved = Assert.Single(await TrainingTestData.SendAsync(client, TrainingTestData.Weight()));
        var current = await PageAsync(client, saved.Revision, 100);
        Assert.Empty(current.Changes);
        Assert.Equal(saved.Revision, current.Cursor);
        Assert.False(current.HasMore);

        using var ahead = await client.GetAsync($"/v1/training/changes?after={saved.Revision + 1}");
        Assert.Equal(HttpStatusCode.Conflict, ahead.StatusCode);
        using var error = JsonDocument.Parse(await ahead.Content.ReadAsByteArrayAsync());
        Assert.Equal("cursor_reset_required", error.RootElement.GetProperty("code").GetString());
    }

    /// <summary>Пагинация читает последние версии, включая правку и удаление уже прочитанных записей между страницами.</summary>
    [Fact]
    public async Task PagesDeliverUpdatesAndTombstonesCreatedBetweenRequestsAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var initial = new[] { TrainingTestData.Weight(), TrainingTestData.Weight(), TrainingTestData.Weight() };
        var saved = await TrainingTestData.SendAsync(client, initial);
        var first = await PageAsync(client, 0, 1);
        Assert.Equal(initial[0].Id, Assert.Single(first.Changes).Id);
        Assert.True(first.HasMore);
        var edited = initial[0] with { BaseRevision = saved[0].Revision };
        edited = TrainingTestData.Edit(edited, value => value["weightKG"] = 76);
        var deleted = initial[1] with { BaseRevision = saved[1].Revision, Deleted = true, Value = null };
        var changes = await TrainingTestData.SendAsync(client, edited, deleted);
        var late = Assert.Single(await TrainingTestData.SendAsync(client, TrainingTestData.Weight()));

        var cursor = first.Cursor;
        var received = new List<TrainingChange>();
        for (var pageNumber = 0; pageNumber < 10; pageNumber++)
        {
            var page = await PageAsync(client, cursor, 1);
            Assert.All(page.Changes, change => Assert.True(change.Revision > cursor));
            received.AddRange(page.Changes);
            cursor = page.Cursor;
            if (!page.HasMore) break;
        }

        Assert.Equal(new[] { saved[2].Revision, changes[0].Revision, changes[1].Revision, late.Revision }, received.Select(item => item.Revision));
        Assert.Equal(76, received.Single(item => item.Id == edited.Id).Value!.Value.GetProperty("weightKG").GetDouble());
        Assert.True(received.Single(item => item.Id == deleted.Id).Deleted);
        var replay = await PageAsync(client, 0, 100);
        Assert.Equal(4, replay.Changes.Count);
        Assert.Equal(4, replay.Changes.Select(item => item.Id).Distinct().Count());
        Assert.Equal(late.Revision, replay.Cursor);
        Assert.False(replay.HasMore);
    }

    /// <summary>До ста записей принимаются одним пакетом, а повтор tombstone не повышает версию.</summary>
    [Fact]
    public async Task AcceptsMaximumBatchAndAcknowledgesDeletionRetriesAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var mutations = Enumerable.Range(0, 100).Select(_ => TrainingTestData.Weight()).ToArray();
        var saved = await TrainingTestData.SendAsync(client, mutations);
        Assert.Equal(mutations.Select(item => item.Id), saved.Select(item => item.Id));
        var deletion = mutations[0] with { BaseRevision = saved[0].Revision, Deleted = true, Value = null };
        var first = Assert.Single(await TrainingTestData.SendAsync(client, deletion));
        var retried = Assert.Single(await TrainingTestData.SendAsync(client, deletion));
        Assert.True(first.Deleted);
        Assert.Equal(first.Revision, retried.Revision);
        var page = await PageAsync(client, saved[^1].Revision, 100);
        Assert.Equal(first.Revision, Assert.Single(page.Changes).Revision);
    }

    /// <summary>Пульс нельзя привязать к отсутствующей либо чужой тренировке; отказ откатывает метаданные.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task PulseRequiresAnOwnedWorkoutAsync(bool anotherOwnerHasWorkout)
    {
        using var factory = new BackendFactory();
        using var owner = factory.Client(Guid.NewGuid().ToString());
        using var other = factory.Client(Guid.NewGuid().ToString());
        var pulse = TrainingTestData.Mutation(TrainingKinds.HeartRate);
        if (anotherOwnerHasWorkout) await TrainingTestData.SendAsync(other, TrainingTestData.Mutation(TrainingKinds.Workout));
        using var response = await owner.PostAsJsonAsync("/v1/training/changes", new[] { pulse }, TrainingJson.Options);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        using var error = JsonDocument.Parse(await response.Content.ReadAsByteArrayAsync());
        Assert.Equal("workout_missing", error.RootElement.GetProperty("code").GetString());
        Assert.Empty((await PageAsync(owner, 0, 100)).Changes);
    }

    /// <summary>Лимитер нового маршрута изолирован по владельцу и срабатывает до удалённой introspection.</summary>
    [Fact]
    public async Task TrainingRateLimitIsPerOwnerAndPrecedesIntrospectionAsync()
    {
        using var factory = new BackendFactory();
        using var first = factory.Client(Guid.NewGuid().ToString());
        using var second = factory.Client(Guid.NewGuid().ToString());
        for (var request = 0; request < 240; request++)
        {
            using var accepted = await first.GetAsync("/v1/training/changes");
            Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        }
        using var denied = await first.GetAsync("/v1/training/changes");
        Assert.Equal(HttpStatusCode.TooManyRequests, denied.StatusCode);
        Assert.Equal(240, factory.Introspection.Calls);
        using var separate = await second.GetAsync("/v1/training/changes");
        Assert.Equal(HttpStatusCode.OK, separate.StatusCode);
        Assert.Equal(241, factory.Introspection.Calls);
    }

    /// <summary>Страница восстанавливается настоящим JSON-контрактом, без подмены Storage.</summary>
    private static async Task<TrainingPage> PageAsync(HttpClient client, long cursor, int limit)
    {
        var page = await client.GetFromJsonAsync<TrainingPage>($"/v1/training/changes?after={cursor}&limit={limit}", TrainingJson.Options);
        return Assert.IsType<TrainingPage>(page);
    }

    /// <summary>Каждый сценарий меняет один независимый аспект корректного минимального envelope.</summary>
    private static string InvalidBody(string scenario)
    {
        if (scenario == "empty-body") return "";
        if (scenario == "malformed") return "[{";
        if (scenario == "object-root") return "{}";
        if (scenario == "null-root") return "null";
        if (scenario == "empty-batch") return "[]";
        if (scenario == "null-mutation") return "[null]";
        if (scenario == "oversized-batch") return JsonSerializer.Serialize(Enumerable.Range(0, 101).Select(_ => TrainingTestData.Weight()), TrainingJson.Options);
        var payload = JsonSerializer.SerializeToNode(new[] { TrainingTestData.Weight() }, TrainingJson.Options)!.AsArray();
        var mutation = payload[0]!.AsObject();
        var value = mutation["value"]!.AsObject();
        switch (scenario)
        {
            case "duplicate-key": payload.Add(mutation.DeepClone()); break;
            case "unknown-kind": mutation["kind"] = "unknown"; break;
            case "negative-revision": mutation["baseRevision"] = -1; break;
            case "bad-id": mutation["id"] = "not-a-guid"; break;
            case "id-mismatch": value["id"] = Guid.NewGuid(); break;
            case "deleted-with-value": mutation["deleted"] = true; break;
            case "missing-value": mutation.Remove("value"); break;
            case "null-value": mutation["value"] = null; break;
            case "owner-overposting": mutation["ownerId"] = Guid.NewGuid(); break;
            case "unknown-value-field": value["unexpected"] = "reject"; break;
            case "missing-kind": mutation.Remove("kind"); break;
            case "missing-id": mutation.Remove("id"); break;
            case "missing-revision": mutation.Remove("baseRevision"); break;
            case "missing-deleted": mutation.Remove("deleted"); break;
            case "missing-weight": value.Remove("weightKG"); break;
            case "null-weight": value["weightKG"] = null; break;
            case "string-weight": value["weightKG"] = "75.25"; break;
            case "boolean-weight": value["weightKG"] = true; break;
            case "nonfinite-weight": value["weightKG"] = "NaN"; break;
            case "incorrect-field-case": mutation["Kind"] = mutation["kind"]!.DeepClone(); mutation.Remove("kind"); break;
            case "duplicate-json-property": return payload.ToJsonString(TrainingJson.Options).Replace("\"weightKG\":75.25", "\"weightKG\":75.25,\"weightKG\":77", StringComparison.Ordinal);
            default: throw new InvalidOperationException("Unknown test scenario.");
        }
        return payload.ToJsonString(TrainingJson.Options);
    }
}
