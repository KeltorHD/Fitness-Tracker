using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Encodings.Web;

namespace FitLife.Backend;

/// <summary>Текущий тип записи журнала; UUID сохраняются между устройствами.</summary>
public static class TrainingKinds
{
    /// <summary>Тип тренировки.</summary>
    public const string Workout = "workout";
    /// <summary>Тип плана тренировки.</summary>
    public const string Template = "template";
    /// <summary>Тип самостоятельного замера веса.</summary>
    public const string BodyWeight = "bodyWeight";
    /// <summary>Тип записи пульса.</summary>
    public const string HeartRate = "heartRate";
    /// <summary>Тип записи питания: foodEntry.</summary>
    public const string FoodEntry = "foodEntry";
    /// <summary>Тип записи питания: waterEntry.</summary>
    public const string WaterEntry = "waterEntry";
    /// <summary>Тип записи питания: supplementEntry.</summary>
    public const string SupplementEntry = "supplementEntry";
    /// <summary>Тип записи питания: supplementPlan.</summary>
    public const string SupplementPlan = "supplementPlan";
    /// <summary>Тип записи питания: nutritionProfile.</summary>
    public const string NutritionProfile = "nutritionProfile";
    /// <summary>Возвращает true только для действующих типов журнала.</summary>
    public static bool Contains(string kind) => kind is Workout or Template or BodyWeight or HeartRate || IsNutrition(kind);
    /// <summary>Определяет агрегаты дневника питания.</summary>
    public static bool IsNutrition(string kind) => kind is FoodEntry or WaterEntry or SupplementEntry or SupplementPlan or NutritionProfile;
}

/// <summary>Одна мутация с известной клиенту версией; владелец определяется только JWT.</summary>
public sealed record TrainingMutation
{
    /// <summary>Текущий тип агрегата журнала.</summary>
    public required string Kind { get; init; }
    /// <summary>Стабильный UUID из Core.</summary>
    public required Guid Id { get; init; }
    /// <summary>Последняя известная клиенту версия; ноль означает новую запись.</summary>
    public required long BaseRevision { get; init; }
    /// <summary>Признак tombstone, распространяющего офлайн-удаление.</summary>
    public required bool Deleted { get; init; }
    /// <summary>Типизированный JSON текущего значения; null при удалении.</summary>
    public JsonElement? Value { get; init; }
}

/// <summary>Серверная версия агрегата либо tombstone, необходимый для офлайн-удалений.</summary>
public sealed record TrainingChange(string Kind, Guid Id, long Revision, bool Deleted, JsonElement? Value);
/// <summary>Страница последних версий агрегатов после указанного курсора.</summary>
public sealed record TrainingPage(IReadOnlyList<TrainingChange> Changes, long Cursor, bool HasMore);

/// <summary>Историческое определение упражнения в контракте Core.</summary>
public sealed record ExerciseData
{
    /// <summary>Стабильный UUID из Core.</summary>
    public required Guid Id { get; init; }
    /// <summary>Сохранённое имя, независимое от будущих переименований каталога.</summary>
    public required string Name { get; init; }
    /// <summary>Основная группа мышц упражнения в обозначениях Core.</summary>
    public required string Muscle { get; init; }
    /// <summary>Исторический текст инструкции упражнения.</summary>
    public required string Instructions { get; init; }
}

/// <summary>Параметры и выполнение дополнительного этапа дропсета.</summary>
public sealed record DropStageData
{
    /// <summary>Стабильный UUID из Core.</summary>
    public required Guid Id { get; init; }
    /// <summary>Количество повторений; ноль допустим для незаполненного подхода.</summary>
    public required int Repetitions { get; init; }
    /// <summary>Вес в килограммах; ноль означает отсутствие добавленного веса.</summary>
    public required double WeightKG { get; init; }
    /// <summary>Unix seconds выполнения; null означает невыполненный этап.</summary>
    public double? CompletedAt { get; init; }
}

/// <summary>Цели и выполнение подхода, включая разминку, множитель и заметку.</summary>
public sealed record WorkoutSetData
{
    /// <summary>Стабильный UUID из Core.</summary>
    public required Guid Id { get; init; }
    /// <summary>Количество повторений; ноль допустим для незаполненного подхода.</summary>
    public required int Repetitions { get; init; }
    /// <summary>Вес в килограммах; ноль означает отсутствие добавленного веса.</summary>
    public required double WeightKG { get; init; }
    /// <summary>Разминочный подход исключается из рабочего объёма.</summary>
    public required bool IsWarmup { get; init; }
    /// <summary>Unix seconds выполнения; null означает невыполненный этап.</summary>
    public double? CompletedAt { get; init; }
    /// <summary>Необязательный множитель нагрузки, например для парных гантелей.</summary>
    public int? LoadMultiplier { get; init; }
    /// <summary>Упорядоченные дополнительные этапы; null сохраняет отсутствие дропсета.</summary>
    public List<DropStageData>? DropStages { get; init; }
    /// <summary>Необязательная пользовательская заметка подхода.</summary>
    public string? Note { get; init; }
}

