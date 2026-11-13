namespace FitLife.Backend;

/// <summary>Типизированный контракт NutrientsData для синхронизации питания Core.</summary>
public sealed record NutrientsData
{
    /// <summary>Калории в ккал.</summary>
    public required double Calories { get; init; }
    /// <summary>Белки в граммах.</summary>
    public required double Protein { get; init; }
    /// <summary>Жиры в граммах.</summary>
    public required double Fat { get; init; }
    /// <summary>Углеводы в граммах.</summary>
    public required double Carbohydrates { get; init; }
}

/// <summary>Типизированный контракт FoodProductData для синхронизации питания Core.</summary>
public sealed record FoodProductData
{
    /// <summary>Идентификатор продукта.</summary>
    public required string Id { get; init; }
    /// <summary>Название продукта.</summary>
    public required string Name { get; init; }
    /// <summary>Бренд продукта.</summary>
    public required string Brand { get; init; }
    /// <summary>Единица массы или объёма.</summary>
    public required string Unit { get; init; }
    /// <summary>Состав на 100 г или мл.</summary>
    public required NutrientsData Per100Units { get; init; }
    /// <summary>Ссылка на изображение.</summary>
    public string? ImageURL { get; init; }
    /// <summary>Источник сведений.</summary>
    public string? SourceURL { get; init; }
    /// <summary>Сохранённый штрихкод.</summary>
    public string? Barcode { get; init; }
}

/// <summary>Типизированный контракт FoodPortionData для синхронизации питания Core.</summary>
public sealed record FoodPortionData
{
    /// <summary>UUID порции.</summary>
    public required Guid Id { get; init; }
    /// <summary>Исторический снимок продукта.</summary>
    public required FoodProductData Product { get; init; }
    /// <summary>Размер порции в единицах продукта.</summary>
    public required double Amount { get; init; }
}

/// <summary>Типизированный контракт FoodEntryData для синхронизации питания Core.</summary>
public sealed record FoodEntryData
{
    /// <summary>UUID записи питания.</summary>
    public required Guid Id { get; init; }
    /// <summary>Дата в Unix seconds.</summary>
    public required double Date { get; init; }
    /// <summary>Приём пищи.</summary>
    public required string Meal { get; init; }
    /// <summary>Название записи.</summary>
    public required string Title { get; init; }
    /// <summary>Порции в исходном порядке.</summary>
    public required List<FoodPortionData> Portions { get; init; }
    /// <summary>Заметка пользователя.</summary>
    public required string Note { get; init; }
    /// <summary>Очищенный JPEG до 600000 байт.</summary>
    public byte[]? Photo { get; init; }
    /// <summary>Сохранённый рецепт.</summary>
    public required bool IsSavedMeal { get; init; }
}

/// <summary>Типизированный контракт WaterEntryData для синхронизации питания Core.</summary>
public sealed record WaterEntryData
{
    /// <summary>UUID записи воды.</summary>
    public required Guid Id { get; init; }
    /// <summary>Дата в Unix seconds.</summary>
    public required double Date { get; init; }
    /// <summary>Объём в мл.</summary>
    public required double Milliliters { get; init; }
}

/// <summary>Типизированный контракт SupplementEntryData для синхронизации питания Core.</summary>
public sealed record SupplementEntryData
{
    /// <summary>UUID приёма.</summary>
    public required Guid Id { get; init; }
    /// <summary>Версия модели приёма.</summary>
    public required int SchemaVersion { get; init; }
    /// <summary>Фактическая дата в Unix seconds.</summary>
    public required double Date { get; init; }
    /// <summary>Вид добавки.</summary>
    public required string Kind { get; init; }
    /// <summary>Название добавки.</summary>
    public required string Name { get; init; }
    /// <summary>Фактически принятое количество.</summary>
    public required double Amount { get; init; }
    /// <summary>Единицы количества.</summary>
    public required string Unit { get; init; }
    /// <summary>Учитывать состав в итогах питания.</summary>
    public required bool IncludesNutrition { get; init; }
    /// <summary>Состав на базовое количество выбранной единицы.</summary>
    public NutrientsData? NutritionPerBasis { get; init; }
    /// <summary>Заметка.</summary>
    public required string Note { get; init; }
    /// <summary>Историческая ссылка на расписание, без каскадного удаления.</summary>
    public Guid? PlanID { get; init; }
    /// <summary>Запланированное время в Unix seconds.</summary>
    public double? ScheduledFor { get; init; }
}

/// <summary>Типизированный контракт SupplementPlanData для синхронизации питания Core.</summary>
public sealed record SupplementPlanData
{
    /// <summary>UUID расписания.</summary>
    public required Guid Id { get; init; }
    /// <summary>Параметры дозы, введённые пользователем.</summary>
    public required SupplementEntryData Prototype { get; init; }
    /// <summary>Периодичность.</summary>
    public required string Recurrence { get; init; }
    /// <summary>Интервал календарных дней.</summary>
    public required int IntervalDays { get; init; }
    /// <summary>Дни недели Calendar от 1 до 7.</summary>
    public required List<int> Weekdays { get; init; }
    /// <summary>Минуты от полуночи, по возрастанию.</summary>
    public required List<int> Times { get; init; }
    /// <summary>Дата начала в Unix seconds.</summary>
    public required double StartDate { get; init; }
    /// <summary>Необязательная дата окончания.</summary>
    public double? EndDate { get; init; }
    /// <summary>Часовой пояс IANA.</summary>
    public required string TimeZoneID { get; init; }
    /// <summary>Включено расписание.</summary>
    public required bool Enabled { get; init; }
    /// <summary>Пользователь включил напоминания.</summary>
    public required bool RemindersEnabled { get; init; }
}

/// <summary>Типизированный контракт NutritionGoalData для синхронизации питания Core.</summary>
public sealed record NutritionGoalData
{
    /// <summary>Цель калорий в ккал.</summary>
    public required double Calories { get; init; }
    /// <summary>Цель белков в граммах.</summary>
    public double? Protein { get; init; }
    /// <summary>Цель жиров в граммах.</summary>
    public double? Fat { get; init; }
    /// <summary>Цель углеводов в граммах.</summary>
    public double? Carbohydrates { get; init; }
    /// <summary>Цель воды в мл.</summary>
    public double? WaterMilliliters { get; init; }
}

/// <summary>Типизированный контракт NutritionProfileData для синхронизации питания Core.</summary>
public sealed record NutritionProfileData
{
    /// <summary>Фиксированный UUID профиля питания.</summary>
    public required Guid Id { get; init; }
    /// <summary>Цели питания.</summary>
    public NutritionGoalData? Goal { get; init; }
    /// <summary>Избранные продукты, отсортированные по ID.</summary>
    public required List<FoodProductData> Favorites { get; init; }
}
