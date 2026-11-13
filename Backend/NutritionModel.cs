using Microsoft.EntityFrameworkCore;

namespace FitLife.Backend;

/// <summary>Структурированная строка NutritionFood, изолированная владельцем.</summary>
public sealed class NutritionFood
{
    /// <summary>UUID владельца из проверенного JWT; часть составного ключа.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Тип агрегата change feed; не вид добавки.</summary>
    public string Kind { get; set; } = "";
    /// <summary>Стабильный UUID агрегата Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Дата события в Unix seconds с дробной точностью.</summary>
    public double Date { get; set; }
    /// <summary>Приём пищи: breakfast, lunch, dinner или snack.</summary>
    public string Meal { get; set; } = "";
    /// <summary>Название записи питания.</summary>
    public string Title { get; set; } = "";
    /// <summary>Пользовательская заметка, до 2000 символов.</summary>
    public string Note { get; set; } = "";
    /// <summary>Очищенный JPEG до 600000 байт; null при отсутствии фотографии.</summary>
    public byte[]? Photo { get; set; }
    /// <summary>Запись также доступна как сохранённое блюдо.</summary>
    public bool IsSavedMeal { get; set; }
}

/// <summary>Структурированная строка NutritionWater, изолированная владельцем.</summary>
public sealed class NutritionWater
{
    /// <summary>UUID владельца из проверенного JWT; часть составного ключа.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Тип агрегата change feed; не вид добавки.</summary>
    public string Kind { get; set; } = "";
    /// <summary>Стабильный UUID агрегата Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Дата события в Unix seconds с дробной точностью.</summary>
    public double Date { get; set; }
    /// <summary>Объём выпитой воды в мл.</summary>
    public double Milliliters { get; set; }
}

/// <summary>Структурированная строка NutritionDose, изолированная владельцем.</summary>
public sealed class NutritionDose
{
    /// <summary>UUID владельца из проверенного JWT; часть составного ключа.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Тип агрегата change feed; не вид добавки.</summary>
    public string Kind { get; set; } = "";
    /// <summary>Стабильный UUID агрегата Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Текущая версия модели приёма — 1.</summary>
    public int SchemaVersion { get; set; }
    /// <summary>Дата события в Unix seconds с дробной точностью.</summary>
    public double Date { get; set; }
    /// <summary>Вид добавки: creatine, protein, massGainer или other.</summary>
    public string SupplementKind { get; set; } = "";
    /// <summary>Сохранённое название продукта или добавки.</summary>
    public string Name { get; set; } = "";
    /// <summary>Количество в сохранённых единицах; у избранного null.</summary>
    public double Amount { get; set; }
    /// <summary>Единица количества из контракта Core.</summary>
    public string Unit { get; set; } = "";
    /// <summary>Включён ли учёт состава в дневных итогах.</summary>
    public bool IncludesNutrition { get; set; }
    /// <summary>Пользовательская заметка, до 2000 символов.</summary>
    public string Note { get; set; } = "";
    /// <summary>Исторический UUID расписания без каскадной связи.</summary>
    public Guid? PlanID { get; set; }
    /// <summary>Исходный слот расписания в Unix seconds; null для ручного приёма.</summary>
    public double? ScheduledFor { get; set; }
    /// <summary>Калории в ккал на базовое количество; у профиля — дневная цель.</summary>
    public double? Calories { get; set; }
    /// <summary>Белки в граммах на базовое количество; у профиля — дневная цель.</summary>
    public double? Protein { get; set; }
    /// <summary>Жиры в граммах на базовое количество; у профиля — дневная цель.</summary>
    public double? Fat { get; set; }
    /// <summary>Углеводы в граммах на базовое количество; у профиля — дневная цель.</summary>
    public double? Carbohydrates { get; set; }
}

