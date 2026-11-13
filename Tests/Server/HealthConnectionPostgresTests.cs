using FitLife.Authentication;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет перенос существующих аккаунтов и распределённую сериализацию OAuth на PostgreSQL.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class HealthConnectionPostgresTests
{
    /// <summary>Миграция не меняет старые credentials, добавляет owner FK; удаление аккаунта удаляет привязку.</summary>
    [Fact]
    public async Task MigrationPreservesAccountsAndCascadesConnectionsAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<AuthDbContext>().UseNpgsql(fixture.ConnectionString).UseOpenIddict().Options;
        await using var database = new AuthDbContext(options);
        var previous = "20261108165641_AddPendingRegistrationExpiryIndex";
        await database.GetService<IMigrator>().MigrateAsync(previous, cancellationToken);
        var owner = Guid.NewGuid().ToString();
        database.Users.Add(new ApplicationUser { Id = owner, UserName = owner, PasswordHash = "existing-password-hash", SecurityStamp = "existing-stamp" });
        await database.SaveChangesAsync(cancellationToken);
        await database.Database.MigrateAsync(cancellationToken);
        Assert.False(database.Database.HasPendingModelChanges());
        database.ChangeTracker.Clear();
        var preserved = await database.Users.SingleAsync(cancellationToken);
        Assert.Equal("existing-password-hash", preserved.PasswordHash);
        Assert.Equal("existing-stamp", preserved.SecurityStamp);
        database.HealthConnections.Add(new HealthConnection { UserId = owner, Provider = XiaomiHealthOAuth.Provider, ProtectedTokens = "encrypted-fixture", UpdatedAt = DateTimeOffset.UtcNow });
        await database.SaveChangesAsync(cancellationToken);
        await database.Users.Where(user => user.Id == owner).ExecuteDeleteAsync(cancellationToken);
        Assert.Empty(await database.HealthConnections.AsNoTracking().ToArrayAsync(cancellationToken));
    }

    /// <summary>Два экземпляра Auth не могут одновременно обновлять одного владельца; отмена ожидания освобождает соединение.</summary>
    [Fact]
    public async Task AdvisoryLocksSerializeOwnersAndReleaseAfterCancellationAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(1));
        await using var fixture = await PostgresDatabase.CreateAsync(deadline.Token);
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:Database"] = fixture.ConnectionString }).Build();
        var first = new HealthConnectionLocks(configuration);
        var second = new HealthConnectionLocks(configuration);
        var owner = Guid.NewGuid().ToString();
        var held = await first.AcquireAsync(owner, deadline.Token);
        try
        {
            using var waiting = CancellationTokenSource.CreateLinkedTokenSource(deadline.Token);
            var pending = second.AcquireAsync(owner, waiting.Token);
            await using var independent = await second.AcquireAsync(Guid.NewGuid().ToString(), deadline.Token);
            Assert.False(pending.IsCompleted);
            await waiting.CancelAsync();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending);
        }
        finally { await held.DisposeAsync(); }
        await using var resumed = await second.AcquireAsync(owner, deadline.Token);
    }
}
