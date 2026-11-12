using Microsoft.EntityFrameworkCore;

namespace FitLife.Backend;

public sealed class TrainingOwner
{
    public string OwnerId { get; set; } = "";
    public long Revision { get; set; }
    public Guid? ImportedBackupId { get; set; }
}

public sealed class TrainingRecordMetadata
{
    public string OwnerId { get; set; } = "";
    public string Kind { get; set; } = "";
    public Guid Id { get; set; }
    public long Revision { get; set; }
    public bool Deleted { get; set; }
    public string Hash { get; set; } = "";
}

public sealed class TrainingWorkout
{
    public string OwnerId { get; set; } = "";
    public string Kind { get; set; } = TrainingKinds.Workout;
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    public double StartedAt { get; set; }
    public double? EndedAt { get; set; }
    public string Status { get; set; } = "";
    public int RestSeconds { get; set; }
    public double? RestEndsAt { get; set; }
    public double? PausedAt { get; set; }
    public double PausedSeconds { get; set; }
    public string Notes { get; set; } = "";
    public double? BodyWeightKG { get; set; }
    public bool? DurationIsKnown { get; set; }
    public List<TrainingPause> Pauses { get; set; } = [];
}

public sealed class TrainingPause
{
    public string OwnerId { get; set; } = "";
    public Guid WorkoutId { get; set; }
    public int Position { get; set; }
    public double StartedAt { get; set; }
    public double EndedAt { get; set; }
}

/// <summary>Снимок упражнения сохраняет историческое имя независимо от изменений каталога.</summary>
public sealed class TrainingExercise
{
    public string OwnerId { get; set; } = "";
    public string Kind { get; set; } = "";
    public Guid AggregateId { get; set; }
    public int VariationIndex { get; set; }
    public int Position { get; set; }
    public Guid Id { get; set; }
    public Guid ExerciseId { get; set; }
    public string Name { get; set; } = "";
    public string Muscle { get; set; } = "";
    public string Instructions { get; set; } = "";
    public Guid? SupersetID { get; set; }
    public int? SetCount { get; set; }
    public int? Repetitions { get; set; }
    public double? WeightKG { get; set; }
    public int? LoadMultiplier { get; set; }
    public bool HasPlannedSets { get; set; }
    public List<TrainingSet> Sets { get; set; } = [];
}

public sealed class TrainingSet
{
    public string OwnerId { get; set; } = "";
    public string Kind { get; set; } = "";
    public Guid AggregateId { get; set; }
    public int VariationIndex { get; set; }
    public int ExercisePosition { get; set; }
    public int Position { get; set; }
    public Guid Id { get; set; }
    public int Repetitions { get; set; }
    public double WeightKG { get; set; }
    public bool IsWarmup { get; set; }
    public double? CompletedAt { get; set; }
    public int? LoadMultiplier { get; set; }
    public string? Note { get; set; }
    public bool HasDropStages { get; set; }
    public List<TrainingDropStage> DropStages { get; set; } = [];
}

public sealed class TrainingDropStage
{
    public string OwnerId { get; set; } = "";
    public string Kind { get; set; } = "";
    public Guid AggregateId { get; set; }
    public int VariationIndex { get; set; }
    public int ExercisePosition { get; set; }
    public int SetPosition { get; set; }
    public int Position { get; set; }
    public Guid Id { get; set; }
    public int Repetitions { get; set; }
    public double WeightKG { get; set; }
    public double? CompletedAt { get; set; }
}

public sealed class TrainingTemplate
{
    public string OwnerId { get; set; } = "";
    public string Kind { get; set; } = TrainingKinds.Template;
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    public int RestSeconds { get; set; }
    public string? BaseVariationName { get; set; }
    public string MuscleGroupsJson { get; set; } = "[]";
    public string MusclesJson { get; set; } = "[]";
    public string MuscleRegionsJson { get; set; } = "[]";
    public string PreferredWeekdaysJson { get; set; } = "[]";
    public List<TrainingVariation> Variations { get; set; } = [];
}

public sealed class TrainingVariation
{
    public string OwnerId { get; set; } = "";
    public Guid TemplateId { get; set; }
    public int Position { get; set; }
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
}

public sealed class TrainingBodyWeight
{
    public string OwnerId { get; set; } = "";
    public string Kind { get; set; } = TrainingKinds.BodyWeight;
    public Guid Id { get; set; }
    public double MeasuredAt { get; set; }
    public double WeightKG { get; set; }
    // Замер может пережить удаление тренировки: это часть действующего контракта Core.
    public Guid? WorkoutID { get; set; }
}

