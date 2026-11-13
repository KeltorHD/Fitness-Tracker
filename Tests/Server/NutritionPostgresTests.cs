using System.Text.Json;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет миграцию и все поля питания на настоящем одноразовом PostgreSQL.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class NutritionPostgresTests
{
    /// <summary>Обновление прежней схемы сохраняет журнал; питание читается из таблиц, удаление аккаунта каскадно.</summary>
    [Fact]
    public async Task UpgradePreservesExistingTrainingAndNutritionRoundTripsBeforeAccountDeletionAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var database = new BackupDbContext(new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options);
        var previous = database.Database.GetMigrations().Where(x => !x.EndsWith("AddNutritionAndSupplementSchedules", StringComparison.Ordinal)).Last();
        await database.GetService<IMigrator>().MigrateAsync(previous, cancellationToken);
        var owner = Guid.NewGuid().ToString();
        var storage = new TrainingStorage(database);
        var original = await storage.ApplyAsync(owner, TrainingTestData.Weight(), cancellationToken);
        await database.Database.MigrateAsync(cancellationToken);
        Assert.False(database.Database.HasPendingModelChanges());
        var values = NutritionFixture.Mutations();
        await storage.ApplyBatchAsync(owner, values, cancellationToken);
        var page = await storage.ChangesAsync(owner, original.Revision, 100, cancellationToken);
        foreach (var (expected, actual) in values.Zip(page.Changes))
            Assert.True(JsonElement.DeepEquals(TrainingValidation.Canonical(expected.Kind, expected.Id, expected.Value!.Value), actual.Value!.Value));
        Assert.Equal(values.Count, page.Changes.Count);
        Assert.Single(await database.BodyWeights.ToListAsync(cancellationToken));
        if (Environment.GetEnvironmentVariable("FITLIFE_TEST_NUTRITION_PAGE") is { Length: > 0 } path)
            await File.WriteAllBytesAsync(path, JsonSerializer.SerializeToUtf8Bytes(page, TrainingJson.Options), cancellationToken);
        await new BackupStorage(database, TimeProvider.System).DeleteAccount(owner, cancellationToken);
        Assert.Empty(await database.Set<NutritionFood>().ToListAsync(cancellationToken));
        Assert.Empty(await database.Set<NutritionProduct>().ToListAsync(cancellationToken));
        Assert.Empty(await database.Set<NutritionPlan>().ToListAsync(cancellationToken));
        Assert.Empty(await database.Set<NutritionDose>().ToListAsync(cancellationToken));
        Assert.Empty(await database.Set<NutritionProfileRow>().ToListAsync(cancellationToken));
        Assert.Empty(await database.Set<NutritionWater>().ToListAsync(cancellationToken));
        Assert.Empty(await database.TrainingRecords.ToListAsync(cancellationToken));
    }
    /// <summary>Два устройства с одним слотом сохраняют единственный факт приёма; различия требуют CAS-конфликта.</summary>
    [Fact]
    public async Task ConcurrentScheduledIntakeCannotCreateDuplicateOrSilentlyOverwriteAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options;
        await using (var database = new BackupDbContext(options)) await database.Database.MigrateAsync(cancellationToken);
        var original = NutritionFixture.Mutations()[3];
        var changed = TrainingTestData.Edit(original, value => value["amount"] = 25);
        var owner = Guid.NewGuid().ToString();
        var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        async Task<bool> SaveAsync(TrainingMutation mutation)
        {
            await using var database = new BackupDbContext(options);
            await gate.Task.WaitAsync(cancellationToken);
            try { await new TrainingStorage(database).ApplyAsync(owner, mutation, cancellationToken); return true; }
            catch (TrainingException error) when (error.Status == 409 && error.Code == "training_conflict") { return false; }
        }
        var first = SaveAsync(original);
        var second = SaveAsync(changed);
        gate.SetResult();
        var results = await Task.WhenAll(first, second);
        Assert.Single(results, value => value);
        await using var verification = new BackupDbContext(options);
        Assert.Single(await verification.Set<NutritionDose>().ToListAsync(cancellationToken));
        Assert.Single(await verification.TrainingRecords.ToListAsync(cancellationToken));
    }

}
