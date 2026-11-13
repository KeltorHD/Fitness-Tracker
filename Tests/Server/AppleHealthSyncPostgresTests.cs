using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет реальную health-миграцию, конкурентные повторы и каскад удаления на одноразовом PostgreSQL.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class AppleHealthSyncPostgresTests
{
    /// <summary>Обновление сохраняет существующий архив, создаёт health-таблицы и удаляет только нужного владельца.</summary>
    [Fact]
    public async Task MigrationPreservesExistingDataAndAccountDeletionCascadesHealthAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options;
        await using var database = new BackupDbContext(options);
        await database.GetService<IMigrator>().MigrateAsync("20261112194506_CreateTrainingModel", cancellationToken);
        var owner = Guid.NewGuid().ToString(); var other = Guid.NewGuid().ToString();
        database.Backups.Add(new() { OwnerId = other, Id = Guid.NewGuid(), Size = 3, Payload = [1, 2, 3], Sha256 = "existing-hash", ArchiveVersion = 4 });
        await database.SaveChangesAsync(cancellationToken);
        await database.Database.MigrateAsync(cancellationToken);
        Assert.False(database.Database.HasPendingModelChanges());
        var storage = new HealthSyncStorage(database, TimeProvider.System);
        var point = Point();
        await storage.ApplyAsync(owner, Batch(point), cancellationToken);
        await storage.ApplyAsync(other, Batch(Point()), cancellationToken);
        await new BackupStorage(database, TimeProvider.System).DeleteAccount(owner, cancellationToken);
        database.ChangeTracker.Clear();
        Assert.Single(await database.Set<HealthSyncSample>().ToArrayAsync(cancellationToken));
        Assert.Equal(other, (await database.Set<HealthSyncOwner>().SingleAsync(cancellationToken)).OwnerId);
        Assert.Single(await database.Set<HealthSyncDevice>().ToArrayAsync(cancellationToken));
        var archive = await database.Backups.SingleAsync(cancellationToken);
        Assert.Equal(new byte[] { 1, 2, 3 }, archive.Payload);
        Assert.Equal("existing-hash", archive.Sha256);
        var denied = await Assert.ThrowsAsync<HealthDataException>(() => storage.ApplyAsync(owner, Batch(Point()), cancellationToken));
        Assert.Equal("account_deleted", denied.Code);
    }

    /// <summary>Два одновременных повтора одного пакета имеют один результат; независимые удаления побеждают запоздалые upserts.</summary>
    [Fact]
    public async Task ConcurrentDeliveriesAreSerializedAndDeletionCannotBeResurrectedAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options;
        await using (var seed = new BackupDbContext(options)) await seed.Database.MigrateAsync(cancellationToken);
        var owner = Guid.NewGuid().ToString(); var point = Point(); var batch = Batch(point);
        async Task<HealthSyncAcknowledgement> DeliverAsync(HealthSyncBatch value)
        {
            await using var context = new BackupDbContext(options);
            return await new HealthSyncStorage(context, TimeProvider.System).ApplyAsync(owner, value, cancellationToken);
        }
        var delivered = await Task.WhenAll(DeliverAsync(batch), DeliverAsync(batch));
        Assert.Equal(delivered[0].BatchId, delivered[1].BatchId);
        Assert.Equal(delivered[0].Sequence, delivered[1].Sequence);
        Assert.Equal(delivered[0].Buckets, delivered[1].Buckets);
        await Task.WhenAll(DeliverAsync(Batch(point)), DeliverAsync(Batch(point) with { Quantities = [], DeletedIds = [point.Id] }));
        await using var verification = new BackupDbContext(options);
        var sample = await verification.Set<HealthSyncSample>().SingleAsync(cancellationToken);
        Assert.True(sample.Deleted);
        Assert.Null(sample.Value);
        Assert.Empty(sample.SourceName);
    }

    /// <summary>Создаёт нативную точку без внешней сети или приватных данных.</summary>
    private static HealthQuantity Point() => new(Guid.NewGuid(), "bodyWeight", BackendFactory.BackupTime.AddDays(-1), BackendFactory.BackupTime.AddDays(-1), 70, "source", "Source");
    /// <summary>Первый пакет отдельного устройства одного владельца.</summary>
    private static HealthSyncBatch Batch(HealthQuantity point) => new(Guid.NewGuid(), 1, Guid.NewGuid(), "UTC", DateTimeOffset.UtcNow, [point], [], [], []);
}
