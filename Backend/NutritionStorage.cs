using System.Text.Json;
using Microsoft.EntityFrameworkCore;

namespace FitLife.Backend;

/// <summary>Преобразует типизированные контракты питания в отдельные строки таблиц и обратно.</summary>
internal static class NutritionStorage
{
    /// <summary>Заменяет граф внутри общей транзакции журнала и проверки CAS.</summary>
    internal static async Task SaveAsync(BackupDbContext db, string owner, string kind, Guid id, JsonElement value, CancellationToken cancellationToken)
    {
        await RemoveAsync(db, owner, kind, id, cancellationToken);
        switch (kind)
        {
            case TrainingKinds.FoodEntry:
                {
                    var data = TrainingJson.Read<FoodEntryData>(value);
                    db.Add(new NutritionFood
                    {
                        OwnerId = owner,
                        Kind = kind,
                        Id = id,
                        Date = data.Date,
                        Meal = data.Meal,
                        Title = data.Title,
                        Note = data.Note,
                        Photo = data.Photo,
                        IsSavedMeal = data.IsSavedMeal,
                    });
                    for (var i = 0; i < data.Portions.Count; i++)
                        db.Add(Product(owner, kind, id, i, data.Portions[i].Product, data.Portions[i].Id, data.Portions[i].Amount));
                    break;
                }
            case TrainingKinds.WaterEntry:
                {
                    var data = TrainingJson.Read<WaterEntryData>(value);
                    db.Add(new NutritionWater
                    {
                        OwnerId = owner,
                        Kind = kind,
                        Id = id,
                        Date = data.Date,
                        Milliliters = data.Milliliters,
                    });
                    break;
                }
            case TrainingKinds.SupplementEntry:
                {
                    var data = TrainingJson.Read<SupplementEntryData>(value);
                    db.Add(Dose(owner, kind, data));
                    break;
                }
            case TrainingKinds.SupplementPlan:
                {
                    var data = TrainingJson.Read<SupplementPlanData>(value);
                    db.Add(new NutritionPlan
                    {
                        OwnerId = owner,
                        Kind = kind,
                        Id = id,
                        Recurrence = data.Recurrence,
                        IntervalDays = data.IntervalDays,
                        StartDate = data.StartDate,
                        EndDate = data.EndDate,
                        TimeZoneID = data.TimeZoneID,
                        Enabled = data.Enabled,
                        RemindersEnabled = data.RemindersEnabled,
                        WeekdaysJson = JsonSerializer.Serialize(data.Weekdays),
                        TimesJson = JsonSerializer.Serialize(data.Times),
                    });
                    db.Add(Dose(owner, kind, data.Prototype));
                    break;
                }
            case TrainingKinds.NutritionProfile:
                {
                    var data = TrainingJson.Read<NutritionProfileData>(value);
                    db.Add(new NutritionProfileRow
                    {
                        OwnerId = owner,
                        Kind = kind,
                        Id = id,
                        Calories = data.Goal?.Calories,
                        Protein = data.Goal?.Protein,
                        Fat = data.Goal?.Fat,
                        Carbohydrates = data.Goal?.Carbohydrates,
                        WaterMilliliters = data.Goal?.WaterMilliliters,
                    });
                    for (var i = 0; i < data.Favorites.Count; i++)
                        db.Add(Product(owner, kind, id, i, data.Favorites[i], null, null));
                    break;
                }
        }
    }

