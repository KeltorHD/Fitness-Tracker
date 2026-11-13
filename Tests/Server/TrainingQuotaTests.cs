using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет документированные квоты на настоящем PostgreSQL с полными графами и сохранёнными tombstones.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class TrainingQuotaTests
{
    /// <summary>Граница принимается, лишняя запись отклоняется, правка допускается и удаление освобождает живую квоту.</summary>
    [Theory]
    [InlineData(TrainingKinds.Workout, 10000)]
    [InlineData(TrainingKinds.Template, 1000)]
    [InlineData(TrainingKinds.BodyWeight, 10000)]
    public async Task ActiveQuotaAllowsBoundaryEditsAndReleasesCapacityAfterDeletionAsync(string kind, int limit)
    {
        // Arrange: полные допустимые графы занимают все места, кроме последнего.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var database = new BackupDbContext(new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options);
        await database.Database.MigrateAsync(cancellationToken);
        var owner = Guid.NewGuid().ToString();
        await TrainingQuotaSeed.ActiveAsync(database, owner, kind, limit - 1, cancellationToken);
        var storage = new TrainingStorage(database);
        var boundary = TrainingTestData.Mutation(kind);
        // Act / Assert: последняя запись принята, следующая отклонена без изменения counter.
        var accepted = await storage.ApplyAsync(owner, boundary, cancellationToken);
        var nextId = Guid.NewGuid();
        var next = TrainingTestData.Edit(boundary with { Id = nextId }, value => value["id"] = nextId);

        var refused = await Assert.ThrowsAsync<TrainingException>(() => storage.ApplyAsync(owner, next, cancellationToken));
        Assert.Equal(409, refused.Status);
        Assert.Equal("training_limit", refused.Code);
        Assert.Equal(limit, await database.TrainingRecords.CountAsync(item => item.OwnerId == owner && !item.Deleted, cancellationToken));
        Assert.Equal(accepted.Revision, (await database.TrainingOwners.AsNoTracking().SingleAsync(cancellationToken)).Revision);

        // Act / Assert: правка доступна при полной квоте, удаление освобождает одно место.
        var updated = TrainingTestData.Edit(boundary with { BaseRevision = accepted.Revision }, value =>
        {
            if (kind == TrainingKinds.BodyWeight) value["weightKG"] = 76;
            else value["name"] = "Edit at quota";
        });
        var changed = await storage.ApplyAsync(owner, updated, cancellationToken);
        var deletion = await storage.ApplyAsync(owner, updated with { BaseRevision = changed.Revision, Deleted = true, Value = null }, cancellationToken);
        var retried = await storage.ApplyAsync(owner, next, cancellationToken);
        Assert.True(retried.Revision > deletion.Revision);
        Assert.Equal(limit, await database.TrainingRecords.CountAsync(item => item.OwnerId == owner && !item.Deleted, cancellationToken));
        Assert.Equal(limit + 1, await database.TrainingRecords.CountAsync(cancellationToken));
        Assert.True((await database.TrainingRecords.AsNoTracking().SingleAsync(item => item.Id == boundary.Id && item.Kind == kind, cancellationToken)).Deleted);
    }

    /// <summary>Общая квота учитывает 100 000 метаданных с удалениями, но позволяет исправить существующий UUID.</summary>
    [Fact]
    public async Task MetadataQuotaCountsTombstonesAndDoesNotBlockExistingRecordAsync()
    {
        // Arrange: сохранённые удаления оставляют одно место в общей квоте metadata.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var database = new BackupDbContext(new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options);
        await database.Database.MigrateAsync(cancellationToken);
        var owner = Guid.NewGuid().ToString();
        await TrainingQuotaSeed.TombstonesAsync(database, owner, 99999, cancellationToken);
        var storage = new TrainingStorage(database);
        var boundary = TrainingTestData.Weight();
        // Act / Assert: 100 000-я запись принята, новый UUID запрещён даже после удаления.
        var created = await storage.ApplyAsync(owner, boundary, cancellationToken);
        var next = TrainingTestData.Weight();
        var limit = await Assert.ThrowsAsync<TrainingException>(() => storage.ApplyAsync(owner, next, cancellationToken));
        Assert.Equal("training_limit", limit.Code);
        var deleted = await storage.ApplyAsync(owner, boundary with { BaseRevision = created.Revision, Deleted = true, Value = null }, cancellationToken);
        Assert.Equal("training_limit", (await Assert.ThrowsAsync<TrainingException>(() => storage.ApplyAsync(owner, next, cancellationToken))).Code);
        // Act / Assert: существующий UUID можно восстановить, не увеличивая число metadata.
        var restored = await storage.ApplyAsync(owner, boundary with { BaseRevision = deleted.Revision }, cancellationToken);
        Assert.False(restored.Deleted);
        Assert.Equal(100000, await database.TrainingRecords.CountAsync(cancellationToken));
        Assert.Single(await database.BodyWeights.ToListAsync(cancellationToken));
    }
}
