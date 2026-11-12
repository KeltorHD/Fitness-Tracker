using System.Text.Json;
using System.Globalization;

namespace FitLife.Backend;

/// <summary>Повторяет правила сохраняемых моделей Swift Core на недоверенной HTTP-границе.</summary>
internal static class TrainingValidation
{
    private static readonly HashSet<string> Groups = ["chest", "back", "legs", "shoulders", "arms", "core", "fullBody"];
    private static readonly HashSet<string> Muscles = ["chest", "lats", "middle back", "lower back", "traps", "quadriceps", "hamstrings", "glutes", "calves", "abductors", "adductors", "shoulders", "neck", "biceps", "triceps", "forearms", "abdominals"];
    private static readonly HashSet<string> Regions = ["chestUpper", "chestMiddle", "chestLower", "deltoidAnterior", "deltoidLateral", "deltoidPosterior", "rotatorCuff", "trapeziusUpper", "trapeziusMiddle", "trapeziusLower", "rectusAbdominisUpper", "rectusAbdominisLower", "obliques", "transversusAbdominis", "bicepsLong", "bicepsShort", "tricepsLong", "tricepsLateral", "tricepsMedial", "rectusFemoris", "vastusLateralis", "vastusMedialis", "vastusIntermedius", "bicepsFemoris", "semitendinosus", "semimembranosus", "gluteusMaximus", "gluteusMedius", "gluteusMinimus", "gastrocnemius", "soleus"];

    internal static JsonElement Canonical(string kind, Guid id, JsonElement value)
    {
        switch (kind)
        {
            case TrainingKinds.Workout:
                var workout = TrainingJson.Read<WorkoutData>(value);
                Check(workout.Id == id);
                Workout(workout);
                return TrainingJson.Element(workout);
            case TrainingKinds.Template:
                var template = TrainingJson.Read<TemplateData>(value);
                Check(template.Id == id);
                Template(template);
                return TrainingJson.Element(template with
                {
                    MuscleGroups = template.MuscleGroups.Order(StringComparer.Ordinal).ToList(),
                    Muscles = template.Muscles.Order(StringComparer.Ordinal).ToList(),
                    MuscleRegions = template.MuscleRegions.Order(StringComparer.Ordinal).ToList(),
                    PreferredWeekdays = template.PreferredWeekdays.Order().ToList()
                });
            case TrainingKinds.BodyWeight:
                var weight = TrainingJson.Read<BodyWeightData>(value);
                Check(weight.Id == id);
                Weight(weight.WeightKG);
                Time(weight.MeasuredAt);
                return TrainingJson.Element(weight);
            case TrainingKinds.HeartRate:
                var heart = TrainingJson.Read<HeartRateData>(value);
                Check(heart.WorkoutID == id && heart.SchemaVersion == 1);
                Check(heart.Mode is "appleHealth" or "bluetooth");
                Check(heart.Origin is null or "liveHealthKit");
                Check(heart.Origin is null || heart.Mode == "appleHealth");
                List(heart.Readings);
                Check(heart.Readings.Count <= 10_000);
                var previous = double.NegativeInfinity;
                foreach (var reading in heart.Readings)
                {
                    Time(reading.Date);
                    Check(double.IsFinite(reading.BeatsPerMinute) && reading.BeatsPerMinute is >= 1 and <= 300 && reading.Date > previous);
                    previous = reading.Date;
                }
                return TrainingJson.Element(heart);
            default:
                throw new TrainingException(400, "invalid_training_kind");
        }
    }

    private static void Workout(WorkoutData value)
    {
        Name(value.Name);
        Time(value.StartedAt);
        OptionalTime(value.EndedAt);
        OptionalTime(value.PausedAt);
        OptionalTime(value.RestEndsAt);
        if (value.BodyWeightKG is { } bodyWeight) Weight(bodyWeight);
        Check(value.Notes is not null && value.RestSeconds is >= 0 and <= 3600);
        Check(value.Status is "active" or "paused" or "completed" or "cancelled");
        Check((value.Status == "paused") == (value.PausedAt is not null));
        Check((value.Status is "completed" or "cancelled") == (value.EndedAt is not null));
        Check(double.IsFinite(value.PausedSeconds) && value.PausedSeconds >= 0);
        if (value.EndedAt is { } end) Check(end >= value.StartedAt && value.PausedSeconds <= end - value.StartedAt);
        List(value.Pauses);
        var previousEnd = value.StartedAt;
        var pausedSeconds = 0.0;
        foreach (var pause in value.Pauses)
        {
            Time(pause.StartedAt);
            Time(pause.EndedAt);
            Check(pause.StartedAt >= previousEnd && pause.EndedAt >= pause.StartedAt && pause.EndedAt <= (value.EndedAt ?? double.PositiveInfinity));
            previousEnd = pause.EndedAt;
            pausedSeconds += pause.EndedAt - pause.StartedAt;
        }
        Check(Math.Abs(pausedSeconds - value.PausedSeconds) < 0.01);
        if (value.PausedAt is { } pausedAt) Check(pausedAt >= previousEnd);
        List(value.Exercises);
        Unique(value.Exercises.Select(x => x.Id));
        Supersets(value.Exercises.Select(x => x.SupersetID));
        var setIds = new List<Guid>();
        var completed = false;
        foreach (var row in value.Exercises)
        {
            Exercise(row.Exercise);
            List(row.Sets);
            Check(row.Sets.Count is >= 1 and <= 30);
            foreach (var set in row.Sets)
            {
                Set(set, true);
                setIds.Add(set.Id);
                setIds.AddRange((set.DropStages ?? []).Select(x => x.Id));
                if (set.CompletedAt is not null) completed = true;
                foreach (var date in new[] { set.CompletedAt }.Concat((set.DropStages ?? []).Select(x => x.CompletedAt)).OfType<double>())
                    Check(date >= value.StartedAt && date <= (value.EndedAt ?? double.PositiveInfinity));
            }
        }
        Unique(setIds);
        Check(value.Status != "completed" || completed);
    }

