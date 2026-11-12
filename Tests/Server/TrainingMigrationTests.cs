using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет настоящую схему, перенос архивов, блокировки и каскады на одноразовом PostgreSQL.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class TrainingMigrationTests
{
    [Fact]
    public async Task MigratesLatestSnapshotOncePreservingOriginalArchivesAndAllFieldsAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var ct = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(ct);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options;
        await using var database = new BackupDbContext(options);
        await database.GetService<IMigrator>().MigrateAsync("20261111184926_UpdateArchiveFormatIdentifier", ct);
        var owner = Guid.NewGuid().ToString();
        var values = TrainingFixture.Mutations();
        var old = values[0] with { Id = Guid.NewGuid() };
        var oldValue = JsonNode.Parse(old.Value!.Value.GetRawText())!.AsObject();
        oldValue["id"] = old.Id;
        old = old with { Value = JsonSerializer.SerializeToElement(oldValue) };
        var previous = Backup(owner, TrainingFixture.Archive([old]), 100);
        var latest = Backup(owner, TrainingFixture.Archive(values), 200);
        database.Backups.AddRange(previous, latest);
        await database.SaveChangesAsync(ct);

        await database.Database.MigrateAsync(ct);
        var storage = new TrainingStorage(database);
        await storage.ImportLatestBackupsAsync(ct);
        var page = await storage.ChangesAsync(owner, 0, 100, ct);
        var expected = values.Where(x => x.Kind != TrainingKinds.HeartRate).ToList();
        Assert.Equal(expected.Count, page.Changes.Count);
        foreach (var value in expected)
        {
            var actual = Assert.Single(page.Changes, x => x.Kind == value.Kind && x.Id == value.Id);
            Assert.True(JsonElement.DeepEquals(TrainingValidation.Canonical(value.Kind, value.Id, value.Value!.Value), actual.Value!.Value));
        }
        Assert.DoesNotContain(page.Changes, x => x.Id == old.Id);
        Assert.Equal(latest.Id, (await database.TrainingOwners.SingleAsync(ct)).ImportedBackupId);
        Assert.Equal(2, await database.Backups.CountAsync(ct));
        Assert.Equal(previous.Payload, (await database.Backups.AsNoTracking().SingleAsync(x => x.Id == previous.Id, ct)).Payload);
        Assert.Equal(latest.Payload, (await database.Backups.AsNoTracking().SingleAsync(x => x.Id == latest.Id, ct)).Payload);
        Assert.False(database.Database.HasPendingModelChanges());
        Assert.Equal(3, (await database.Database.GetAppliedMigrationsAsync(ct)).Count());

        var first = page.Changes.First(x => x.Kind == TrainingKinds.Workout);
        var editedValue = JsonNode.Parse(first.Value!.Value.GetRawText())!.AsObject();
        editedValue["notes"] = "Изменено после переноса";
        var edited = await storage.ApplyAsync(owner, new TrainingMutation
        { Kind = first.Kind, Id = first.Id, BaseRevision = first.Revision, Deleted = false, Value = JsonSerializer.SerializeToElement(editedValue) }, ct);
        await storage.ImportLatestBackupsAsync(ct);
        var repeated = await storage.ChangesAsync(owner, page.Cursor, 100, ct);
        Assert.Single(repeated.Changes);
        Assert.Equal(edited.Revision, repeated.Changes[0].Revision);
        Assert.Equal("Изменено после переноса", repeated.Changes[0].Value!.Value.GetProperty("notes").GetString());
    }

    [Fact]
    public async Task InvalidTemplateRollsBackPreviouslyImportedWorkoutsWithoutChangingArchiveAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var ct = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(ct);
        await using var database = new BackupDbContext(new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options);
        await database.Database.MigrateAsync(ct);
        var owner = Guid.NewGuid().ToString();
        var values = TrainingFixture.Mutations();
        var index = values.FindIndex(x => x.Kind == TrainingKinds.Template);
        var invalid = JsonNode.Parse(values[index].Value!.Value.GetRawText())!.AsObject();
        invalid["name"] = "";
        values[index] = values[index] with { Value = JsonSerializer.SerializeToElement(invalid) };
        var backup = Backup(owner, TrainingFixture.Archive(values), 100);
        database.Backups.Add(backup);
        await database.SaveChangesAsync(ct);

        var error = await Assert.ThrowsAsync<InvalidOperationException>(() => new TrainingStorage(database).ImportLatestBackupsAsync(ct));

        Assert.DoesNotContain("Личная заметка", error.ToString());
        Assert.Empty(await database.Workouts.ToListAsync(ct));
        Assert.Empty(await database.Exercises.ToListAsync(ct));
        Assert.Empty(await database.TrainingRecords.ToListAsync(ct));
        Assert.Empty(await database.TrainingOwners.ToListAsync(ct));
        var preserved = await database.Backups.AsNoTracking().SingleAsync(ct);
        Assert.Equal(backup.Payload, preserved.Payload);
        Assert.Equal(backup.Sha256, preserved.Sha256);
    }

    [Fact]
    public async Task ConcurrentDeviceUpdatesAcceptOneVersionAndReturnConflictToTheOtherAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var ct = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(ct);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options;
        var owner = Guid.NewGuid().ToString();
        var initial = TrainingFixture.Mutations()[0];
        TrainingChange created;
        await using (var database = new BackupDbContext(options))
        {
            await database.Database.MigrateAsync(ct);
            created = await new TrainingStorage(database).ApplyAsync(owner, initial, ct);
        }
        async Task<bool> Update(string note)
        {
            await using var database = new BackupDbContext(options);
            var value = JsonNode.Parse(initial.Value!.Value.GetRawText())!.AsObject();
            value["notes"] = note;
            try
            {
                await new TrainingStorage(database).ApplyAsync(owner,
                    initial with { BaseRevision = created.Revision, Value = JsonSerializer.SerializeToElement(value) }, ct);
                return true;
            }
            catch (TrainingException error)
            {
                Assert.Equal("training_conflict", error.Code);
                Assert.Equal(409, error.Status);
                Assert.NotNull(error.Current);
                Assert.Equal(created.Revision + 1, error.Current.Revision);
                return false;
            }
        }
        var results = await Task.WhenAll(Update("Устройство A"), Update("Устройство B"));
        Assert.Single(results, x => x);
        await using var verification = new BackupDbContext(options);
        Assert.Equal(created.Revision + 1, (await verification.TrainingOwners.SingleAsync(ct)).Revision);
        Assert.Single(await verification.Workouts.ToListAsync(ct));
    }

    [Fact]
    public async Task AccountCleanupRacingWithTrainingUploadCannotLeaveAnyUserDataAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var ct = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(ct);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options;
        var owner = Guid.NewGuid().ToString();
        await using (var setup = new BackupDbContext(options)) await setup.Database.MigrateAsync(ct);
        async Task Upload()
        {
            await using var database = new BackupDbContext(options);
            try { await new TrainingStorage(database).ApplyBatchAsync(owner, TrainingFixture.Mutations(), ct); }
            catch (TrainingException error) { Assert.Equal("account_deleted", error.Code); }
        }
        async Task Delete()
        {
            await using var database = new BackupDbContext(options);
            await new BackupStorage(database, TimeProvider.System).DeleteAccount(owner, ct);
        }
        await Task.WhenAll(Upload(), Delete());
        await using var verification = new BackupDbContext(options);
        Assert.Single(await verification.DeletedAccounts.ToListAsync(ct));
        Assert.Empty(await verification.TrainingOwners.ToListAsync(ct));
        Assert.Empty(await verification.TrainingRecords.ToListAsync(ct));
        Assert.Empty(await verification.Workouts.ToListAsync(ct));
        Assert.Empty(await verification.Templates.ToListAsync(ct));
        Assert.Empty(await verification.HeartRateRecordings.ToListAsync(ct));
        Assert.Empty(await verification.Set<TrainingHeartRateReading>().ToListAsync(ct));
        Assert.Empty(await verification.BodyWeights.ToListAsync(ct));
    }

    private static BackupRecord Backup(string owner, byte[] payload, long createdAt) => new()
    {
        Id = Guid.NewGuid(),
        OwnerId = owner,
        Payload = payload,
        CreatedAtMilliseconds = createdAt,
        ArchiveVersion = 4,
        Size = payload.Length,
        Sha256 = Convert.ToHexStringLower(SHA256.HashData(payload))
    };
}
