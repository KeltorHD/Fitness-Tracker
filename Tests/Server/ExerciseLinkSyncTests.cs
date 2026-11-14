using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет связь упражнения с каталогом через реальный синхронизируемый API.</summary>
[Trait("Category", "HTTP")]
public sealed class ExerciseLinkSyncTests
{
    /// <summary>Связь изолирована владельцем, поддерживает версии и синхронизирует удаление.</summary>
    [Fact]
    public async Task LinkSupportsIsolationConflictsAndDeletionAsync()
    {
        using var factory = new BackendFactory();
        using var first = factory.Client(Guid.NewGuid().ToString());
        using var second = factory.Client(Guid.NewGuid().ToString());
        var source = Guid.NewGuid();
        var target = Guid.NewGuid();
        var mutation = new TrainingMutation
        {
            Kind = TrainingKinds.ExerciseLink,
            Id = source,
            BaseRevision = 0,
            Deleted = false,
            Value = JsonSerializer.SerializeToElement(new ExerciseLinkData { Id = source, CatalogID = target }, TrainingJson.Options)
        };
        var saved = Assert.Single(await TrainingTestData.SendAsync(first, mutation));
        Assert.Equal(target, saved.Value!.Value.GetProperty("catalogID").GetGuid());
        var empty = await second.GetFromJsonAsync<TrainingPage>("/v1/training/changes?kinds=exerciseLink", TrainingJson.Options);
        Assert.Empty(Assert.IsType<TrainingPage>(empty).Changes);
        var replacement = mutation with
        {
            BaseRevision = saved.Revision,
            Value = JsonSerializer.SerializeToElement(new ExerciseLinkData { Id = source, CatalogID = Guid.NewGuid() }, TrainingJson.Options)
        };
        var updated = Assert.Single(await TrainingTestData.SendAsync(first, replacement));
        using var stale = await first.PostAsJsonAsync("/v1/training/changes", new[] { mutation }, TrainingJson.Options);
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        var deleted = Assert.Single(await TrainingTestData.SendAsync(first, replacement with
        { BaseRevision = updated.Revision, Deleted = true, Value = null }));
        var page = await first.GetFromJsonAsync<TrainingPage>("/v1/training/changes?kinds=exerciseLink", TrainingJson.Options);
        Assert.True(Assert.Single(Assert.IsType<TrainingPage>(page).Changes).Deleted);
        Assert.True(deleted.Deleted);
        await using var scope = factory.Services.CreateAsyncScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<BackupDbContext>().Set<TrainingExerciseLink>().ToListAsync());
    }

    /// <summary>Недопустимая связь не записывается и не создаёт версию.</summary>
    [Fact]
    public async Task RejectsSelfLinkAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var id = Guid.NewGuid();
        var mutation = new TrainingMutation
        {
            Kind = TrainingKinds.ExerciseLink,
            Id = id,
            BaseRevision = 0,
            Deleted = false,
            Value = JsonSerializer.SerializeToElement(new ExerciseLinkData { Id = id, CatalogID = id }, TrainingJson.Options)
        };
        using var response = await client.PostAsJsonAsync("/v1/training/changes", new[] { mutation }, TrainingJson.Options);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var page = await client.GetFromJsonAsync<TrainingPage>("/v1/training/changes?kinds=exerciseLink", TrainingJson.Options);
        Assert.Empty(Assert.IsType<TrainingPage>(page).Changes);
    }
}
