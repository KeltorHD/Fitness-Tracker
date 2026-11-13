using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Читает синтетический fixture, сформированный настоящим Swift Codable.</summary>
internal static class NutritionFixture
{
    internal const string KINDS = "foodEntry,waterEntry,supplementEntry,supplementPlan,nutritionProfile";
    /// <summary>Возвращает независимые мутации всех типов питания, единиц и расписаний.</summary>
    internal static List<TrainingMutation> Mutations()
    {
        using var document = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "Fixtures", "nutrition-contract.json")));
        return document.RootElement.EnumerateArray().Select(entry => new TrainingMutation
        {
            Kind = entry.GetProperty("kind").GetString()!,
            Id = entry.GetProperty("value").GetProperty("id").GetGuid(),
            BaseRevision = 0,
            Deleted = false,
            Value = entry.GetProperty("value").Clone()
        }).ToList();
    }
    /// <summary>Читает все типы питания через настоящий HTTP change feed.</summary>
    internal static async Task<TrainingPage> PageAsync(HttpClient client, long after = 0, int limit = 100)
    {
        using var response = await client.GetAsync($"/v1/training/changes?after={after}&limit={limit}&kinds={KINDS}");
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<TrainingPage>(TrainingJson.Options))!;
    }
}

/// <summary>Проверяет сохранение питания, офлайн-повторы, конфликты и изоляцию через реальный API.</summary>
[Trait("Category", "HTTP")]
public sealed class NutritionSyncTests
{
    /// <summary>Проверяет все поля Swift, JPEG, состав и отдельные таблицы без архивного payload.</summary>
    [Fact]
    public async Task SwiftNutritionRoundTripsAllFieldsAndRetriesWithoutNewRevisionsAsync()
    {
        using var factory = new BackendFactory();
        var owner = Guid.NewGuid().ToString();
        using var client = factory.Client(owner);
        var mutations = NutritionFixture.Mutations();
        var saved = await TrainingTestData.SendAsync(client, mutations.ToArray());
        var repeated = await TrainingTestData.SendAsync(client, mutations.ToArray());
        Assert.Equal(saved.Select(x => x.Revision), repeated.Select(x => x.Revision));
        var page = await NutritionFixture.PageAsync(client);
        Assert.Equal(mutations.Count, page.Changes.Count);
        foreach (var (expected, actual) in mutations.Zip(page.Changes))
            Assert.True(JsonElement.DeepEquals(TrainingValidation.Canonical(expected.Kind, expected.Id, expected.Value!.Value), actual.Value!.Value), expected.Kind);
        using var other = factory.Client(Guid.NewGuid().ToString());
        Assert.Empty((await NutritionFixture.PageAsync(other)).Changes);
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<BackupDbContext>();
        Assert.Single(await database.Set<NutritionFood>().ToListAsync());
        Assert.Equal(7, (await database.Set<NutritionFood>().SingleAsync()).Photo!.Length);
        Assert.Equal(2, await database.Set<NutritionProduct>().CountAsync());
        Assert.Equal(8, await database.Set<NutritionDose>().CountAsync());
        Assert.Empty(await database.Backups.ToListAsync());
    }

