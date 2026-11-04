using FitnessTracker.Backend;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет настоящие PostgreSQL-миграции и конкурирующие операции в изолированных базах.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class PostgresTests
{
    /// <summary>Раздельные базы применяют миграции без расхождений модели; гонка загрузок соблюдает квоту.</summary>
    [Fact]
    public async Task RealMigrationsAndConcurrentQuotaRemainConsistentAsync()
    {
        // Arrange: отдельная БД каждого сервиса, существующие миграции и ограниченный срок теста.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var auth = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var backups = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(backups.ConnectionString).Options;
        await using (var database = new BackupDbContext(options))
        {
            await database.Database.MigrateAsync(cancellationToken);
            Assert.False(database.Database.HasPendingModelChanges());
        }
        await using (var database = new Authentication.AuthDbContext(
            new DbContextOptionsBuilder<Authentication.AuthDbContext>().UseNpgsql(auth.ConnectionString).UseOpenIddict().Options))
        {
            await database.Database.MigrateAsync(cancellationToken);
            Assert.False(database.Database.HasPendingModelChanges());
            Assert.Empty(await database.Users.ToListAsync(cancellationToken));
        }
        var owner = Guid.NewGuid().ToString();
        for (var index = 0; index < BackupStorage.MaximumCopies - 1; index++)
            Assert.Equal(201, await UploadAsync(options, owner, Guid.NewGuid(), cancellationToken));

        // Act: четыре независимых DbContext одновременно занимают последний слот.
        var results = await Task.WhenAll(Enumerable.Range(0, 4)
            .Select(_ => UploadAsync(options, owner, Guid.NewGuid(), cancellationToken)));

        // Assert: только одна загрузка создана; квота не превышена и существующие копии не вытеснены.
        Assert.Single(results, value => value == 201);
        Assert.Equal(3, results.Count(value => value == 409));
        await using var verification = new BackupDbContext(options);
        Assert.Equal(BackupStorage.MaximumCopies, await verification.Backups.CountAsync(cancellationToken));
    }

    /// <summary>При любом порядке гонки удаления и PUT данные владельца удалены, чужая копия сохранена.</summary>
    [Fact]
    public async Task AccountDeletionSerializesWithConcurrentUploadAsync()
    {
        // Arrange: пользователь с копией и независимый пользователь, которого нельзя затронуть.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options;
        await using (var database = new BackupDbContext(options)) await database.Database.MigrateAsync(cancellationToken);
        var owner = Guid.NewGuid().ToString();
        var other = Guid.NewGuid().ToString();
        Assert.Equal(201, await UploadAsync(options, owner, Guid.NewGuid(), cancellationToken));
        Assert.Equal(201, await UploadAsync(options, other, Guid.NewGuid(), cancellationToken));

        // Act: удаление и загрузка используют разные соединения и общий per-user advisory lock.
        var uploading = UploadAsync(options, owner, Guid.NewGuid(), cancellationToken);
        var deleting = DeleteOwnerAsync(options, owner, cancellationToken);
        await Task.WhenAll(uploading, deleting);

        // Assert: PUT либо успел до удаления, либо отклонён; итоговые данные от порядка не зависят.
        Assert.Contains(await uploading, new[] { 201, 403 });
        await using (var verification = new BackupDbContext(options))
        {
            Assert.False(await verification.Backups.AnyAsync(item => item.OwnerId == owner, cancellationToken));
            Assert.Single(await verification.Backups.Where(item => item.OwnerId == other).ToListAsync(cancellationToken));
            Assert.True(await verification.DeletedAccounts.AnyAsync(item => item.Id == owner, cancellationToken));
        }
        await DeleteOwnerAsync(options, owner, cancellationToken);
        Assert.Equal(403, await UploadAsync(options, owner, Guid.NewGuid(), cancellationToken));
    }

    /// <summary>Возвращает ожидаемые бизнес-отказы; инфраструктурные ошибки не скрываются.</summary>
    private static async Task<int> UploadAsync(DbContextOptions<BackupDbContext> options, string owner, Guid id,
        CancellationToken cancellationToken)
    {
        await using var database = new BackupDbContext(options);
        try
        {
            await new BackupStorage(database, new FrozenTimeProvider(BackendFactory.BackupTime)).Put(owner, id,
                """{"format":"com.fitnesstracker.archive","version":4,"exportedAt":1700000000,"workouts":[],"templates":[],"bodyWeights":[]}"""u8.ToArray(),
                cancellationToken);
            return 201;
        }
        catch (BackupException error) { return error.Status; }
    }

    /// <summary>Удаляет данные владельца на отдельном соединении, как независимый запрос сервиса.</summary>
    private static async Task DeleteOwnerAsync(DbContextOptions<BackupDbContext> options, string owner,
        CancellationToken cancellationToken)
    {
        await using var database = new BackupDbContext(options);
        await new BackupStorage(database, TimeProvider.System).DeleteAccount(owner, cancellationToken);
    }
}
