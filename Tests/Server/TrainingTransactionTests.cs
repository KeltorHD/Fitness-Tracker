using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет rollback после удаления дочерних строк и частичной записи нескольких агрегатов.</summary>
[Trait("Category", "HTTP")]
public sealed class TrainingTransactionTests
{
    /// <summary>Поздний конфликт откатывает уже выполненное каскадное удаление тренировки и pulse tombstone.</summary>
    [Fact]
    public async Task LaterVersionConflictRollsBackWorkoutAndPulseDeletionAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var seeded = await TrainingTestData.SendAsync(client, TrainingFixture.Mutations().ToArray());
        var workout = seeded.First(item => item.Kind == TrainingKinds.Workout);
        var deletion = new TrainingMutation { Kind = workout.Kind, Id = workout.Id, BaseRevision = workout.Revision, Deleted = true };
        var stale = TrainingTestData.Edit(TrainingTestData.Mutation(TrainingKinds.BodyWeight), value => value["weightKG"] = 90);

        using var response = await client.PostAsJsonAsync("/v1/training/changes", new[] { deletion, stale }, TrainingJson.Options);

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        var page = await client.GetFromJsonAsync<TrainingPage>("/v1/training/changes?limit=100", TrainingJson.Options);
        Assert.NotNull(page);
        Assert.Equal(seeded.Select(item => item.Revision), page.Changes.Select(item => item.Revision));
        Assert.All(page.Changes, item => Assert.False(item.Deleted));
        foreach (var (expected, actual) in seeded.Zip(page.Changes))
            Assert.True(JsonElement.DeepEquals(expected.Value!.Value, actual.Value!.Value));
    }

    /// <summary>Ошибка после изменения версии и очистки старых детей восстанавливает весь прежний граф; повтор проходит.</summary>
    [Theory]
    [InlineData(TrainingKinds.Workout)]
    [InlineData(TrainingKinds.Template)]
    [InlineData(TrainingKinds.BodyWeight)]
    [InlineData(TrainingKinds.HeartRate)]
    public async Task StorageFailureDuringReplacementRollsBackGraphAndVersionAsync(string kind)
    {
        // Arrange: сохраняем все связанные данные через HTTP и включаем отказ только после подготовки.
        var interceptor = new TrainingSaveInterceptor();
        using var factory = new BackendFactory(storageInterceptor: interceptor);
        using var client = factory.Client(Guid.NewGuid().ToString());
        var seeded = await TrainingTestData.SendAsync(client, TrainingFixture.Mutations().ToArray());
        var original = TrainingTestData.Mutation(kind);
        var version = seeded.Single(item => item.Kind == kind && item.Id == original.Id);
        var updated = Replacement(original with { BaseRevision = version.Revision });
        var additional = TrainingTestData.Weight();
        interceptor.Arm(2);

        // Act: metadata Save уже прошёл, ExecuteDelete старых детей выполнен, следующий Save отказывает.
        using var failed = await client.PostAsJsonAsync("/v1/training/changes", new[] { updated, additional }, TrainingJson.Options);

        // Assert: отдельно читаем журнал новым context, не опираясь на откатившийся ChangeTracker.
        Assert.Equal(HttpStatusCode.InternalServerError, failed.StatusCode);
        Assert.DoesNotContain("private-storage-sentinel", await failed.Content.ReadAsStringAsync());
        var preserved = await client.GetFromJsonAsync<TrainingPage>("/v1/training/changes?limit=100", TrainingJson.Options);
        Assert.NotNull(preserved);
        Assert.Equal(seeded.Select(item => item.Revision), preserved.Changes.Select(item => item.Revision));
        foreach (var (expected, actual) in seeded.Zip(preserved.Changes))
        {
            Assert.Equal(expected.Id, actual.Id);
            Assert.True(JsonElement.DeepEquals(expected.Value!.Value, actual.Value!.Value));
        }
        interceptor.Arm(0);
        var retried = await TrainingTestData.SendAsync(client, updated, additional);
        Assert.Equal(version.Id, retried[0].Id);
        Assert.Equal(additional.Id, retried[1].Id);
        Assert.True(retried[0].Revision > seeded[^1].Revision);
    }

    /// <summary>Отмена после первой/второй записи откатывает также owner counter и позволяет безопасный повтор.</summary>
    [Theory]
    [InlineData(2)]
    [InlineData(4)]
    public async Task CancellationAfterPartialBatchDoesNotLeaveRowsOrRevisionsAsync(int saveNumber)
    {
        var interceptor = new TrainingSaveInterceptor();
        using var factory = new BackendFactory(storageInterceptor: interceptor);
        var owner = Guid.NewGuid().ToString();
        using var client = factory.Client(owner);
        var batch = new[] { TrainingTestData.Weight(), TrainingTestData.Weight() };
        using var cancellation = new CancellationTokenSource();
        interceptor.Arm(saveNumber, cancellation);
        await using (var scope = factory.Services.CreateAsyncScope())
        {
            var storage = scope.ServiceProvider.GetRequiredService<TrainingStorage>();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => storage.ApplyBatchAsync(owner, batch, cancellation.Token));
        }
        interceptor.Arm(0);
        await using (var verification = factory.Services.CreateAsyncScope())
        {
            var database = verification.ServiceProvider.GetRequiredService<BackupDbContext>();
            Assert.Empty(await database.TrainingOwners.ToListAsync());
            Assert.Empty(await database.TrainingRecords.ToListAsync());
            Assert.Empty(await database.BodyWeights.ToListAsync());
        }
        var retry = await TrainingTestData.SendAsync(client, batch);
        Assert.Equal(new long[] { 1, 2 }, retry.Select(item => item.Revision));
    }

    /// <summary>Связанный граф заменяется полностью, а не добавляется поверх прежних строк.</summary>
    internal static TrainingMutation Replacement(TrainingMutation original) => TrainingTestData.Edit(original, value =>
    {
        switch (original.Kind)
        {
            case TrainingKinds.Workout:
                var row = value["exercises"]![1]!.DeepClone().AsObject();
                row["supersetID"] = null;
                row["id"] = Guid.NewGuid();
                row["sets"]![0]!["id"] = Guid.NewGuid();
                value["exercises"] = new JsonArray(row);
                value["pauses"] = new JsonArray();
                value["pausedSeconds"] = 0;
                value["notes"] = "Changed workout";
                break;
            case TrainingKinds.Template:
                var target = value["exercises"]![1]!.DeepClone().AsObject();
                target["supersetID"] = null;
                target["id"] = Guid.NewGuid();
                value["exercises"] = new JsonArray(target);
                value["variations"] = new JsonArray();
                value["name"] = "Changed template";
                break;
            case TrainingKinds.BodyWeight: value["weightKG"] = 78.125; break;
            case TrainingKinds.HeartRate:
                value["readings"] = new JsonArray(value["readings"]![0]!.DeepClone());
                break;
            default: throw new InvalidOperationException("Unknown fixture kind.");
        }
    });
}
