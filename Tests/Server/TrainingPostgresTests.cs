using System.Data.Common;
using System.Text.Json;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Npgsql;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет настоящие каскады, снимки чтения и конкуренцию графов на отдельных PostgreSQL-соединениях.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class TrainingPostgresTests
{
    /// <summary>Полная замена и удаление не оставляют прежние подходы, вариации, паузы и измерения.</summary>
    [Theory]
    [InlineData(TrainingKinds.Workout)]
    [InlineData(TrainingKinds.Template)]
    [InlineData(TrainingKinds.BodyWeight)]
    [InlineData(TrainingKinds.HeartRate)]
    public async Task ReplacingAndDeletingGraphsDoesNotLeaveStaleChildrenAsync(string kind)
    {
        // Arrange: сохраняем исходный полный граф через настоящее хранилище PostgreSQL.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var database = Context(fixture);
        await database.Database.MigrateAsync(cancellationToken);
        var owner = Guid.NewGuid().ToString();
        var storage = new TrainingStorage(database);
        var original = TrainingFixture.Mutations();
        var seeded = await storage.ApplyBatchAsync(owner, original, cancellationToken);
        var mutation = original.First(item => item.Kind == kind);
        var version = seeded.Single(item => item.Kind == kind && item.Id == mutation.Id);
        var replacement = TrainingTransactionTests.Replacement(mutation with { BaseRevision = version.Revision });

        // Act: заменяем целый агрегат, включая его вложенные строки.
        var saved = await storage.ApplyAsync(owner, replacement, cancellationToken);

        // Assert: новый граф точен, соседние агрегаты сохранены, прежних детей больше нет.
        var page = await storage.ChangesAsync(owner, 0, 100, cancellationToken);
        var current = page.Changes.Single(item => item.Kind == kind && item.Id == mutation.Id);
        Assert.True(JsonElement.DeepEquals(TrainingValidation.Canonical(kind, mutation.Id, replacement.Value!.Value), current.Value!.Value));
        foreach (var expected in seeded.Where(item => item.Kind != kind || item.Id != mutation.Id))
            Assert.True(JsonElement.DeepEquals(expected.Value!.Value, page.Changes.Single(item => item.Kind == expected.Kind && item.Id == expected.Id).Value!.Value));
        var rows = database.Exercises.Where(item => item.OwnerId == owner && item.Kind == kind && item.AggregateId == mutation.Id);
        Assert.Equal(kind is TrainingKinds.Workout or TrainingKinds.Template ? 1 : 0, await rows.CountAsync(cancellationToken));
        Assert.Equal(kind == TrainingKinds.Workout ? 1 : 0, await database.Set<TrainingSet>().CountAsync(item => item.OwnerId == owner && item.Kind == kind && item.AggregateId == mutation.Id, cancellationToken));
        Assert.Empty(await database.Set<TrainingDropStage>().Where(item => item.OwnerId == owner && item.Kind == kind && item.AggregateId == mutation.Id).ToListAsync(cancellationToken));
        if (kind == TrainingKinds.Template)
            Assert.Empty(await database.Set<TrainingVariation>().Where(item => item.OwnerId == owner && item.TemplateId == mutation.Id).ToListAsync(cancellationToken));
        if (kind == TrainingKinds.Workout)
            Assert.Empty(await database.Set<TrainingPause>().Where(item => item.OwnerId == owner && item.WorkoutId == mutation.Id).ToListAsync(cancellationToken));
        if (kind == TrainingKinds.HeartRate)
            Assert.Single(await database.Set<TrainingHeartRateReading>().Where(item => item.OwnerId == owner && item.WorkoutId == mutation.Id).ToListAsync(cancellationToken));

        // Act / Assert: удаление оставляет tombstone и каскадно убирает связанные измерения.
        await storage.ApplyAsync(owner, replacement with { BaseRevision = saved.Revision, Deleted = true, Value = null }, cancellationToken);
        var deleted = await storage.ChangesAsync(owner, 0, 100, cancellationToken);
        foreach (var expected in seeded)
        {
            var actual = deleted.Changes.Single(item => item.Kind == expected.Kind && item.Id == expected.Id);
            if (expected.Kind == kind && expected.Id == mutation.Id || kind == TrainingKinds.Workout && expected.Kind == TrainingKinds.HeartRate && expected.Id == mutation.Id)
            {
                Assert.True(actual.Deleted);
                Assert.Null(actual.Value);
            }
            else Assert.True(JsonElement.DeepEquals(expected.Value!.Value, actual.Value!.Value));
        }
        Assert.Empty(await rows.ToListAsync(cancellationToken));
        Assert.Empty(await database.Set<TrainingSet>().Where(item => item.OwnerId == owner && item.Kind == kind && item.AggregateId == mutation.Id).ToListAsync(cancellationToken));
        if (kind is TrainingKinds.Workout or TrainingKinds.HeartRate)
            Assert.Empty(await database.Set<TrainingHeartRateReading>().Where(item => item.OwnerId == owner && item.WorkoutId == mutation.Id).ToListAsync(cancellationToken));
    }

    /// <summary>Два новых агрегата одного владельца оба принимаются и получают разные последовательные версии.</summary>
    [Fact]
    public async Task ConcurrentDifferentRecordsPreserveBothValuesAndRevisionSequenceAsync()
    {
        // Arrange: два запроса используют отдельные соединения и один owner counter.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using (var setup = Context(fixture)) await setup.Database.MigrateAsync(cancellationToken);
        var owner = Guid.NewGuid().ToString();
        var first = TrainingTestData.Weight();
        var second = TrainingTestData.Weight();
        async Task<TrainingChange> WriteAsync(TrainingMutation mutation)
        {
            await using var database = Context(fixture);
            return await new TrainingStorage(database).ApplyAsync(owner, mutation, cancellationToken);
        }
        // Act: обе записи выполняются одновременно, без общего ChangeTracker.
        var saved = await Task.WhenAll(WriteAsync(first), WriteAsync(second));
        // Assert: блокировка сохраняет обе записи и выдаёт последовательные версии.
        Assert.Equal(new long[] { 1, 2 }, saved.Select(item => item.Revision).Order());
        await using var verification = Context(fixture);
        var page = await new TrainingStorage(verification).ChangesAsync(owner, 0, 100, cancellationToken);
        Assert.Equal(new[] { first.Id, second.Id }.Order(), page.Changes.Select(item => item.Id).Order());
        Assert.Equal(2, page.Cursor);
        Assert.Equal(2, await verification.BodyWeights.CountAsync(cancellationToken));
    }

    /// <summary>Правка между SELECT корня и SELECT детей не смешивает старую версию с новым графом.</summary>
    [Fact]
    public async Task FeedReadsOneConsistentSnapshotDuringConcurrentGraphReplacementAsync()
    {
        // Arrange: фиксируем исходную версию и управляемую остановку чтения между SELECT.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var owner = Guid.NewGuid().ToString();
        var original = TrainingTestData.Mutation(TrainingKinds.Workout);
        TrainingChange initial;
        await using (var setup = Context(fixture))
        {
            await setup.Database.MigrateAsync(cancellationToken);
            initial = await new TrainingStorage(setup).ApplyAsync(owner, original, cancellationToken);
        }
        var gate = new WorkoutReadGate();
        await using var reader = new BackupDbContext(new DbContextOptionsBuilder<BackupDbContext>()
            .UseNpgsql(fixture.ConnectionString)
            .AddInterceptors(gate)
            .Options);
        // Act: после чтения корня другое соединение подтверждает замену всех детей.
        var reading = new TrainingStorage(reader).ChangesAsync(owner, 0, 100, cancellationToken);
        try
        {
            await gate.Entered.Task.WaitAsync(cancellationToken);
            await using var writer = Context(fixture);
            var updated = TrainingTransactionTests.Replacement(original with { BaseRevision = initial.Revision });
            var saved = await new TrainingStorage(writer).ApplyAsync(owner, updated, cancellationToken);
            Assert.True(saved.Revision > initial.Revision);
        }
        finally { gate.Release.TrySetResult(); }
        // Assert: первая страница целиком старая, следующая целиком новая.
        var snapshot = await reading;
        var actual = Assert.Single(snapshot.Changes);
        Assert.Equal(initial.Revision, actual.Revision);
        Assert.True(JsonElement.DeepEquals(initial.Value!.Value, actual.Value!.Value));
        var next = await new TrainingStorage(reader).ChangesAsync(owner, snapshot.Cursor, 100, cancellationToken);
        Assert.True(Assert.Single(next.Changes).Revision > actual.Revision);
        Assert.Single(next.Changes[0].Value!.Value.GetProperty("exercises").EnumerateArray());
    }

    /// <summary>Реальная ошибка PostgreSQL после изменения metadata и удаления пауз откатывает весь прежний граф.</summary>
    [Fact]
    public async Task DatabaseConstraintFailureDuringChildDeletionRollsBackEverythingAsync()
    {
        // Arrange: только в одноразовой БД триггер отклоняет удаление дроп-этапа.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var database = Context(fixture);
        await database.Database.MigrateAsync(cancellationToken);
        var owner = Guid.NewGuid().ToString();
        var storage = new TrainingStorage(database);
        var seeded = await storage.ApplyBatchAsync(owner, TrainingFixture.Mutations(), cancellationToken);
        var original = TrainingTestData.Mutation(TrainingKinds.Workout);
        var initial = seeded.Single(item => item.Kind == original.Kind && item.Id == original.Id);
        var replacement = TrainingTransactionTests.Replacement(original with { BaseRevision = initial.Revision });
        await database.Database.ExecuteSqlRawAsync("""
            CREATE FUNCTION reject_training_drop_delete() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'synthetic training constraint'; END;
            $$;
            CREATE TRIGGER reject_training_drop_delete BEFORE DELETE ON "TrainingDropStage"
            FOR EACH ROW EXECUTE FUNCTION reject_training_drop_delete();
            """, cancellationToken);

        // Act: реальный SQL-отказ наступает после изменения версии и удаления пауз.
        var error = await Assert.ThrowsAsync<PostgresException>(() => storage.ApplyAsync(owner, replacement, cancellationToken));
        // Assert: новый context видит весь прежний граф; повтор после снятия отказа успешен.
        Assert.Equal("23514", error.SqlState);
        await using (var verification = Context(fixture))
        {
            var preserved = await new TrainingStorage(verification).ChangesAsync(owner, 0, 100, cancellationToken);
            Assert.Equal(seeded.Select(item => item.Revision), preserved.Changes.Select(item => item.Revision));
            foreach (var (expected, actual) in seeded.Zip(preserved.Changes))
                Assert.True(JsonElement.DeepEquals(expected.Value!.Value, actual.Value!.Value));
        }
        await database.Database.ExecuteSqlRawAsync("DROP TRIGGER reject_training_drop_delete ON \"TrainingDropStage\"; DROP FUNCTION reject_training_drop_delete();", cancellationToken);
        var retry = await storage.ApplyAsync(owner, replacement, cancellationToken);
        Assert.Equal(seeded[^1].Revision + 1, retry.Revision);
    }

    /// <summary>Создаёт новый контекст, не разделяя ChangeTracker и соединение между конкурентными операциями.</summary>
    private static BackupDbContext Context(PostgresDatabase fixture) => new(new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options);

    /// <summary>Останавливает один SELECT после его выполнения; сигналы не зависят от тайминга и задержек.</summary>
    private sealed class WorkoutReadGate : DbCommandInterceptor
    {
        private int _remaining = 1;
        /// <summary>SELECT корня выполнен, следующие SELECT детей ещё не начались.</summary>
        internal TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        /// <summary>Разрешает продолжить чтение после подтверждённой записи на другом соединении.</summary>
        internal TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        /// <summary>Сохраняет настоящий DbDataReader и передаёт отмену ожиданию сигнала.</summary>
        public override async ValueTask<DbDataReader> ReaderExecutedAsync(DbCommand command, CommandExecutedEventData eventData,
            DbDataReader result, CancellationToken cancellationToken = default)
        {
            if (command.CommandText.Contains("FROM \"Workouts\"", StringComparison.Ordinal) && Interlocked.Exchange(ref _remaining, 0) == 1)
            {
                Entered.TrySetResult();
                await Release.Task.WaitAsync(cancellationToken);
            }
            return result;
        }
    }
}