/// <summary>Структурированная строка NutritionPlan, изолированная владельцем.</summary>
public sealed class NutritionPlan
{
    /// <summary>UUID владельца из проверенного JWT; часть составного ключа.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Тип агрегата change feed; не вид добавки.</summary>
    public string Kind { get; set; } = "";
    /// <summary>Стабильный UUID агрегата Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Периодичность: daily, weekdays или intervalDays.</summary>
    public string Recurrence { get; set; } = "";
    /// <summary>Интервал календарных дней, от 1 до 365.</summary>
    public int IntervalDays { get; set; }
    /// <summary>Дата начала расписания в Unix seconds.</summary>
    public double StartDate { get; set; }
    /// <summary>Последний включённый календарный день, либо null.</summary>
    public double? EndDate { get; set; }
    /// <summary>Сохранённый часовой пояс IANA для расписания.</summary>
    public string TimeZoneID { get; set; } = "";
    /// <summary>Расписание активно; выключение сохраняет историю.</summary>
    public bool Enabled { get; set; }
    /// <summary>Пользователь запросил напоминания; разрешение ОС остаётся на устройстве.</summary>
    public bool RemindersEnabled { get; set; }
    /// <summary>Малый упорядоченный список дней недели Calendar, 1–7.</summary>
    public string WeekdaysJson { get; set; } = "";
    /// <summary>Малый упорядоченный список минут от полуночи, до 8 времён.</summary>
    public string TimesJson { get; set; } = "";
}

/// <summary>Структурированная строка NutritionProfileRow, изолированная владельцем.</summary>
public sealed class NutritionProfileRow
{
    /// <summary>UUID владельца из проверенного JWT; часть составного ключа.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Тип агрегата change feed; не вид добавки.</summary>
    public string Kind { get; set; } = "";
    /// <summary>Стабильный UUID агрегата Core.</summary>
    public Guid Id { get; set; }
    /// <summary>Калории в ккал на базовое количество; у профиля — дневная цель.</summary>
    public double? Calories { get; set; }
    /// <summary>Белки в граммах на базовое количество; у профиля — дневная цель.</summary>
    public double? Protein { get; set; }
    /// <summary>Жиры в граммах на базовое количество; у профиля — дневная цель.</summary>
    public double? Fat { get; set; }
    /// <summary>Углеводы в граммах на базовое количество; у профиля — дневная цель.</summary>
    public double? Carbohydrates { get; set; }
    /// <summary>Необязательная дневная цель воды в мл.</summary>
    public double? WaterMilliliters { get; set; }
}

/// <summary>Структурированная строка NutritionProduct, изолированная владельцем.</summary>
public sealed class NutritionProduct
{
    /// <summary>UUID владельца из проверенного JWT; часть составного ключа.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Тип агрегата change feed; не вид добавки.</summary>
    public string Kind { get; set; } = "";
    /// <summary>UUID родительской записи питания или профиля.</summary>
    public Guid AggregateId { get; set; }
    /// <summary>Позиция снимка продукта в исходном списке.</summary>
    public int Position { get; set; }
    /// <summary>UUID порции; у избранного null.</summary>
    public Guid? PortionId { get; set; }
    /// <summary>Количество в сохранённых единицах; у избранного null.</summary>
    public double? Amount { get; set; }
    /// <summary>Строковый идентификатор исторического продукта.</summary>
    public string ProductId { get; set; } = "";
    /// <summary>Сохранённое название продукта или добавки.</summary>
    public string Name { get; set; } = "";
    /// <summary>Бренд исторического продукта.</summary>
    public string Brand { get; set; } = "";
    /// <summary>Единица количества из контракта Core.</summary>
    public string Unit { get; set; } = "";
    /// <summary>Необязательная ссылка на изображение продукта.</summary>
    public string? ImageURL { get; set; }
    /// <summary>Необязательная ссылка на источник сведений.</summary>
    public string? SourceURL { get; set; }
    /// <summary>Необязательный штрихкод продукта.</summary>
    public string? Barcode { get; set; }
    /// <summary>Калории в ккал на базовое количество; у профиля — дневная цель.</summary>
    public double Calories { get; set; }
    /// <summary>Белки в граммах на базовое количество; у профиля — дневная цель.</summary>
    public double Protein { get; set; }
    /// <summary>Жиры в граммах на базовое количество; у профиля — дневная цель.</summary>
    public double Fat { get; set; }
    /// <summary>Углеводы в граммах на базовое количество; у профиля — дневная цель.</summary>
    public double Carbohydrates { get; set; }
}