/// <summary>Строка упражнения с сохранением порядка подходов и суперсета.</summary>
public sealed record WorkoutExerciseData
{
    /// <summary>Стабильный UUID из Core.</summary>
    public required Guid Id { get; init; }
    /// <summary>Снимок определения упражнения с исходным UUID.</summary>
    public required ExerciseData Exercise { get; init; }
    /// <summary>Подходы в исходном порядке.</summary>
    public required List<WorkoutSetData> Sets { get; init; }
    /// <summary>UUID непрерывной группы суперсета либо null.</summary>
    public Guid? SupersetID { get; init; }
}

/// <summary>Завершённая пауза в числовых Unix seconds.</summary>
public sealed record WorkoutPauseData
{
    /// <summary>Начало события в Unix seconds с дробной точностью.</summary>
    public required double StartedAt { get; init; }
    /// <summary>Завершение события в Unix seconds; null у незавершённой тренировки.</summary>
    public required double EndedAt { get; init; }
}

/// <summary>Числовые Unix seconds соответствуют Swift Date и сохраняют дробную точность.</summary>
public sealed record WorkoutData
{
    /// <summary>Стабильный UUID из Core.</summary>
    public required Guid Id { get; init; }
    /// <summary>Сохранённое имя, независимое от будущих переименований каталога.</summary>
    public required string Name { get; init; }
    /// <summary>Начало события в Unix seconds с дробной точностью.</summary>
    public required double StartedAt { get; init; }
    /// <summary>Завершение события в Unix seconds; null у незавершённой тренировки.</summary>
    public double? EndedAt { get; init; }
    /// <summary>Состояние Core: active, paused, completed или cancelled.</summary>
    public required string Status { get; init; }
    /// <summary>Упражнения в исходном порядке.</summary>
    public required List<WorkoutExerciseData> Exercises { get; init; }
    /// <summary>Настроенная длительность отдыха в секундах.</summary>
    public required int RestSeconds { get; init; }
    /// <summary>Сохранённая дата окончания текущего отдыха либо null.</summary>
    public double? RestEndsAt { get; init; }
    /// <summary>Начало текущей незавершённой паузы либо null.</summary>
    public double? PausedAt { get; init; }
    /// <summary>Завершённые интервалы пауз в исходном порядке.</summary>
    public required List<WorkoutPauseData> Pauses { get; init; }
    /// <summary>Суммарное время завершённых пауз в секундах.</summary>
    public required double PausedSeconds { get; init; }
    /// <summary>Заметка тренировки; пустая строка сохраняется.</summary>
    public required string Notes { get; init; }
    /// <summary>Явно записанный вес тела; не вычисляется из замеров.</summary>
    public double? BodyWeightKG { get; init; }
    /// <summary>False у импорта с неизвестной длительностью; null сохраняется.</summary>
    public bool? DurationIsKnown { get; init; }
}

/// <summary>Строка плана с общими либо индивидуальными целями подходов.</summary>
public sealed record TemplateExerciseData
{
    /// <summary>Стабильный UUID из Core.</summary>
    public required Guid Id { get; init; }
    /// <summary>Снимок определения упражнения с исходным UUID.</summary>
    public required ExerciseData Exercise { get; init; }
    /// <summary>Число запланированных подходов.</summary>
    public required int SetCount { get; init; }
    /// <summary>Количество повторений; ноль допустим для незаполненного подхода.</summary>
    public required int Repetitions { get; init; }
    /// <summary>Вес в килограммах; ноль означает отсутствие добавленного веса.</summary>
    public required double WeightKG { get; init; }
    /// <summary>Необязательный множитель нагрузки, например для парных гантелей.</summary>
    public int? LoadMultiplier { get; init; }
    /// <summary>Индивидуальные цели; null использует общие параметры строки.</summary>
    public List<WorkoutSetData>? PlannedSets { get; init; }
    /// <summary>UUID непрерывной группы суперсета либо null.</summary>
    public Guid? SupersetID { get; init; }
}

/// <summary>Самостоятельная именованная вариация списка упражнений.</summary>
public sealed record TemplateVariationData
{
    /// <summary>Стабильный UUID из Core.</summary>
    public required Guid Id { get; init; }
    /// <summary>Сохранённое имя, независимое от будущих переименований каталога.</summary>
    public required string Name { get; init; }
    /// <summary>Упражнения в исходном порядке.</summary>
    public required List<TemplateExerciseData> Exercises { get; init; }
}

