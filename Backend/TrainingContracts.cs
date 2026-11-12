using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Encodings.Web;

namespace FitLife.Backend;

/// <summary>Текущий тип записи журнала; UUID сохраняются между устройствами.</summary>
public static class TrainingKinds
{
    public const string Workout = "workout";
    public const string Template = "template";
    public const string BodyWeight = "bodyWeight";
    public const string HeartRate = "heartRate";
    public static bool Contains(string kind) => kind is Workout or Template or BodyWeight or HeartRate;
}

/// <summary>Одна мутация с известной клиенту версией; владелец определяется только JWT.</summary>
public sealed record TrainingMutation
{
    public required string Kind { get; init; }
    public required Guid Id { get; init; }
    public required long BaseRevision { get; init; }
    public required bool Deleted { get; init; }
    public JsonElement? Value { get; init; }
}

/// <summary>Серверная версия агрегата либо tombstone, необходимый для офлайн-удалений.</summary>
public sealed record TrainingChange(string Kind, Guid Id, long Revision, bool Deleted, JsonElement? Value);
public sealed record TrainingPage(IReadOnlyList<TrainingChange> Changes, long Cursor, bool HasMore);

public sealed record ExerciseData
{
    public required Guid Id { get; init; }
    public required string Name { get; init; }
    public required string Muscle { get; init; }
    public required string Instructions { get; init; }
}

public sealed record DropStageData
{
    public required Guid Id { get; init; }
    public required int Repetitions { get; init; }
    public required double WeightKG { get; init; }
    public double? CompletedAt { get; init; }
}

public sealed record WorkoutSetData
{
    public required Guid Id { get; init; }
    public required int Repetitions { get; init; }
    public required double WeightKG { get; init; }
    public required bool IsWarmup { get; init; }
    public double? CompletedAt { get; init; }
    public int? LoadMultiplier { get; init; }
    public List<DropStageData>? DropStages { get; init; }
    public string? Note { get; init; }
}

public sealed record WorkoutExerciseData
{
    public required Guid Id { get; init; }
    public required ExerciseData Exercise { get; init; }
    public required List<WorkoutSetData> Sets { get; init; }
    public Guid? SupersetID { get; init; }
}

public sealed record WorkoutPauseData
{
    public required double StartedAt { get; init; }
    public required double EndedAt { get; init; }
}

/// <summary>Числовые Unix seconds соответствуют Swift Date и сохраняют дробную точность.</summary>
public sealed record WorkoutData
{
    public required Guid Id { get; init; }
    public required string Name { get; init; }
    public required double StartedAt { get; init; }
    public double? EndedAt { get; init; }
    public required string Status { get; init; }
    public required List<WorkoutExerciseData> Exercises { get; init; }
    public required int RestSeconds { get; init; }
    public double? RestEndsAt { get; init; }
    public double? PausedAt { get; init; }
    public required List<WorkoutPauseData> Pauses { get; init; }
    public required double PausedSeconds { get; init; }
    public required string Notes { get; init; }
    public double? BodyWeightKG { get; init; }
    public bool? DurationIsKnown { get; init; }
}

public sealed record TemplateExerciseData
{
    public required Guid Id { get; init; }
    public required ExerciseData Exercise { get; init; }
    public required int SetCount { get; init; }
    public required int Repetitions { get; init; }
    public required double WeightKG { get; init; }
    public int? LoadMultiplier { get; init; }
    public List<WorkoutSetData>? PlannedSets { get; init; }
    public Guid? SupersetID { get; init; }
}

public sealed record TemplateVariationData
{
    public required Guid Id { get; init; }
    public required string Name { get; init; }
    public required List<TemplateExerciseData> Exercises { get; init; }
}

public sealed record TemplateData
{
    public required Guid Id { get; init; }
    public required string Name { get; init; }
    public required List<TemplateExerciseData> Exercises { get; init; }
    public required int RestSeconds { get; init; }
    public required List<string> MuscleGroups { get; init; }
    public required List<string> Muscles { get; init; }
    public required List<string> MuscleRegions { get; init; }
    public required List<int> PreferredWeekdays { get; init; }
    public required List<TemplateVariationData> Variations { get; init; }
    public string? BaseVariationName { get; init; }
}

public sealed record BodyWeightData
{
    public required Guid Id { get; init; }
    public required double MeasuredAt { get; init; }
    public required double WeightKG { get; init; }
    public Guid? WorkoutID { get; init; }
}

public sealed record HeartRateReadingData
{
    public required double Date { get; init; }
    public required double BeatsPerMinute { get; init; }
}

public sealed record HeartRateData
{
    public required int SchemaVersion { get; init; }
    public required Guid WorkoutID { get; init; }
    public required string Mode { get; init; }
    public string? Origin { get; init; }
    public required List<HeartRateReadingData> Readings { get; init; }
}

/// <summary>Единые строгие правила wire JSON; неизвестные поля не теряются при записи.</summary>
internal static class TrainingJson
{
    internal static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        NumberHandling = JsonNumberHandling.Strict,
        RespectNullableAnnotations = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        MaxDepth = 32
    };

    internal static T Read<T>(JsonElement value) => value.Deserialize<T>(Options)
        ?? throw new TrainingException(400, "invalid_training_data");
    internal static JsonElement Element<T>(T value) => JsonSerializer.SerializeToElement(value, Options);
}

public sealed class TrainingException(int status, string code, TrainingChange? current = null) : Exception(code)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
    public TrainingChange? Current { get; } = current;
}