    /// <summary>Удаляет только граф указанного агрегата, оставляя tombstone и исторические ссылки.</summary>
    internal static async Task RemoveAsync(BackupDbContext db, string owner, string kind, Guid id, CancellationToken cancellationToken)
    {
        await db.Set<NutritionFood>().Where(x => x.OwnerId == owner && x.Kind == kind && x.Id == id).ExecuteDeleteAsync(cancellationToken);
        await db.Set<NutritionWater>().Where(x => x.OwnerId == owner && x.Kind == kind && x.Id == id).ExecuteDeleteAsync(cancellationToken);
        await db.Set<NutritionDose>().Where(x => x.OwnerId == owner && x.Kind == kind && x.Id == id).ExecuteDeleteAsync(cancellationToken);
        await db.Set<NutritionPlan>().Where(x => x.OwnerId == owner && x.Kind == kind && x.Id == id).ExecuteDeleteAsync(cancellationToken);
        await db.Set<NutritionProfileRow>().Where(x => x.OwnerId == owner && x.Kind == kind && x.Id == id).ExecuteDeleteAsync(cancellationToken);
        await db.Set<NutritionProduct>().Where(x => x.OwnerId == owner && x.Kind == kind && x.AggregateId == id).ExecuteDeleteAsync(cancellationToken);
    }

    /// <summary>Восстанавливает типизированное значение из согласованного снимка таблиц.</summary>
    internal static async Task<JsonElement> ReadAsync(BackupDbContext db, string owner, string kind, Guid id, CancellationToken cancellationToken)
    {
        switch (kind)
        {
            case TrainingKinds.FoodEntry:
                {
                    var row = await db.Set<NutritionFood>().AsNoTracking().SingleAsync(x => x.OwnerId == owner && x.Kind == kind && x.Id == id, cancellationToken);
                    var products = await db.Set<NutritionProduct>().AsNoTracking().Where(x => x.OwnerId == owner && x.Kind == kind && x.AggregateId == id).OrderBy(x => x.Position).ToListAsync(cancellationToken);
                    return TrainingJson.Element(new FoodEntryData
                    {
                        Id = row.Id,
                        Date = row.Date,
                        Meal = row.Meal,
                        Title = row.Title,
                        Portions = products.Select(x => new FoodPortionData { Id = x.PortionId!.Value, Amount = x.Amount!.Value, Product = ProductValue(x) }).ToList(),
                        Note = row.Note,
                        Photo = row.Photo,
                        IsSavedMeal = row.IsSavedMeal,
                    });
                }
            case TrainingKinds.WaterEntry:
                {
                    var row = await db.Set<NutritionWater>().AsNoTracking().SingleAsync(x => x.OwnerId == owner && x.Kind == kind && x.Id == id, cancellationToken);
                    return TrainingJson.Element(new WaterEntryData
                    {
                        Id = row.Id,
                        Date = row.Date,
                        Milliliters = row.Milliliters,
                    });
                }
            case TrainingKinds.SupplementEntry:
                {
                    var row = await db.Set<NutritionDose>().AsNoTracking().SingleAsync(x => x.OwnerId == owner && x.Kind == kind && x.Id == id, cancellationToken);
                    return TrainingJson.Element(DoseValue(row));
                }
            case TrainingKinds.SupplementPlan:
                {
                    var row = await db.Set<NutritionPlan>().AsNoTracking().SingleAsync(x => x.OwnerId == owner && x.Kind == kind && x.Id == id, cancellationToken);
                    var dose = await db.Set<NutritionDose>().AsNoTracking().SingleAsync(x => x.OwnerId == owner && x.Kind == kind && x.Id == id, cancellationToken);
                    return TrainingJson.Element(new SupplementPlanData
                    {
                        Id = row.Id,
                        Prototype = DoseValue(dose),
                        Recurrence = row.Recurrence,
                        IntervalDays = row.IntervalDays,
                        Weekdays = JsonSerializer.Deserialize<List<int>>(row.WeekdaysJson)!,
                        Times = JsonSerializer.Deserialize<List<int>>(row.TimesJson)!,
                        StartDate = row.StartDate,
                        EndDate = row.EndDate,
                        TimeZoneID = row.TimeZoneID,
                        Enabled = row.Enabled,
                        RemindersEnabled = row.RemindersEnabled,
                    });
                }
            case TrainingKinds.NutritionProfile:
                {
                    var row = await db.Set<NutritionProfileRow>().AsNoTracking().SingleAsync(x => x.OwnerId == owner && x.Kind == kind && x.Id == id, cancellationToken);
                    var products = await db.Set<NutritionProduct>().AsNoTracking().Where(x => x.OwnerId == owner && x.Kind == kind && x.AggregateId == id).OrderBy(x => x.Position).ToListAsync(cancellationToken);
                    return TrainingJson.Element(new NutritionProfileData
                    {
                        Id = row.Id,
                        Goal = row.Calories is null ? null : new NutritionGoalData { Calories = row.Calories!.Value, Protein = row.Protein, Fat = row.Fat, Carbohydrates = row.Carbohydrates, WaterMilliliters = row.WaterMilliliters },
                        Favorites = products.Select(ProductValue).ToList(),
                    });
                }
            default: throw new TrainingException(400, "invalid_training_kind");
        }
    }

