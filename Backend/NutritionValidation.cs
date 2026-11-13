using System.Globalization;
using System.Text.Json;

namespace FitLife.Backend;

/// <summary>Проверяет все поля питания и расписаний по правилам Swift Core.</summary>
internal static class NutritionValidation
{
    internal static readonly Guid ProfileId = Guid.Parse("9e0850af-6d21-54e8-9eef-e022282e9c05");

    /// <summary>Возвращает проверенный канонический DTO; отсутствующий состав не заменяется нулями.</summary>
    internal static JsonElement Canonical(string kind, Guid id, JsonElement value)
    {
        switch (kind)
        {
            case TrainingKinds.FoodEntry:
                var food = TrainingJson.Read<FoodEntryData>(value);
                Check(food.Id == id && Finite(food.Date) && Text(food.Title, 300, true) && Text(food.Note, 2000));
                Check(food.Meal is "breakfast" or "lunch" or "dinner" or "snack");
                Check(food.Portions is not null && food.Portions.Count <= 100 && food.Portions.All(x => x is not null));
                Check(food.Portions!.Select(x => x.Id).Distinct().Count() == food.Portions.Count);
                Check(food.Portions.Count > 0 || food.Photo is not null);
                if (food.Photo is { } photo) Check(photo.Length is >= 3 and <= 600_000 && photo[0] == 255 && photo[1] == 216 && photo[2] == 255);
                foreach (var portion in food.Portions)
                {
                    Product(portion.Product);
                    Check(Positive(portion.Amount, 10_000));
                }
                return TrainingJson.Element(food);
            case TrainingKinds.WaterEntry:
                var water = TrainingJson.Read<WaterEntryData>(value);
                Check(water.Id == id && Finite(water.Date) && Positive(water.Milliliters, 10_000));
                return TrainingJson.Element(water);
            case TrainingKinds.SupplementEntry:
                var dose = TrainingJson.Read<SupplementEntryData>(value);
                Check(dose.Id == id);
                Dose(dose);
                return TrainingJson.Element(dose);
            case TrainingKinds.SupplementPlan:
                var plan = TrainingJson.Read<SupplementPlanData>(value);
                Check(plan.Id == id && plan.Prototype is not null && plan.Prototype.Id == id);
                Dose(plan.Prototype!);
                Check(plan.Prototype!.PlanID is null && plan.Prototype.ScheduledFor is null);
                Check(plan.Recurrence is "daily" or "weekdays" or "intervalDays");
                Check(plan.IntervalDays is >= 1 and <= 365);
                Check(plan.Times is not null && plan.Times.Count is >= 1 and <= 8 && plan.Times.All(x => x is >= 0 and < 1440));
                Check(plan.Times!.SequenceEqual(plan.Times.Distinct().Order()));
                Check(plan.Weekdays is not null && plan.Weekdays.All(x => x is >= 1 and <= 7));
                Check(plan.Weekdays!.SequenceEqual(plan.Weekdays.Distinct().Order()));
                Check(plan.Recurrence != "weekdays" || plan.Weekdays.Count > 0);
                Check(Finite(plan.StartDate) && (plan.EndDate is null || Finite(plan.EndDate.Value) && plan.EndDate >= plan.StartDate));
                Check(plan.TimeZoneID is not null && plan.TimeZoneID.Length <= 100);
                try { _ = TimeZoneInfo.FindSystemTimeZoneById(plan.TimeZoneID!); }
                catch (TimeZoneNotFoundException) { throw new TrainingException(400, "invalid_training_data"); }
                catch (InvalidTimeZoneException) { throw new TrainingException(400, "invalid_training_data"); }
                return TrainingJson.Element(plan);
            case TrainingKinds.NutritionProfile:
                var profile = TrainingJson.Read<NutritionProfileData>(value);
                Check(id == ProfileId && profile.Id == id);
                if (profile.Goal is { } goal)
                {
                    Check(Positive(goal.Calories, 20_000));
                    Check(new[] { goal.Protein, goal.Fat, goal.Carbohydrates }.All(x => x is null || Positive(x.Value, 2000)));
                    Check(goal.WaterMilliliters is null || Positive(goal.WaterMilliliters.Value, 10_000));
                }
                Check(profile.Favorites is not null && profile.Favorites.Count <= 500 && profile.Favorites.All(x => x is not null));
                foreach (var product in profile.Favorites!) Product(product);
                Check(profile.Favorites!.Select(x => x.Id).Distinct(StringComparer.Ordinal).Count() == profile.Favorites.Count);
                Check(profile.Favorites.Select(x => x.Id).SequenceEqual(profile.Favorites.Select(x => x.Id).Order(StringComparer.Ordinal)));
                return TrainingJson.Element(profile);
            default: throw new TrainingException(400, "invalid_training_kind");
        }
    }

