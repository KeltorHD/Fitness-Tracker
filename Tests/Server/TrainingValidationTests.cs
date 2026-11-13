using System.Text.Json;
using FitLife.Backend;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Сверяет C#-валидацию с граничным корпусом, независимо проверенным настоящим Swift Core.</summary>
[Trait("Category", "Unit")]
public sealed class TrainingValidationTests
{
    private static readonly IReadOnlyDictionary<string, JsonElement> _cases = LoadCases();

    /// <summary>Имена сценариев дают короткий воспроизводимый отчёт, без вывода полного payload в runner.</summary>
    public static IEnumerable<object[]> Cases => _cases.Keys.Select(name => new object[] { name });

    /// <summary>Каждая корректная и ошибочная граница должна иметь тот же результат, что в Core.</summary>
    [Theory]
    [MemberData(nameof(Cases))]
    public void MatchesActualSwiftCoreValidation(string name)
    {
        var scenario = _cases[name];
        var kind = scenario.GetProperty("kind").GetString()!;
        var id = scenario.GetProperty("id").GetGuid();
        var value = scenario.GetProperty("value");
        if (scenario.GetProperty("accepted").GetBoolean())
        {
            var canonical = TrainingValidation.Canonical(kind, id, value);
            Assert.Equal(JsonValueKind.Object, canonical.ValueKind);
            Assert.Equal(id, canonical.GetProperty(kind == TrainingKinds.HeartRate ? "workoutID" : "id").GetGuid());
        }
        else
        {
            var error = Record.Exception(() => TrainingValidation.Canonical(kind, id, value));
            Assert.NotNull(error);
            Assert.True(error is JsonException || error is TrainingException { Status: 400 },
                $"Unexpected exception type in {name}: {error.GetType().Name}");
        }
    }

    /// <summary>Читает только синтетический tracked fixture; verdicts проверяются Core в check-linux.sh.</summary>
    private static IReadOnlyDictionary<string, JsonElement> LoadCases()
    {
        using var data = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "Fixtures", "training-validation.json")));
        return data.RootElement.EnumerateArray().ToDictionary(item => item.GetProperty("name").GetString()!, item => item.Clone());
    }
}
