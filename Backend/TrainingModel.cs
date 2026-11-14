using Microsoft.EntityFrameworkCore;

namespace FitLife.Backend;

/// <summary>Владелец журнала и монотонный счётчик его серверных версий.</summary>
public sealed class TrainingOwner
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Монотонная версия записи в пределах владельца.</summary>
    public long Revision { get; set; }
    /// <summary>UUID однократно перенесённого полного архива; исходный архив сохраняется.</summary>
    public Guid? ImportedBackupId { get; set; }
}

/// <summary>Версия, контрольный хеш и признак удаления одного агрегата владельца.</summary>
public sealed class TrainingRecordMetadata
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Текущий тип агрегата журнала.</summary>
    public string Kind { get; set; } = "";
    /// <summary>Стабильный UUID из Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Монотонная версия записи в пределах владельца.</summary>
    public long Revision { get; set; }
    /// <summary>Признак tombstone, распространяющего офлайн-удаление.</summary>
    public bool Deleted { get; set; }
    /// <summary>SHA-256 канонического значения для идемпотентного повтора записи.</summary>
    public string Hash { get; set; } = "";
}

/// <summary>Личная связь упражнения с каталогом, изолированная владельцем.</summary>
public sealed class TrainingExerciseLink
{
    /// <summary>Владелец записи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Тип синхронизируемой записи.</summary>
    public string Kind { get; set; } = TrainingKinds.ExerciseLink;
    /// <summary>UUID пользовательского упражнения.</summary>
    public Guid Id { get; set; }
    /// <summary>UUID упражнения каталога.</summary>
    public Guid CatalogID { get; set; }
}

/// <summary>Состояние тренировки; упражнения и подходы хранятся в зависимых таблицах.</summary>
public sealed class TrainingWorkout
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Текущий тип агрегата журнала.</summary>
    public string Kind { get; set; } = TrainingKinds.Workout;
    /// <summary>Стабильный UUID из Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Сохранённое имя, независимое от будущих переименований каталога.</summary>
    public string Name { get; set; } = "";
    /// <summary>Начало события в Unix seconds с дробной точностью.</summary>
    public double StartedAt { get; set; }
    /// <summary>Завершение события в Unix seconds; null у незавершённой тренировки.</summary>
    public double? EndedAt { get; set; }
    /// <summary>Состояние тренировки Core либо безопасный HTTP status ожидаемого отказа.</summary>
    public string Status { get; set; } = "";
    /// <summary>Настроенная длительность отдыха в секундах.</summary>
    public int RestSeconds { get; set; }
    /// <summary>Сохранённая дата окончания текущего отдыха либо null.</summary>
    public double? RestEndsAt { get; set; }
    /// <summary>Начало текущей незавершённой паузы либо null.</summary>
    public double? PausedAt { get; set; }
    /// <summary>Суммарное время завершённых пауз в секундах.</summary>
    public double PausedSeconds { get; set; }
    /// <summary>Заметка тренировки; пустая строка сохраняется.</summary>
    public string Notes { get; set; } = "";
    /// <summary>Явно записанный вес тела; не вычисляется из замеров.</summary>
    public double? BodyWeightKG { get; set; }
    /// <summary>False у импорта с неизвестной длительностью; null сохраняется.</summary>
    public bool? DurationIsKnown { get; set; }
    /// <summary>Завершённые интервалы пауз в исходном порядке.</summary>
    public List<TrainingPause> Pauses { get; set; } = [];
}

/// <summary>Завершённый интервал паузы в исходном порядке тренировки.</summary>
public sealed class TrainingPause
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>UUID родительской тренировки в том же аккаунте.</summary>
    public Guid WorkoutId { get; set; }
    /// <summary>Позиция дочерней записи в исходном списке, начиная с нуля.</summary>
    public int Position { get; set; }
    /// <summary>Начало события в Unix seconds с дробной точностью.</summary>
    public double StartedAt { get; set; }
    /// <summary>Завершение события в Unix seconds; null у незавершённой тренировки.</summary>
    public double EndedAt { get; set; }
}

