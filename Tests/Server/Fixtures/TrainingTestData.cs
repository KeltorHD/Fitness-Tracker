using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using FitLife.Backend;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Создаёт независимые синтетические данные и выполняет настоящие HTTP-запросы нового журнала.</summary>
internal static class TrainingTestData
{
    /// <summary>Возвращает свежую мутацию заданного типа из действующего Swift fixture.</summary>
    internal static TrainingMutation Mutation(string kind) => TrainingFixture.Mutations().First(item => item.Kind == kind);

    /// <summary>Изменяет копию JSON, не меняя общий fixture и данные соседнего теста.</summary>
    internal static TrainingMutation Edit(TrainingMutation mutation, Action<JsonObject> edit)
    {
        var value = JsonNode.Parse(mutation.Value!.Value.GetRawText())!.AsObject();
        edit(value);
        return mutation with { Value = JsonSerializer.SerializeToElement(value, TrainingJson.Options) };
    }

    /// <summary>Создаёт небольшой валидный замер для сценариев страниц, квот и конкуренции.</summary>
    internal static TrainingMutation Weight(Guid? id = null, double kilograms = 75.25, long revision = 0)
    {
        var recordId = id ?? Guid.NewGuid();
        return new TrainingMutation
        {
            Kind = TrainingKinds.BodyWeight,
            Id = recordId,
            BaseRevision = revision,
            Deleted = false,
            Value = JsonSerializer.SerializeToElement(new BodyWeightData { Id = recordId, MeasuredAt = 1700000000.125, WeightKG = kilograms }, TrainingJson.Options)
        };
    }

    /// <summary>Требует успешное подтверждение всего HTTP-пакета с сохранением исходного порядка.</summary>
    internal static async Task<List<TrainingChange>> SendAsync(HttpClient client, params TrainingMutation[] mutations)
    {
        using var response = await client.PostAsJsonAsync("/v1/training/changes", mutations, TrainingJson.Options);
        response.EnsureSuccessStatusCode();
        var result = await response.Content.ReadFromJsonAsync<List<TrainingChange>>(TrainingJson.Options);
        Assert.NotNull(result);
        Assert.Equal(mutations.Length, result.Count);
        return result;
    }
}