/// <summary>Полный план Core с расписанием, выбором мышц и вариациями.</summary>
public sealed record TemplateData
{
    /// <summary>Стабильный UUID из Core.</summary>
    public required Guid Id { get; init; }
    /// <summary>Сохранённое имя, независимое от будущих переименований каталога.</summary>
    public required string Name { get; init; }
    /// <summary>Упражнения в исходном порядке.</summary>
    public required List<TemplateExerciseData> Exercises { get; init; }
    /// <summary>Настроенная длительность отдыха в секундах.</summary>
    public required int RestSeconds { get; init; }
    /// <summary>Выбранные группы мышц в каноническом порядке.</summary>
    public required List<string> MuscleGroups { get; init; }
    /// <summary>Выбранные мышцы в каноническом порядке.</summary>
    public required List<string> Muscles { get; init; }
    /// <summary>Выбранные области мышц в каноническом порядке.</summary>
    public required List<string> MuscleRegions { get; init; }
    /// <summary>Дни расписания Core: воскресенье = 1, суббота = 7.</summary>
    public required List<int> PreferredWeekdays { get; init; }
    /// <summary>Именованные варианты плана в пользовательском порядке.</summary>
    public required List<TemplateVariationData> Variations { get; init; }
    /// <summary>Необязательное имя первого списка упражнений.</summary>
    public string? BaseVariationName { get; init; }
}

/// <summary>Замер веса в килограммах с необязательной связью с тренировкой.</summary>
public sealed record BodyWeightData
{
    /// <summary>Стабильный UUID из Core.</summary>
    public required Guid Id { get; init; }
    /// <summary>Дата замера в Unix seconds с дробной точностью.</summary>
    public required double MeasuredAt { get; init; }
    /// <summary>Вес в килограммах; ноль означает отсутствие добавленного веса.</summary>
    public required double WeightKG { get; init; }
    /// <summary>UUID связанной тренировки; связь замера может пережить её удаление.</summary>
    public Guid? WorkoutID { get; init; }
}

/// <summary>Одно измерение пульса; время и BPM сохраняют дробную точность.</summary>
public sealed record HeartRateReadingData
{
    /// <summary>Дата измерения в Unix seconds с дробной точностью.</summary>
    public required double Date { get; init; }
    /// <summary>Измеренный пульс в BPM, от 1 до 300.</summary>
    public required double BeatsPerMinute { get; init; }
}

/// <summary>Сохранённый пульс с режимом, источником и упорядоченными измерениями.</summary>
public sealed record HeartRateData
{
    /// <summary>Текущая версия структуры записи пульса Core.</summary>
    public required int SchemaVersion { get; init; }
    /// <summary>UUID родительской тренировки; пульс удаляется вместе с ней.</summary>
    public required Guid WorkoutID { get; init; }
    /// <summary>Режим получения пульса: appleHealth или bluetooth.</summary>
    public required string Mode { get; init; }
    /// <summary>Необязательный источник liveHealthKit для живого приёма Apple Health.</summary>
    public string? Origin { get; init; }
    /// <summary>Строго упорядоченные измерения пульса; до 10 000 на тренировку.</summary>
    public required List<HeartRateReadingData> Readings { get; init; }
}

/// <summary>Единые строгие правила wire JSON; неизвестные поля не теряются при записи.</summary>
internal static class TrainingJson
{
    internal static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false,
        AllowDuplicateProperties = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        NumberHandling = JsonNumberHandling.Strict,
        RespectNullableAnnotations = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        MaxDepth = 32
    };

    /// <summary>Строго декодирует проверяемый DTO, отклоняя неизвестные и отсутствующие поля.</summary>
    internal static T Read<T>(JsonElement value) => value.Deserialize<T>(Options)
        ?? throw new TrainingException(400, "invalid_training_data");
    /// <summary>Сериализует DTO с едиными wire-правилами без HTML-экранирования.</summary>
    internal static JsonElement Element<T>(T value) => JsonSerializer.SerializeToElement(value, Options);
}

/// <summary>Ожидаемый безопасный отказ API; текущая версия возвращается при конфликте.</summary>
public sealed class TrainingException(int status, string code, TrainingChange? current = null) : Exception(code)
{
    /// <summary>HTTP status ожидаемого отказа API.</summary>
    public int Status { get; } = status;
    /// <summary>Машинный код ожидаемого отказа без пользовательских данных.</summary>
    public string Code { get; } = code;
    /// <summary>Текущая серверная версия при конфликте либо null.</summary>
    public TrainingChange? Current { get; } = current;
}