    /// <summary>Проверяет CAS, атомарный откат пакета, удаление и сохранение фактов после удаления расписания.</summary>
    [Fact]
    public async Task ConflictsRollbackBatchAndPlanDeletionPreservesHistoryAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var mutations = NutritionFixture.Mutations();
        var saved = await TrainingTestData.SendAsync(client, mutations.ToArray());
        var food = mutations[0] with { BaseRevision = saved[0].Revision };
        var edit = TrainingTestData.Edit(food, x => x["note"] = "Новая заметка");
        var updated = Assert.Single(await TrainingTestData.SendAsync(client, edit));
        using var conflict = await client.PostAsJsonAsync("/v1/training/changes", new[] { TrainingTestData.Edit(food, x => x["note"] = "Устаревшее изменение") }, TrainingJson.Options);
        Assert.Equal(HttpStatusCode.Conflict, conflict.StatusCode);
        var before = await NutritionFixture.PageAsync(client);
        var invalidPlan = TrainingTestData.Edit(mutations[2] with { BaseRevision = saved[2].Revision }, x => x["times"] = new JsonArray(540, 540));
        using var failed = await client.PostAsJsonAsync("/v1/training/changes", new[] { TrainingTestData.Edit(edit with { BaseRevision = updated.Revision }, x => x["note"] = "Откатить"), invalidPlan }, TrainingJson.Options);
        Assert.Equal(HttpStatusCode.BadRequest, failed.StatusCode);
        Assert.Empty((await NutritionFixture.PageAsync(client, before.Cursor)).Changes);
        var deleted = await TrainingTestData.SendAsync(client, mutations[2] with { BaseRevision = saved[2].Revision, Deleted = true, Value = null });
        var tombstone = Assert.Single((await NutritionFixture.PageAsync(client, before.Cursor)).Changes);
        Assert.True(tombstone.Deleted);
        Assert.Equal(deleted[0].Revision, tombstone.Revision);
        var page = await NutritionFixture.PageAsync(client);
        Assert.False(page.Changes.Single(x => x.Id == mutations[3].Id).Deleted);
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<BackupDbContext>();
        Assert.Empty(await database.Set<NutritionPlan>().ToListAsync());
        Assert.Equal(7, await database.Set<NutritionDose>().CountAsync());
    }

    /// <summary>Отклоняет недоверенные количества, фотографии, состав и расписания до любых записей.</summary>
    [Theory]
    [InlineData("food", "photo")]
    [InlineData("food", "portion")]
    [InlineData("food", "duplicate")]
    [InlineData("food", "unknown")]
    [InlineData("water", "zero")]
    [InlineData("dose", "negative")]
    [InlineData("dose", "unit")]
    [InlineData("dose", "missingName")]
    [InlineData("dose", "partialLink")]
    [InlineData("dose", "nutrition")]
    [InlineData("plan", "times")]
    [InlineData("plan", "weekdays")]
    [InlineData("plan", "interval")]
    [InlineData("plan", "zone")]
    [InlineData("plan", "end")]
    [InlineData("profile", "goal")]
    [InlineData("profile", "duplicate")]
    public async Task InvalidNutritionCannotLeavePartialDataAsync(string type, string error)
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var values = NutritionFixture.Mutations();
        var index = type switch { "food" => 0, "water" => 1, "plan" => 2, "profile" => 4, _ => 5 };
        var invalid = TrainingTestData.Edit(values[index], value =>
        {
            switch (type, error)
            {
                case ("food", "photo"): value["photo"] = Convert.ToBase64String([1, 2, 3]); break;
                case ("food", "portion"): value["portions"]![0]!["amount"] = 0; break;
                case ("food", "duplicate"): value["portions"]!.AsArray().Add(value["portions"]![0]!.DeepClone()); break;
                case ("food", "unknown"): value["ownerId"] = Guid.NewGuid().ToString(); break;
                case ("water", _): value["milliliters"] = 0; break;
                case ("dose", "negative"): value["amount"] = -1; break;
                case ("dose", "unit"): value["unit"] = "buckets"; break;
                case ("dose", "missingName"): value["name"] = " "; break;
                case ("dose", "partialLink"): value["planID"] = Guid.NewGuid(); break;
                case ("dose", "nutrition"): value["nutritionPerBasis"]!["protein"] = 10000; break;
                case ("plan", "times"): value["times"] = new JsonArray(540, 540); break;
                case ("plan", "weekdays"): value["weekdays"] = new JsonArray(); break;
                case ("plan", "interval"): value["intervalDays"] = 0; break;
                case ("plan", "zone"): value["timeZoneID"] = "Invalid/Nowhere"; break;
                case ("plan", "end"): value["endDate"] = 0; break;
                case ("profile", "goal"): value["goal"]!["calories"] = -1; break;
                case ("profile", "duplicate"): value["favorites"]!.AsArray().Add(value["favorites"]![0]!.DeepClone()); break;
            }
        });
        using var response = await client.PostAsJsonAsync("/v1/training/changes", new[] { invalid }, TrainingJson.Options);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<BackupDbContext>();
        Assert.Empty(await database.TrainingRecords.ToListAsync());
        Assert.Empty(await database.TrainingOwners.ToListAsync());
    }

    /// <summary>Проверяет фильтр типов, страницы, удаления и отсутствие питания в прежнем feed.</summary>
    [Fact]
    public async Task FeedPaginatesNutritionWithoutBreakingTrainingClientsAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var values = NutritionFixture.Mutations();
        await TrainingTestData.SendAsync(client, values.ToArray());
        var found = new List<TrainingChange>();
        long cursor = 0;
        while (true)
        {
            var page = await NutritionFixture.PageAsync(client, cursor, 2);
            Assert.True(page.Cursor > cursor);
            found.AddRange(page.Changes);
            cursor = page.Cursor;
            if (!page.HasMore) break;
        }
        Assert.Equal(values.Count, found.Count);
        using var response = await client.GetAsync("/v1/training/changes");
        var original = await response.Content.ReadFromJsonAsync<TrainingPage>(TrainingJson.Options);
        Assert.Empty(original!.Changes);
        using var invalid = await client.GetAsync("/v1/training/changes?kinds=unknown");
        Assert.Equal(HttpStatusCode.BadRequest, invalid.StatusCode);
    }

    /// <summary>Новые типы питания требуют действующий JWT для аудитории Backend.</summary>
    [Fact]
    public async Task NutritionRequiresAuthenticatedActiveBackendTokenAsync()
    {
        using var factory = new BackendFactory();
        using var anonymous = factory.Client();
        using var response = await anonymous.PostAsJsonAsync("/v1/training/changes", NutritionFixture.Mutations(), TrainingJson.Options);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        using var wrongAudience = factory.Client(Guid.NewGuid().ToString(), audience: "another-api");
        using var denied = await wrongAudience.GetAsync("/v1/training/changes?kinds=foodEntry");
        Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
        factory.Introspection.Active = false;
        using var revoked = factory.Client(Guid.NewGuid().ToString());
        using var rejected = await revoked.GetAsync("/v1/training/changes?kinds=foodEntry");
        Assert.Equal(HttpStatusCode.Unauthorized, rejected.StatusCode);
    }
}