    /// <summary>Сохраняет скалярные поля Dose без сериализации агрегата в БД.</summary>
    private static NutritionDose Dose(string owner, string kind, SupplementEntryData data) => new()
    {
        OwnerId = owner,
        Kind = kind,
        Id = data.Id,
        SchemaVersion = data.SchemaVersion,
        Date = data.Date,
        SupplementKind = data.Kind,
        Name = data.Name,
        Amount = data.Amount,
        Unit = data.Unit,
        IncludesNutrition = data.IncludesNutrition,
        Note = data.Note,
        PlanID = data.PlanID,
        ScheduledFor = data.ScheduledFor,
        Calories = data.NutritionPerBasis?.Calories,
        Protein = data.NutritionPerBasis?.Protein,
        Fat = data.NutritionPerBasis?.Fat,
        Carbohydrates = data.NutritionPerBasis?.Carbohydrates,
    };

    /// <summary>Восстанавливает исходные поля Dose, включая необязательные значения.</summary>
    private static SupplementEntryData DoseValue(NutritionDose row) => new()
    {
        Id = row.Id,
        SchemaVersion = row.SchemaVersion,
        Date = row.Date,
        Kind = row.SupplementKind,
        Name = row.Name,
        Amount = row.Amount,
        Unit = row.Unit,
        IncludesNutrition = row.IncludesNutrition,
        NutritionPerBasis = row.Calories is null ? null : new NutrientsData { Calories = row.Calories!.Value, Protein = row.Protein!.Value, Fat = row.Fat!.Value, Carbohydrates = row.Carbohydrates!.Value },
        Note = row.Note,
        PlanID = row.PlanID,
        ScheduledFor = row.ScheduledFor,
    };

    /// <summary>Сохраняет скалярные поля Product без сериализации агрегата в БД.</summary>
    private static NutritionProduct Product(string owner, string kind, Guid id, int position, FoodProductData data, Guid? portionId, double? amount) => new()
    {
        OwnerId = owner,
        Kind = kind,
        AggregateId = id,
        Position = position,
        PortionId = portionId,
        Amount = amount,
        ProductId = data.Id,
        Name = data.Name,
        Brand = data.Brand,
        Unit = data.Unit,
        ImageURL = data.ImageURL,
        SourceURL = data.SourceURL,
        Barcode = data.Barcode,
        Calories = data.Per100Units.Calories,
        Protein = data.Per100Units.Protein,
        Fat = data.Per100Units.Fat,
        Carbohydrates = data.Per100Units.Carbohydrates,
    };

    /// <summary>Восстанавливает исходные поля Product, включая необязательные значения.</summary>
    private static FoodProductData ProductValue(NutritionProduct row) => new()
    {
        Id = row.ProductId,
        Name = row.Name,
        Brand = row.Brand,
        Unit = row.Unit,
        Per100Units = new NutrientsData { Calories = row.Calories, Protein = row.Protein, Fat = row.Fat, Carbohydrates = row.Carbohydrates },
        ImageURL = row.ImageURL,
        SourceURL = row.SourceURL,
        Barcode = row.Barcode,
    };
}