/// <summary>Составные ключи и каскады питания; история приёмов не зависит от существования расписания.</summary>
internal static class NutritionModel
{
    /// <summary>Настраивает нормализованные таблицы питания без изменения существующих журналов.</summary>
    internal static void Configure(ModelBuilder builder)
    {
        builder.Entity<NutritionFood>().ToTable("NutritionFood");
        builder.Entity<NutritionFood>().HasKey(x => new { x.OwnerId, x.Kind, x.Id });
        builder.Entity<NutritionFood>()
            .HasOne<TrainingRecordMetadata>()
            .WithMany()
            .HasForeignKey(x => new { x.OwnerId, x.Kind, x.Id })
            .OnDelete(DeleteBehavior.Cascade);
        builder.Entity<NutritionFood>().Property(x => x.OwnerId).HasMaxLength(36);
        builder.Entity<NutritionFood>().Property(x => x.Kind).HasMaxLength(16);
        builder.Entity<NutritionWater>().ToTable("NutritionWater");
        builder.Entity<NutritionWater>().HasKey(x => new { x.OwnerId, x.Kind, x.Id });
        builder.Entity<NutritionWater>()
            .HasOne<TrainingRecordMetadata>()
            .WithMany()
            .HasForeignKey(x => new { x.OwnerId, x.Kind, x.Id })
            .OnDelete(DeleteBehavior.Cascade);
        builder.Entity<NutritionWater>().Property(x => x.OwnerId).HasMaxLength(36);
        builder.Entity<NutritionWater>().Property(x => x.Kind).HasMaxLength(16);
        builder.Entity<NutritionDose>().ToTable("NutritionDose");
        builder.Entity<NutritionDose>().HasKey(x => new { x.OwnerId, x.Kind, x.Id });
        builder.Entity<NutritionDose>()
            .HasOne<TrainingRecordMetadata>()
            .WithMany()
            .HasForeignKey(x => new { x.OwnerId, x.Kind, x.Id })
            .OnDelete(DeleteBehavior.Cascade);
        builder.Entity<NutritionDose>().Property(x => x.OwnerId).HasMaxLength(36);
        builder.Entity<NutritionDose>().Property(x => x.Kind).HasMaxLength(16);
        builder.Entity<NutritionPlan>().ToTable("NutritionPlan");
        builder.Entity<NutritionPlan>().HasKey(x => new { x.OwnerId, x.Kind, x.Id });
        builder.Entity<NutritionPlan>()
            .HasOne<TrainingRecordMetadata>()
            .WithMany()
            .HasForeignKey(x => new { x.OwnerId, x.Kind, x.Id })
            .OnDelete(DeleteBehavior.Cascade);
        builder.Entity<NutritionPlan>().Property(x => x.OwnerId).HasMaxLength(36);
        builder.Entity<NutritionPlan>().Property(x => x.Kind).HasMaxLength(16);
        builder.Entity<NutritionProfileRow>().ToTable("NutritionProfileRow");
        builder.Entity<NutritionProfileRow>().HasKey(x => new { x.OwnerId, x.Kind, x.Id });
        builder.Entity<NutritionProfileRow>()
            .HasOne<TrainingRecordMetadata>()
            .WithMany()
            .HasForeignKey(x => new { x.OwnerId, x.Kind, x.Id })
            .OnDelete(DeleteBehavior.Cascade);
        builder.Entity<NutritionProfileRow>().Property(x => x.OwnerId).HasMaxLength(36);
        builder.Entity<NutritionProfileRow>().Property(x => x.Kind).HasMaxLength(16);
        builder.Entity<NutritionProduct>().ToTable("NutritionProduct");
        builder.Entity<NutritionProduct>().HasKey(x => new { x.OwnerId, x.Kind, x.AggregateId, x.Position });
        builder.Entity<NutritionProduct>()
            .HasOne<TrainingRecordMetadata>()
            .WithMany()
            .HasForeignKey(x => new { x.OwnerId, x.Kind, x.AggregateId })
            .OnDelete(DeleteBehavior.Cascade);
        builder.Entity<NutritionProduct>().Property(x => x.OwnerId).HasMaxLength(36);
        builder.Entity<NutritionProduct>().Property(x => x.Kind).HasMaxLength(16);
        builder.Entity<NutritionFood>().HasIndex(x => new { x.OwnerId, x.Date });
        builder.Entity<NutritionDose>().HasIndex(x => new { x.OwnerId, x.Date });
    }
}
