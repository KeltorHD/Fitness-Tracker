using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace FitLife.Backend;

/// <summary>Явное преобразование wire DTO в нормализованные строки без сохранения архива/payload.</summary>
internal static class TrainingMapping
{
    /// <summary>Создаёт корневую строку тренировки и точные интервалы пауз.</summary>
    internal static TrainingWorkout Workout(string owner, WorkoutData value) => new()
    {
        OwnerId = owner,
        Id = value.Id,
        Name = value.Name,
        StartedAt = value.StartedAt,
        EndedAt = value.EndedAt,
        Status = value.Status,
        RestSeconds = value.RestSeconds,
        RestEndsAt = value.RestEndsAt,
        PausedAt = value.PausedAt,
        PausedSeconds = value.PausedSeconds,
        Notes = value.Notes,
        BodyWeightKG = value.BodyWeightKG,
        DurationIsKnown = value.DurationIsKnown,
        Pauses = value.Pauses.Select((pause, index) => new TrainingPause
        {
            OwnerId = owner,
            WorkoutId = value.Id,
            Position = index,
            StartedAt = pause.StartedAt,
            EndedAt = pause.EndedAt
        }).ToList()
    };

    /// <summary>Создаёт корневую строку плана с каноническими наборами выбора.</summary>
    internal static TrainingTemplate Template(string owner, TemplateData value) => new()
    {
        OwnerId = owner,
        Id = value.Id,
        Name = value.Name,
        RestSeconds = value.RestSeconds,
        BaseVariationName = value.BaseVariationName,
        MuscleGroupsJson = JsonSerializer.Serialize(value.MuscleGroups),
        MusclesJson = JsonSerializer.Serialize(value.Muscles),
        MuscleRegionsJson = JsonSerializer.Serialize(value.MuscleRegions),
        PreferredWeekdaysJson = JsonSerializer.Serialize(value.PreferredWeekdays),
        Variations = value.Variations.Select((variation, index) => new TrainingVariation
        {
            OwnerId = owner,
            TemplateId = value.Id,
            Position = index + 1,
            Id = variation.Id,
            Name = variation.Name
        }).ToList()
    };

    /// <summary>Создаёт самостоятельный замер веса с необязательной связью с тренировкой.</summary>
    internal static TrainingBodyWeight BodyWeight(string owner, BodyWeightData value) => new()
    {
        OwnerId = owner,
        Id = value.Id,
        MeasuredAt = value.MeasuredAt,
        WeightKG = value.WeightKG,
        WorkoutID = value.WorkoutID
    };

    /// <summary>Создаёт запись пульса и упорядоченные измерения с исходной точностью.</summary>
    internal static TrainingHeartRate HeartRate(string owner, HeartRateData value) => new()
    {
        OwnerId = owner,
        Id = value.WorkoutID,
        SchemaVersion = value.SchemaVersion,
        Mode = value.Mode,
        Origin = value.Origin,
        Readings = value.Readings.Select((reading, index) => new TrainingHeartRateReading
        {
            OwnerId = owner,
            WorkoutId = value.WorkoutID,
            Position = index,
            Date = reading.Date,
            BeatsPerMinute = reading.BeatsPerMinute
        }).ToList()
    };

    /// <summary>Создаёт нормализованные строки упражнений тренировки с исходными позициями.</summary>
    internal static List<TrainingExercise> WorkoutExercises(string owner, WorkoutData value) =>
        value.Exercises.Select((row, index) => Exercise(owner, TrainingKinds.Workout, value.Id, 0,
            index, row.Id, row.Exercise, row.SupersetID, row.Sets)).ToList();

    /// <summary>Создаёт строки основного плана и всех вариаций с независимыми позициями.</summary>
    internal static List<TrainingExercise> TemplateExercises(string owner, TemplateData value)
    {
        var rows = new List<TrainingExercise>();
        Add(value.Exercises, 0);
        for (var index = 0; index < value.Variations.Count; index++) Add(value.Variations[index].Exercises, index + 1);
        return rows;
        void Add(List<TemplateExerciseData> exercises, int variation)
        {
            rows.AddRange(exercises.Select((row, index) =>
            {
                var result = Exercise(owner, TrainingKinds.Template, value.Id, variation, index,
                    row.Id, row.Exercise, row.SupersetID, row.PlannedSets ?? []);
                result.SetCount = row.SetCount;
                result.Repetitions = row.Repetitions;
                result.WeightKG = row.WeightKG;
                result.LoadMultiplier = row.LoadMultiplier;
                result.HasPlannedSets = row.PlannedSets is not null;
                return result;
            }));
        }
    }