public sealed class TrainingHeartRate
{
    public string OwnerId { get; set; } = "";
    public string Kind { get; set; } = TrainingKinds.HeartRate;
    public Guid Id { get; set; }
    public int SchemaVersion { get; set; }
    public string Mode { get; set; } = "";
    public string? Origin { get; set; }
    public List<TrainingHeartRateReading> Readings { get; set; } = [];
}

public sealed class TrainingHeartRateReading
{
    public string OwnerId { get; set; } = "";
    public Guid WorkoutId { get; set; }
    public int Position { get; set; }
    public double Date { get; set; }
    public double BeatsPerMinute { get; set; }
}

internal static class TrainingModel
{
    internal static void Configure(ModelBuilder builder)
    {
        builder.Entity<TrainingOwner>().HasKey(x => x.OwnerId);
        builder.Entity<TrainingRecordMetadata>().HasKey(x => new { x.OwnerId, x.Kind, x.Id });
        builder.Entity<TrainingRecordMetadata>().HasIndex(x => new { x.OwnerId, x.Revision }).IsUnique();
        builder.Entity<TrainingRecordMetadata>().Property(x => x.Hash).HasMaxLength(64);
        builder.Entity<TrainingRecordMetadata>().HasOne<TrainingOwner>().WithMany()
            .HasForeignKey(x => x.OwnerId).OnDelete(DeleteBehavior.Cascade);
        foreach (var type in new[] { typeof(TrainingWorkout), typeof(TrainingTemplate), typeof(TrainingBodyWeight), typeof(TrainingHeartRate) })
        {
            builder.Entity(type).HasKey("OwnerId", "Id");
            builder.Entity(type).HasOne(typeof(TrainingRecordMetadata)).WithMany()
                .HasForeignKey("OwnerId", "Kind", "Id").OnDelete(DeleteBehavior.Cascade);
        }
        builder.Entity<TrainingWorkout>().HasIndex(x => new { x.OwnerId, x.StartedAt });
        builder.Entity<TrainingWorkout>().HasMany(x => x.Pauses).WithOne()
            .HasForeignKey(x => new { x.OwnerId, x.WorkoutId }).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<TrainingPause>().HasKey(x => new { x.OwnerId, x.WorkoutId, x.Position });
        builder.Entity<TrainingTemplate>().HasMany(x => x.Variations).WithOne()
            .HasForeignKey(x => new { x.OwnerId, x.TemplateId }).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<TrainingVariation>().HasKey(x => new { x.OwnerId, x.TemplateId, x.Position });
        builder.Entity<TrainingExercise>().HasKey(x => new { x.OwnerId, x.Kind, x.AggregateId, x.VariationIndex, x.Position });
        builder.Entity<TrainingExercise>().HasIndex(x => new { x.OwnerId, x.ExerciseId });
        builder.Entity<TrainingExercise>().HasOne<TrainingRecordMetadata>().WithMany()
            .HasForeignKey(x => new { x.OwnerId, x.Kind, x.AggregateId }).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<TrainingExercise>().HasMany(x => x.Sets).WithOne()
            .HasForeignKey(x => new { x.OwnerId, x.Kind, x.AggregateId, x.VariationIndex, x.ExercisePosition })
            .OnDelete(DeleteBehavior.Cascade);
        builder.Entity<TrainingSet>().HasKey(x => new { x.OwnerId, x.Kind, x.AggregateId, x.VariationIndex, x.ExercisePosition, x.Position });
        builder.Entity<TrainingSet>().HasMany(x => x.DropStages).WithOne()
            .HasForeignKey(x => new { x.OwnerId, x.Kind, x.AggregateId, x.VariationIndex, x.ExercisePosition, x.SetPosition })
            .OnDelete(DeleteBehavior.Cascade);
        builder.Entity<TrainingDropStage>().HasKey(x => new { x.OwnerId, x.Kind, x.AggregateId, x.VariationIndex, x.ExercisePosition, x.SetPosition, x.Position });
        builder.Entity<TrainingHeartRate>().HasOne<TrainingWorkout>().WithOne()
            .HasForeignKey<TrainingHeartRate>(x => new { x.OwnerId, x.Id }).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<TrainingHeartRate>().HasMany(x => x.Readings).WithOne()
            .HasForeignKey(x => new { x.OwnerId, x.WorkoutId }).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<TrainingHeartRateReading>().HasKey(x => new { x.OwnerId, x.WorkoutId, x.Position });
        foreach (var type in builder.Model.GetEntityTypes().Where(x => x.ClrType.Name.StartsWith("Training", StringComparison.Ordinal)))
        {
            builder.Entity(type.ClrType).Property("OwnerId").HasMaxLength(36);
            if (type.FindProperty("Kind") is not null) builder.Entity(type.ClrType).Property("Kind").HasMaxLength(16);
        }
    }
}