    /// <summary>Проверяет дозу и состав относительно выбранной единицы, без рекомендаций дозировки.</summary>
    private static void Dose(SupplementEntryData value)
    {
        Check(value.SchemaVersion == 1 && Finite(value.Date));
        Check(value.Kind is "creatine" or "protein" or "massGainer" or "other");
        Check(Text(value.Name, 300, value.Kind == "other") && Text(value.Note, 2000));
        Check(value.Unit is "grams" or "milligrams" or "milliliters" or "servings" or "capsules" or "tablets");
        Check(Positive(value.Amount, value.Unit == "milligrams" ? 10_000_000 : 10_000));
        Check(value.IncludesNutrition || value.NutritionPerBasis is null);
        Check((value.PlanID is null) == (value.ScheduledFor is null));
        Check(value.ScheduledFor is null || Finite(value.ScheduledFor.Value));
        if (value.NutritionPerBasis is not { } nutrients) return;
        if (value.Unit == "milligrams") Nutrients(new NutrientsData
        { Calories = nutrients.Calories * 100, Protein = nutrients.Protein * 100, Fat = nutrients.Fat * 100, Carbohydrates = nutrients.Carbohydrates * 100 }, "grams");
        else if (value.Unit is "grams" or "milliliters") Nutrients(nutrients, value.Unit);
        else
        {
            Check(new[] { nutrients.Calories, nutrients.Protein, nutrients.Fat, nutrients.Carbohydrates }.All(x => Finite(x) && x >= 0));
            Check(nutrients.Calories <= 10_000 && nutrients.Protein + nutrients.Fat + nutrients.Carbohydrates <= 1000);
        }
    }

    /// <summary>Проверяет исторический продукт и его состав.</summary>
    private static void Product(FoodProductData value)
    {
        Check(value is not null);
        Check(Text(value!.Id, 100, true) && Text(value.Name, 300, true) && Text(value.Brand, 300));
        Check(value.Unit is "grams" or "milliliters");
        Nutrients(value.Per100Units, value.Unit);
    }
    /// <summary>Проверяет конечный неотрицательный состав на 100 единиц.</summary>
    private static void Nutrients(NutrientsData value, string unit)
    {
        Check(value is not null);
        var mass = unit == "grams" ? 100.0 : 1000.0;
        Check(new[] { value!.Calories, value.Protein, value.Fat, value.Carbohydrates }.All(x => Finite(x) && x >= 0));
        Check(value.Calories <= mass * 10 && value.Protein <= mass && value.Fat <= mass && value.Carbohydrates <= mass);
        Check(value.Protein + value.Fat + value.Carbohydrates <= mass * 1.05);
    }
    /// <summary>Проверяет длину в пользовательских символах и обязательное имя.</summary>
    private static bool Text(string value, int maximum, bool required = false) => value is not null && new StringInfo(value).LengthInTextElements <= maximum && (!required || value.Trim().Length > 0);
    /// <summary>Проверяет положительное конечное количество.</summary>
    private static bool Positive(double value, double maximum) => Finite(value) && value > 0 && value <= maximum;
    /// <summary>Проверяет конечность числа.</summary>
    private static bool Finite(double value) => double.IsFinite(value);
    /// <summary>Возвращает безопасный HTTP 400 при нарушении правил модели.</summary>
    private static void Check([System.Diagnostics.CodeAnalysis.DoesNotReturnIf(false)] bool valid) { if (!valid) throw new TrainingException(400, "invalid_training_data"); }
}