    /// <summary>Создаёт снимок упражнения, подходов и дроп-этапов с исходными UUID.</summary>
    private static TrainingExercise Exercise(string owner, string kind, Guid aggregate, int variation,
        int position, Guid id, ExerciseData exercise, Guid? superset, List<WorkoutSetData> sets) => new()
        {
            OwnerId = owner,
            Kind = kind,
            AggregateId = aggregate,
            VariationIndex = variation,
            Position = position,
            Id = id,
            ExerciseId = exercise.Id,
            Name = exercise.Name,
            Muscle = exercise.Muscle,
            Instructions = exercise.Instructions,
            SupersetID = superset,
            Sets = sets.Select((set, index) => new TrainingSet
            {
                OwnerId = owner,
                Kind = kind,
                AggregateId = aggregate,
                VariationIndex = variation,
                ExercisePosition = position,
                Position = index,
                Id = set.Id,
                Repetitions = set.Repetitions,
                WeightKG = set.WeightKG,
                IsWarmup = set.IsWarmup,
                CompletedAt = set.CompletedAt,
                LoadMultiplier = set.LoadMultiplier,
                Note = set.Note,
                HasDropStages = set.DropStages is not null,
                DropStages = (set.DropStages ?? []).Select((stage, stageIndex) => new TrainingDropStage
                {
                    OwnerId = owner,
                    Kind = kind,
                    AggregateId = aggregate,
                    VariationIndex = variation,
                    ExercisePosition = position,
                    SetPosition = index,
                    Position = stageIndex,
                    Id = stage.Id,
                    Repetitions = stage.Repetitions,
                    WeightKG = stage.WeightKG,
                    CompletedAt = stage.CompletedAt
                }).ToList()
            }).ToList()
        };