/// <summary>Снимок упражнения сохраняет историческое имя независимо от изменений каталога.</summary>
public sealed class TrainingExercise
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Текущий тип агрегата журнала.</summary>
    public string Kind { get; set; } = "";
    /// <summary>UUID родительской тренировки или плана.</summary>
    public Guid AggregateId { get; set; }
    /// <summary>Ноль для основного списка, последующие индексы для вариаций.</summary>
    public int VariationIndex { get; set; }
    /// <summary>Позиция дочерней записи в исходном списке, начиная с нуля.</summary>
    public int Position { get; set; }
    /// <summary>Стабильный UUID из Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Стабильный UUID упражнения каталога; историческое имя хранится отдельно.</summary>
    public Guid ExerciseId { get; set; }
    /// <summary>Сохранённое имя, независимое от будущих переименований каталога.</summary>
    public string Name { get; set; } = "";
    /// <summary>Основная группа мышц упражнения в обозначениях Core.</summary>
    public string Muscle { get; set; } = "";
    /// <summary>Исторический текст инструкции упражнения.</summary>
    public string Instructions { get; set; } = "";
    /// <summary>UUID непрерывной группы суперсета либо null.</summary>
    public Guid? SupersetID { get; set; }
    /// <summary>Число запланированных подходов.</summary>
    public int? SetCount { get; set; }
    /// <summary>Количество повторений; ноль допустим для незаполненного подхода.</summary>
    public int? Repetitions { get; set; }
    /// <summary>Вес в килограммах; ноль означает отсутствие добавленного веса.</summary>
    public double? WeightKG { get; set; }
    /// <summary>Необязательный множитель нагрузки, например для парных гантелей.</summary>
    public int? LoadMultiplier { get; set; }
    /// <summary>Сохраняет различие null и индивидуального списка целей.</summary>
    public bool HasPlannedSets { get; set; }
    /// <summary>Подходы в исходном порядке.</summary>
    public List<TrainingSet> Sets { get; set; } = [];
}

/// <summary>Один подход с собственным UUID, целями, выполнением и дроп-этапами.</summary>
public sealed class TrainingSet
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Текущий тип агрегата журнала.</summary>
    public string Kind { get; set; } = "";
    /// <summary>UUID родительской тренировки или плана.</summary>
    public Guid AggregateId { get; set; }
    /// <summary>Ноль для основного списка, последующие индексы для вариаций.</summary>
    public int VariationIndex { get; set; }
    /// <summary>Позиция родительского упражнения в списке.</summary>
    public int ExercisePosition { get; set; }
    /// <summary>Позиция дочерней записи в исходном списке, начиная с нуля.</summary>
    public int Position { get; set; }
    /// <summary>Стабильный UUID из Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Количество повторений; ноль допустим для незаполненного подхода.</summary>
    public int Repetitions { get; set; }
    /// <summary>Вес в килограммах; ноль означает отсутствие добавленного веса.</summary>
    public double WeightKG { get; set; }
    /// <summary>Разминочный подход исключается из рабочего объёма.</summary>
    public bool IsWarmup { get; set; }
    /// <summary>Unix seconds выполнения; null означает невыполненный этап.</summary>
    public double? CompletedAt { get; set; }
    /// <summary>Необязательный множитель нагрузки, например для парных гантелей.</summary>
    public int? LoadMultiplier { get; set; }
    /// <summary>Необязательная пользовательская заметка подхода.</summary>
    public string? Note { get; set; }
    /// <summary>Сохраняет отсутствие необязательного списка дроп-этапов.</summary>
    public bool HasDropStages { get; set; }
    /// <summary>Упорядоченные дополнительные этапы; null сохраняет отсутствие дропсета.</summary>
    public List<TrainingDropStage> DropStages { get; set; } = [];
}

/// <summary>Дополнительный этап дропсета с отдельным временем выполнения.</summary>
public sealed class TrainingDropStage
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Текущий тип агрегата журнала.</summary>
    public string Kind { get; set; } = "";
    /// <summary>UUID родительской тренировки или плана.</summary>
    public Guid AggregateId { get; set; }
    /// <summary>Ноль для основного списка, последующие индексы для вариаций.</summary>
    public int VariationIndex { get; set; }
    /// <summary>Позиция родительского упражнения в списке.</summary>
    public int ExercisePosition { get; set; }
    /// <summary>Позиция родительского подхода.</summary>
    public int SetPosition { get; set; }
    /// <summary>Позиция дочерней записи в исходном списке, начиная с нуля.</summary>
    public int Position { get; set; }
    /// <summary>Стабильный UUID из Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Количество повторений; ноль допустим для незаполненного подхода.</summary>
    public int Repetitions { get; set; }
    /// <summary>Вес в килограммах; ноль означает отсутствие добавленного веса.</summary>
    public double WeightKG { get; set; }
    /// <summary>Unix seconds выполнения; null означает невыполненный этап.</summary>
    public double? CompletedAt { get; set; }
}

