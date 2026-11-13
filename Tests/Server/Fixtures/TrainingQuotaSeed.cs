using System.Security.Cryptography;
using System.Text;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using NpgsqlTypes;

namespace FitLife.Server.Tests;

/// <summary>Быстро заполняет только одноразовую БД полноценными синтетическими графами и точными canonical hashes.</summary>
internal static class TrainingQuotaSeed
{
    /// <summary>COPY избегает тысяч HTTP-запросов при подготовке; сами границы проверяются обычным TrainingStorage.</summary>
    internal static async Task ActiveAsync(BackupDbContext database, string owner, string kind, int count, CancellationToken cancellationToken)
    {
        var values = Enumerable.Range(0, count).Select(_ => Value(kind)).ToArray();
        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        database.TrainingOwners.Add(new TrainingOwner { OwnerId = owner, Revision = count });
        await database.SaveChangesAsync(cancellationToken);
        var connection = (NpgsqlConnection)database.Database.GetDbConnection();
        await using (var writer = await connection.BeginBinaryImportAsync(
            "COPY \"TrainingRecords\" (\"OwnerId\",\"Kind\",\"Id\",\"Revision\",\"Deleted\",\"Hash\") FROM STDIN (FORMAT BINARY)", cancellationToken))
        {
            for (var index = 0; index < values.Length; index++)
            {
                var value = values[index];
                var canonical = TrainingValidation.Canonical(kind, value.Id, value.Value!.Value);
                var hash = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(canonical.GetRawText())));
                await MetadataAsync(writer, owner, kind, value.Id, index + 1, false, hash, cancellationToken);
            }
            await writer.CompleteAsync(cancellationToken);
        }
        switch (kind)
        {
            case TrainingKinds.BodyWeight:
                await using (var writer = await connection.BeginBinaryImportAsync(
                    "COPY \"BodyWeights\" (\"OwnerId\",\"Kind\",\"Id\",\"MeasuredAt\",\"WeightKG\") FROM STDIN (FORMAT BINARY)", cancellationToken))
                {
                    foreach (var value in values)
                    {
                        await writer.StartRowAsync(cancellationToken);
                        await writer.WriteAsync(owner, NpgsqlDbType.Varchar, cancellationToken);
                        await writer.WriteAsync(kind, NpgsqlDbType.Varchar, cancellationToken);
                        await writer.WriteAsync(value.Id, NpgsqlDbType.Uuid, cancellationToken);
                        await writer.WriteAsync(1700000000.125, NpgsqlDbType.Double, cancellationToken);
                        await writer.WriteAsync(75.25, NpgsqlDbType.Double, cancellationToken);
                    }
                    await writer.CompleteAsync(cancellationToken);
                }
                break;
            case TrainingKinds.Workout:
                await using (var writer = await connection.BeginBinaryImportAsync(
                    "COPY \"Workouts\" (\"OwnerId\",\"Kind\",\"Id\",\"Name\",\"StartedAt\",\"EndedAt\",\"Status\",\"RestSeconds\",\"PausedSeconds\",\"Notes\") FROM STDIN (FORMAT BINARY)", cancellationToken))
                {
                    foreach (var value in values)
                    {
                        await writer.StartRowAsync(cancellationToken);
                        await writer.WriteAsync(owner, NpgsqlDbType.Varchar, cancellationToken);
                        await writer.WriteAsync(kind, NpgsqlDbType.Varchar, cancellationToken);
                        await writer.WriteAsync(value.Id, NpgsqlDbType.Uuid, cancellationToken);
                        await writer.WriteAsync("Quota", NpgsqlDbType.Text, cancellationToken);
                        await writer.WriteAsync(0.0, NpgsqlDbType.Double, cancellationToken);
                        await writer.WriteAsync(1.0, NpgsqlDbType.Double, cancellationToken);
                        await writer.WriteAsync("cancelled", NpgsqlDbType.Text, cancellationToken);
                        await writer.WriteAsync(0, NpgsqlDbType.Integer, cancellationToken);
                        await writer.WriteAsync(0.0, NpgsqlDbType.Double, cancellationToken);
                        await writer.WriteAsync("", NpgsqlDbType.Text, cancellationToken);
                    }
                    await writer.CompleteAsync(cancellationToken);
                }
                break;
            case TrainingKinds.Template:
                await TemplatesAsync(connection, owner, values, cancellationToken);
                break;
            default: throw new InvalidOperationException("Unsupported quota seed kind.");
        }
        await transaction.CommitAsync(cancellationToken);
        database.ChangeTracker.Clear();
    }

    /// <summary>Сохраняет допустимые tombstones без графов для проверки общего предела метаданных.</summary>
    internal static async Task TombstonesAsync(BackupDbContext database, string owner, int count, CancellationToken cancellationToken)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        database.TrainingOwners.Add(new TrainingOwner { OwnerId = owner, Revision = count });
        await database.SaveChangesAsync(cancellationToken);
        var connection = (NpgsqlConnection)database.Database.GetDbConnection();
        await using (var writer = await connection.BeginBinaryImportAsync(
            "COPY \"TrainingRecords\" (\"OwnerId\",\"Kind\",\"Id\",\"Revision\",\"Deleted\",\"Hash\") FROM STDIN (FORMAT BINARY)", cancellationToken))
        {
            for (var index = 1; index <= count; index++)
                await MetadataAsync(writer, owner, TrainingKinds.Workout, Guid.NewGuid(), index, true, "", cancellationToken);
            await writer.CompleteAsync(cancellationToken);
        }
        await transaction.CommitAsync(cancellationToken);
        database.ChangeTracker.Clear();
    }

    /// <summary>Все строки используют те же типы и допустимые значения, что обычный wire контракт.</summary>
    private static TrainingMutation Value(string kind)
    {
        if (kind == TrainingKinds.BodyWeight) return TrainingTestData.Weight();
        var id = Guid.NewGuid();
        var value = kind == TrainingKinds.Workout
            ? TrainingJson.Element(new WorkoutData
            {
                Id = id,
                Name = "Quota",
                StartedAt = 0,
                EndedAt = 1,
                Status = "cancelled",
                Exercises = [],
                RestSeconds = 0,
                Pauses = [],
                PausedSeconds = 0,
                Notes = ""
            })
            : TrainingJson.Element(new TemplateData
            {
                Id = id,
                Name = "Quota",
                RestSeconds = 0,
                MuscleGroups = [],
                Muscles = [],
                MuscleRegions = [],
                PreferredWeekdays = [],
                Variations = [],
                Exercises = [new TemplateExerciseData
                {
                    Id = Guid.NewGuid(), Exercise = new ExerciseData { Id = Guid.NewGuid(), Name = "Quota exercise", Muscle = "chest", Instructions = "" },
                    SetCount = 1, Repetitions = 8, WeightKG = 0
                }]
            });
        return new TrainingMutation { Kind = kind, Id = id, BaseRevision = 0, Deleted = false, Value = value };
    }

    /// <summary>Пишет корни и единственное равномерное упражнение каждого синтетического плана.</summary>
    private static async Task TemplatesAsync(NpgsqlConnection connection, string owner, TrainingMutation[] values, CancellationToken cancellationToken)
    {
        await using (var writer = await connection.BeginBinaryImportAsync(
            "COPY \"Templates\" (\"OwnerId\",\"Kind\",\"Id\",\"Name\",\"RestSeconds\",\"MuscleGroupsJson\",\"MusclesJson\",\"MuscleRegionsJson\",\"PreferredWeekdaysJson\") FROM STDIN (FORMAT BINARY)", cancellationToken))
        {
            foreach (var value in values)
            {
                await writer.StartRowAsync(cancellationToken);
                await writer.WriteAsync(owner, NpgsqlDbType.Varchar, cancellationToken);
                await writer.WriteAsync(TrainingKinds.Template, NpgsqlDbType.Varchar, cancellationToken);
                await writer.WriteAsync(value.Id, NpgsqlDbType.Uuid, cancellationToken);
                await writer.WriteAsync("Quota", NpgsqlDbType.Text, cancellationToken);
                await writer.WriteAsync(0, NpgsqlDbType.Integer, cancellationToken);
                for (var field = 0; field < 4; field++) await writer.WriteAsync("[]", NpgsqlDbType.Text, cancellationToken);
            }
            await writer.CompleteAsync(cancellationToken);
        }
        await using (var writer = await connection.BeginBinaryImportAsync(
            "COPY \"Exercises\" (\"OwnerId\",\"Kind\",\"AggregateId\",\"VariationIndex\",\"Position\",\"Id\",\"ExerciseId\",\"Name\",\"Muscle\",\"Instructions\",\"SetCount\",\"Repetitions\",\"WeightKG\",\"HasPlannedSets\") FROM STDIN (FORMAT BINARY)", cancellationToken))
        {
            foreach (var value in values)
            {
                var row = value.Value!.Value.GetProperty("exercises")[0];
                await writer.StartRowAsync(cancellationToken);
                await writer.WriteAsync(owner, NpgsqlDbType.Varchar, cancellationToken);
                await writer.WriteAsync(TrainingKinds.Template, NpgsqlDbType.Varchar, cancellationToken);
                await writer.WriteAsync(value.Id, NpgsqlDbType.Uuid, cancellationToken);
                await writer.WriteAsync(0, NpgsqlDbType.Integer, cancellationToken);
                await writer.WriteAsync(0, NpgsqlDbType.Integer, cancellationToken);
                await writer.WriteAsync(row.GetProperty("id").GetGuid(), NpgsqlDbType.Uuid, cancellationToken);
                await writer.WriteAsync(row.GetProperty("exercise").GetProperty("id").GetGuid(), NpgsqlDbType.Uuid, cancellationToken);
                await writer.WriteAsync("Quota exercise", NpgsqlDbType.Text, cancellationToken);
                await writer.WriteAsync("chest", NpgsqlDbType.Text, cancellationToken);
                await writer.WriteAsync("", NpgsqlDbType.Text, cancellationToken);
                await writer.WriteAsync(1, NpgsqlDbType.Integer, cancellationToken);
                await writer.WriteAsync(8, NpgsqlDbType.Integer, cancellationToken);
                await writer.WriteAsync(0.0, NpgsqlDbType.Double, cancellationToken);
                await writer.WriteAsync(false, NpgsqlDbType.Boolean, cancellationToken);
            }
            await writer.CompleteAsync(cancellationToken);
        }
    }

    /// <summary>Сохраняет монотонную версию и точный хеш живой записи либо пустой хеш tombstone.</summary>
    private static async Task MetadataAsync(NpgsqlBinaryImporter writer, string owner, string kind, Guid id, long revision, bool deleted, string hash, CancellationToken cancellationToken)
    {
        await writer.StartRowAsync(cancellationToken);
        await writer.WriteAsync(owner, NpgsqlDbType.Varchar, cancellationToken);
        await writer.WriteAsync(kind, NpgsqlDbType.Varchar, cancellationToken);
        await writer.WriteAsync(id, NpgsqlDbType.Uuid, cancellationToken);
        await writer.WriteAsync(revision, NpgsqlDbType.Bigint, cancellationToken);
        await writer.WriteAsync(deleted, NpgsqlDbType.Boolean, cancellationToken);
        await writer.WriteAsync(hash, NpgsqlDbType.Varchar, cancellationToken);
    }
}