    private static void Template(TemplateData value)
    {
        Name(value.Name);
        if (value.BaseVariationName is { } name) Name(name);
        Check(value.RestSeconds is >= 0 and <= 3600);
        List(value.MuscleGroups);
        List(value.Muscles);
        List(value.MuscleRegions);
        List(value.PreferredWeekdays);
        List(value.Variations);
        Check(value.MuscleGroups.All(Groups.Contains) && value.Muscles.All(Muscles.Contains) && value.MuscleRegions.All(Regions.Contains));
        Check(value.PreferredWeekdays.All(x => x is >= 1 and <= 7));
        Check(value.MuscleGroups.Distinct().Count() == value.MuscleGroups.Count && value.Muscles.Distinct().Count() == value.Muscles.Count);
        Check(value.MuscleRegions.Distinct().Count() == value.MuscleRegions.Count && value.PreferredWeekdays.Distinct().Count() == value.PreferredWeekdays.Count);
        Unique(value.Variations.Select(x => x.Id).Append(value.Id));
        var allRows = new List<TemplateExerciseData>();
        Rows(value.Exercises);
        foreach (var variation in value.Variations) { Name(variation.Name); Rows(variation.Exercises); }
        Unique(allRows.Select(x => x.Id));
        Unique(allRows.SelectMany(x => x.PlannedSets ?? []).SelectMany(x => new[] { x.Id }.Concat((x.DropStages ?? []).Select(stage => stage.Id))));
        void Rows(List<TemplateExerciseData> rows)
        {
            List(rows);
            Check(rows.Count > 0);
            Supersets(rows.Select(x => x.SupersetID));
            allRows.AddRange(rows);
            foreach (var row in rows)
            {
                Exercise(row.Exercise);
                Check(row.SetCount is >= 1 and <= 30);
                Numbers(row.Repetitions, row.WeightKG, row.LoadMultiplier, false);
                if (row.PlannedSets is not { } sets) continue;
                List(sets);
                Check(sets.Count == row.SetCount);
                foreach (var set in sets)
                {
                    Set(set, false);
                    Check(set.CompletedAt is null && (set.DropStages ?? []).All(x => x.CompletedAt is null));
                }
            }
        }
    }

    private static void Set(WorkoutSetData value, bool allowUnperformed)
    {
        Numbers(value.Repetitions, value.WeightKG, value.LoadMultiplier, allowUnperformed && value.CompletedAt is null);
        OptionalTime(value.CompletedAt);
        Check(value.Note is null || new StringInfo(value.Note).LengthInTextElements <= 2000);
        if (value.DropStages is not { } stages) return;
        List(stages);
        Check(!value.IsWarmup && stages.Count is >= 1 and <= 5);
        Unique(stages.Select(x => x.Id).Append(value.Id));
        var weight = value.WeightKG;
        var completedAt = value.CompletedAt;
        foreach (var stage in stages)
        {
            Numbers(stage.Repetitions, stage.WeightKG, null, false);
            Check(stage.WeightKG < weight);
            OptionalTime(stage.CompletedAt);
            if (stage.CompletedAt is { } date) Check(completedAt is { } previous && date >= previous);
            weight = stage.WeightKG;
            completedAt = stage.CompletedAt;
        }
    }

    private static void Exercise(ExerciseData value)
    {
        Check(value is not null);
        Name(value!.Name);
        Check(Groups.Contains(value.Muscle) && value.Instructions is not null);
    }
    private static void Numbers(int repetitions, double weight, int? multiplier, bool allowZero)
    {
        Check(repetitions is >= 1 and <= 1000 || allowZero && repetitions == 0);
        Check(double.IsFinite(weight) && weight is >= 0 and <= 1500 && (multiplier ?? 1) is >= 1 and <= 10);
    }
    private static void Weight(double value) => Check(double.IsFinite(value) && value is > 0 and <= 1000);
    private static void Time(double value) => Check(double.IsFinite(value));
    private static void OptionalTime(double? value) { if (value is { } date) Time(date); }
    private static void Name(string value) => Check(value is not null && new StringInfo(value.Trim()).LengthInTextElements is >= 1 and <= 80);
    private static void Unique(IEnumerable<Guid> values) { var ids = values.ToList(); Check(ids.Distinct().Count() == ids.Count); }
    private static void List<T>(List<T> values) => Check(values is not null && values.All(x => x is not null));
    private static void Supersets(IEnumerable<Guid?> values)
    {
        foreach (var group in values.Select((id, index) => (id, index)).Where(x => x.id is not null).GroupBy(x => x.id))
        {
            var indices = group.Select(x => x.index).ToList();
            Check(indices.Count >= 2 && indices[^1] - indices[0] + 1 == indices.Count);
        }
    }
    private static void Check(bool value) { if (!value) throw new TrainingException(400, "invalid_training_data"); }
}