    /// <summary>Восстанавливает полный DTO из нормализованных таблиц только указанного владельца.</summary>
    internal static async Task<JsonElement> ReadAsync(BackupDbContext database, string owner, string kind,
        Guid id, CancellationToken cancellationToken)
    {
        if (TrainingKinds.IsNutrition(kind)) return await NutritionStorage.ReadAsync(database, owner, kind, id, cancellationToken);
        if (kind == TrainingKinds.ExerciseLink)
        {
            var value = await database.Set<TrainingExerciseLink>().AsNoTracking()
                .SingleAsync(x => x.OwnerId == owner && x.Id == id, cancellationToken);
            return TrainingJson.Element(new ExerciseLinkData { Id = value.Id, CatalogID = value.CatalogID });
        }
        if (kind == TrainingKinds.BodyWeight)
        {
            var value = await database.BodyWeights.AsNoTracking().SingleAsync(x => x.OwnerId == owner && x.Id == id, cancellationToken);
            return TrainingJson.Element(new BodyWeightData
            {
                Id = value.Id,
                MeasuredAt = value.MeasuredAt,
                WeightKG = value.WeightKG,
                WorkoutID = value.WorkoutID
            });
        }
        if (kind == TrainingKinds.HeartRate)
        {
            var value = await database.HeartRateRecordings.AsNoTracking().Include(x => x.Readings)
                .SingleAsync(x => x.OwnerId == owner && x.Id == id, cancellationToken);
            return TrainingJson.Element(new HeartRateData
            {
                WorkoutID = value.Id,
                SchemaVersion = value.SchemaVersion,
                Mode = value.Mode,
                Origin = value.Origin,
                Readings = value.Readings.OrderBy(x => x.Position).Select(x => new HeartRateReadingData
                { Date = x.Date, BeatsPerMinute = x.BeatsPerMinute }).ToList()
            });
        }
        var rows = await database.Exercises.AsNoTracking().Where(x => x.OwnerId == owner && x.Kind == kind && x.AggregateId == id)
            .Include(x => x.Sets).ThenInclude(x => x.DropStages).AsSplitQuery().ToListAsync(cancellationToken);
        if (kind == TrainingKinds.Workout)
        {
            var value = await database.Workouts.AsNoTracking().Include(x => x.Pauses)
                .SingleAsync(x => x.OwnerId == owner && x.Id == id, cancellationToken);
            return TrainingJson.Element(new WorkoutData
            {
                Id = value.Id,
                Name = value.Name,
                StartedAt = value.StartedAt,
                EndedAt = value.EndedAt,
                Status = value.Status,
                RestSeconds = value.RestSeconds,
                RestEndsAt = value.RestEndsAt,
                PausedAt = value.PausedAt,
                PausedSeconds = value.PausedSeconds,
                Notes = value.Notes,
                BodyWeightKG = value.BodyWeightKG,
                DurationIsKnown = value.DurationIsKnown,
                Pauses = value.Pauses.OrderBy(x => x.Position).Select(x => new WorkoutPauseData
                { StartedAt = x.StartedAt, EndedAt = x.EndedAt }).ToList(),
                Exercises = rows.OrderBy(x => x.Position).Select(x => new WorkoutExerciseData
                { Id = x.Id, Exercise = ExerciseValue(x), SupersetID = x.SupersetID, Sets = Sets(x) }).ToList()
            });
        }
        var template = await database.Templates.AsNoTracking().Include(x => x.Variations)
            .SingleAsync(x => x.OwnerId == owner && x.Id == id, cancellationToken);
        return TrainingJson.Element(new TemplateData
        {
            Id = template.Id,
            Name = template.Name,
            RestSeconds = template.RestSeconds,
            BaseVariationName = template.BaseVariationName,
            MuscleGroups = JsonSerializer.Deserialize<List<string>>(template.MuscleGroupsJson) ?? [],
            Muscles = JsonSerializer.Deserialize<List<string>>(template.MusclesJson) ?? [],
            MuscleRegions = JsonSerializer.Deserialize<List<string>>(template.MuscleRegionsJson) ?? [],
            PreferredWeekdays = JsonSerializer.Deserialize<List<int>>(template.PreferredWeekdaysJson) ?? [],
            Exercises = TemplateRows(0),
            Variations = template.Variations.OrderBy(x => x.Position).Select(x => new TemplateVariationData
            { Id = x.Id, Name = x.Name, Exercises = TemplateRows(x.Position) }).ToList()
        });

        List<TemplateExerciseData> TemplateRows(int variation) => rows.Where(x => x.VariationIndex == variation)
            .OrderBy(x => x.Position).Select(x => new TemplateExerciseData
            {
                Id = x.Id,
                Exercise = ExerciseValue(x),
                SetCount = x.SetCount!.Value,
                Repetitions = x.Repetitions!.Value,
                WeightKG = x.WeightKG!.Value,
                LoadMultiplier = x.LoadMultiplier,
                SupersetID = x.SupersetID,
                PlannedSets = x.HasPlannedSets ? Sets(x) : null
            }).ToList();
    }

    /// <summary>Возвращает исторический снимок упражнения с исходным UUID.</summary>
    private static ExerciseData ExerciseValue(TrainingExercise value) => new()
    { Id = value.ExerciseId, Name = value.Name, Muscle = value.Muscle, Instructions = value.Instructions };

    /// <summary>Восстанавливает упорядоченные подходы и дополнительные этапы, сохраняя null-списки.</summary>
    private static List<WorkoutSetData> Sets(TrainingExercise value) => value.Sets.OrderBy(x => x.Position).Select(x => new WorkoutSetData
    {
        Id = x.Id,
        Repetitions = x.Repetitions,
        WeightKG = x.WeightKG,
        IsWarmup = x.IsWarmup,
        CompletedAt = x.CompletedAt,
        LoadMultiplier = x.LoadMultiplier,
        Note = x.Note,
        DropStages = x.HasDropStages ? x.DropStages.OrderBy(stage => stage.Position).Select(stage => new DropStageData
        { Id = stage.Id, Repetitions = stage.Repetitions, WeightKG = stage.WeightKG, CompletedAt = stage.CompletedAt }).ToList() : null
    }).ToList();
}
