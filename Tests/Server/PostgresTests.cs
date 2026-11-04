using System.Text;
using FitnessTracker.Backend;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Xunit;

namespace FitnessTracker.Server.Tests;

public sealed class PostgresTests
{
    [Fact, Trait("Category", "PostgreSQL")]
    public async Task RealMigrationsAndConcurrentQuotaAndDeletionRemainConsistent()
    {
        var connectionString = Environment.GetEnvironmentVariable("FITNESS_TRACKER_TEST_POSTGRES")
            ?? throw new InvalidOperationException("Set FITNESS_TRACKER_TEST_POSTGRES to a disposable PostgreSQL instance.");
        var name = "fitnesstracker_tests_" + Guid.NewGuid().ToString("N");
        await using var admin = new NpgsqlConnection(connectionString);
        await admin.OpenAsync();
        await using (var create = new NpgsqlCommand($"CREATE DATABASE {name}", admin)) await create.ExecuteNonQueryAsync();
        var isolated = new NpgsqlConnectionStringBuilder(connectionString) { Database = name, Pooling = false }.ConnectionString;
        try
        {
            var backupOptions = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(isolated).Options;
            await using (var database = new BackupDbContext(backupOptions))
            {
                await database.Database.MigrateAsync();
                Assert.False(database.Database.HasPendingModelChanges());
            }
            await using (var database = new Authentication.AuthDbContext(
                new DbContextOptionsBuilder<Authentication.AuthDbContext>().UseNpgsql(isolated).UseOpenIddict().Options))
            {
                await database.Database.MigrateAsync();
                Assert.False(database.Database.HasPendingModelChanges());
                Assert.Equal(0, await database.Users.CountAsync());
            }
            var owner = Guid.NewGuid().ToString();
            var archive = Encoding.UTF8.GetBytes(
                """{"format":"com.fitnesstracker.archive","version":4,"exportedAt":1700000000,"workouts":[],"templates":[],"bodyWeights":[]}""");
            async Task<int> Upload()
            {
                await using var database = new BackupDbContext(backupOptions);
                try
                {
                    await new BackupStorage(database, TimeProvider.System).Put(owner, Guid.NewGuid(), archive, default);
                    return 201;
                }
                catch (BackupException error) { return error.Status; }
            }
            for (var index = 0; index < BackupStorage.MaximumCopies - 1; index++) Assert.Equal(201, await Upload());
            var results = await Task.WhenAll(Upload(), Upload(), Upload(), Upload());
            Assert.Single(results, value => value == 201);
            Assert.Equal(3, results.Count(value => value == 409));
            await using (var database = new BackupDbContext(backupOptions))
            {
                Assert.Equal(BackupStorage.MaximumCopies, await database.Backups.CountAsync());
                await new BackupStorage(database, TimeProvider.System).DeleteAccount(owner, default);
                Assert.Equal(0, await database.Backups.CountAsync());
            }
            Assert.Equal(403, await Upload());
        }
        finally
        {
            await using var drop = new NpgsqlCommand($"DROP DATABASE {name} WITH (FORCE)", admin);
            await drop.ExecuteNonQueryAsync();
        }
    }
}