/// <summary>План тренировки с расписанием, выбором мышц и независимыми вариациями.</summary>
public sealed class TrainingTemplate
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Текущий тип агрегата журнала.</summary>
    public string Kind { get; set; } = TrainingKinds.Template;
    /// <summary>Стабильный UUID из Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Сохранённое имя, независимое от будущих переименований каталога.</summary>
    public string Name { get; set; } = "";
    /// <summary>Настроенная длительность отдыха в секундах.</summary>
    public int RestSeconds { get; set; }
    /// <summary>Необязательное имя первого списка упражнений.</summary>
    public string? BaseVariationName { get; set; }
    /// <summary>Компактный список выбора групп; граф упражнений хранится отдельными строками.</summary>
    public string MuscleGroupsJson { get; set; } = "[]";
    /// <summary>Компактный список выбранных мышц.</summary>
    public string MusclesJson { get; set; } = "[]";
    /// <summary>Компактный список выбранных областей мышц.</summary>
    public string MuscleRegionsJson { get; set; } = "[]";
    /// <summary>Компактный список дней расписания Core.</summary>
    public string PreferredWeekdaysJson { get; set; } = "[]";
    /// <summary>Именованные варианты плана в пользовательском порядке.</summary>
    public List<TrainingVariation> Variations { get; set; } = [];
}

/// <summary>Именованная вариация плана; исходный порядок сохраняется.</summary>
public sealed class TrainingVariation
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>UUID родительского плана в том же аккаунте.</summary>
    public Guid TemplateId { get; set; }
    /// <summary>Позиция дочерней записи в исходном списке, начиная с нуля.</summary>
    public int Position { get; set; }
    /// <summary>Стабильный UUID из Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Сохранённое имя, независимое от будущих переименований каталога.</summary>
    public string Name { get; set; } = "";
}

/// <summary>Самостоятельный замер веса; ссылка на удалённую тренировку допустима.</summary>
public sealed class TrainingBodyWeight
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Текущий тип агрегата журнала.</summary>
    public string Kind { get; set; } = TrainingKinds.BodyWeight;
    /// <summary>Стабильный UUID из Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Дата замера в Unix seconds с дробной точностью.</summary>
    public double MeasuredAt { get; set; }
    /// <summary>Вес в килограммах; ноль означает отсутствие добавленного веса.</summary>
    public double WeightKG { get; set; }
    // Замер может пережить удаление тренировки: это часть действующего контракта Core.
    /// <summary>UUID связанной тренировки; связь замера может пережить её удаление.</summary>
    public Guid? WorkoutID { get; set; }
}

/// <summary>Отдельная запись пульса одной тренировки в том же аккаунте.</summary>
public sealed class TrainingHeartRate
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Текущий тип агрегата журнала.</summary>
    public string Kind { get; set; } = TrainingKinds.HeartRate;
    /// <summary>Стабильный UUID из Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Текущая версия структуры записи пульса Core.</summary>
    public int SchemaVersion { get; set; }
    /// <summary>Режим получения пульса: appleHealth или bluetooth.</summary>
    public string Mode { get; set; } = "";
    /// <summary>Необязательный источник liveHealthKit для живого приёма Apple Health.</summary>
    public string? Origin { get; set; }
    /// <summary>Строго упорядоченные измерения пульса; до 10 000 на тренировку.</summary>
    public List<TrainingHeartRateReading> Readings { get; set; } = [];
}

/// <summary>Измерение пульса с исходной дробной датой и значением.</summary>
public sealed class TrainingHeartRateReading
{
    /// <summary>UUID владельца из проверенного JWT; входит во все ключи и связи.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>UUID родительской тренировки в том же аккаунте.</summary>
    public Guid WorkoutId { get; set; }
    /// <summary>Позиция дочерней записи в исходном списке, начиная с нуля.</summary>
    public int Position { get; set; }
    /// <summary>Дата измерения в Unix seconds с дробной точностью.</summary>
    public double Date { get; set; }
    /// <summary>Измеренный пульс в BPM, от 1 до 300.</summary>
    public double BeatsPerMinute { get; set; }
}

/// <summary>Настраивает составные ключи владельцев, порядок дочерних строк и каскады удаления.</summary>
internal static class TrainingModel
{
    /// <summary>Применяет ключи, индексы и каскады всех нормализованных таблиц журнала.</summary>
    internal static void Configure(ModelBuilder builder)
    {
        builder.Entity<TrainingOwner>().HasKey(x => x.OwnerId);
        builder.Entity<TrainingRecordMetadata>().HasKey(x => new { x.OwnerId, x.Kind, x.Id });
        builder.Entity<TrainingRecordMetadata>().HasIndex(x => new { x.OwnerId, x.Revision }).IsUnique();
        builder.Entity<TrainingRecordMetadata>().Property(x => x.Hash).HasMaxLength(64);
        builder.Entity<TrainingRecordMetadata>().HasOne<TrainingOwner>().WithMany()
            .HasForeignKey(x => x.OwnerId).OnDelete(DeleteBehavior.Cascade);
        foreach (var type in new[] { typeof(TrainingWorkout), typeof(TrainingTemplate), typeof(TrainingBodyWeight), typeof(TrainingHeartRate), typeof(TrainingExerciseLink) })
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
