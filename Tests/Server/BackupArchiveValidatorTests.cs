using System.Text;
using System.Text.Json.Nodes;
using FitLife.Backend;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет текущий формат и границы архива без БД, HTTP и внешних зависимостей.</summary>
[Trait("Category", "Unit")]
public sealed class BackupArchiveValidatorTests
{
    private const string VALID_ARCHIVE = """{"format":"com.fitlife.archive","version":4,"exportedAt":1700000000,"workouts":[],"templates":[],"bodyWeights":[]}""";

    /// <summary>Принимает только текущую маркировку FitLife и версию 4.</summary>
    [Fact]
    public void AcceptsCurrentFitLifeArchive() =>
        Assert.Equal(4, BackupArchiveValidator.Validate(Encoding.UTF8.GetBytes(VALID_ARCHIVE)));

    /// <summary>Отвергает неверные JSON-типы и версии безопасной ошибкой вместо необработанного исключения.</summary>
    [Theory]
    [InlineData("format", "null")]
    [InlineData("format", "42")]
    [InlineData("format", "\"unknown\"")]
    [InlineData("format", "\"com.fitnesstracker.archive\"")]
    [InlineData("format", "\"com.fitsession.archive\"")]
    [InlineData("version", "null")]
    [InlineData("version", "\"4\"")]
    [InlineData("version", "true")]
    [InlineData("version", "0")]
    [InlineData("version", "1")]
    [InlineData("version", "2")]
    [InlineData("version", "3")]
    [InlineData("version", "5")]
    [InlineData("version", "1.5")]
    [InlineData("version", "2147483648")]
    [InlineData("exportedAt", "null")]
    [InlineData("exportedAt", "\"2024-01-01\"")]
    [InlineData("exportedAt", "1e9999")]
    [InlineData("workouts", "{}")]
    [InlineData("templates", "null")]
    [InlineData("bodyWeights", "false")]
    public void RejectsMalformedEnvelopeFields(string field, string value)
    {
        var archive = JsonNode.Parse(VALID_ARCHIVE)!.AsObject();
        archive[field] = JsonNode.Parse(value);
        AssertInvalidArchive(Encoding.UTF8.GetBytes(archive.ToJsonString()));
    }

    /// <summary>Все коллекции и поля конверта обязательны в текущем формате.</summary>
    [Theory]
    [InlineData("format")]
    [InlineData("version")]
    [InlineData("exportedAt")]
    [InlineData("workouts")]
    [InlineData("templates")]
    [InlineData("bodyWeights")]
    public void RejectsMissingRequiredFields(string field)
    {
        var archive = JsonNode.Parse(VALID_ARCHIVE)!.AsObject();
        archive.Remove(field);
        AssertInvalidArchive(Encoding.UTF8.GetBytes(archive.ToJsonString()));
    }

    /// <summary>Повреждённый UTF-8, незавершённый JSON и неподходящий корень не доходят до persistence.</summary>
    [Theory]
    [InlineData("null")]
    [InlineData("[]")]
    [InlineData("{unfinished")]
    public void RejectsMalformedJson(string json) => AssertInvalidArchive(Encoding.UTF8.GetBytes(json));

    /// <summary>Ошибка формата не содержит приватный текст повреждённого архива.</summary>
    [Fact]
    public void RejectsInvalidUtf8WithoutLeakingPayload()
    {
        AssertInvalidArchive([0xff, 0xfe, 0xfd]);
        var exception = Assert.Throws<BackupException>(() => BackupArchiveValidator.Validate("private-health-record"u8.ToArray()));
        Assert.DoesNotContain("private-health-record", exception.Message);
    }

    /// <summary>Принимает ровно 30 MiB и отклоняет превышение без разбора большого JSON.</summary>
    [Fact]
    public void EnforcesExactByteBoundary()
    {
        var payload = new byte[30 * 1024 * 1024];
        payload.AsSpan().Fill((byte)' ');
        Encoding.UTF8.GetBytes(VALID_ARCHIVE).CopyTo(payload, 0);
        Assert.Equal(4, BackupArchiveValidator.Validate(payload));
        foreach (var invalid in new[] { Array.Empty<byte>(), new byte[payload.Length + 1] })
        {
            var error = Assert.Throws<BackupException>(() => BackupArchiveValidator.Validate(invalid));
            Assert.Equal(413, error.Status);
            Assert.Equal("invalid_size", error.Code);
        }
    }

    /// <summary>Граничное число записей разрешено, следующая запись отклоняется для каждой коллекции.</summary>
    [Theory]
    [InlineData("workouts", 10000)]
    [InlineData("templates", 1000)]
    [InlineData("bodyWeights", 10000)]
    public void EnforcesCollectionLimits(string field, int limit)
    {
        var archive = JsonNode.Parse(VALID_ARCHIVE)!.AsObject();
        var items = new JsonArray();
        for (var index = 0; index < limit; index++) items.Add(new JsonObject());
        archive[field] = items;
        Assert.Equal(4, BackupArchiveValidator.Validate(Encoding.UTF8.GetBytes(archive.ToJsonString())));
        items.Add(new JsonObject());
        AssertInvalidArchive(Encoding.UTF8.GetBytes(archive.ToJsonString()));
    }

    /// <summary>Проверяет стабильные status/code ошибки формата.</summary>
    private static void AssertInvalidArchive(byte[] payload)
    {
        var error = Assert.Throws<BackupException>(() => BackupArchiveValidator.Validate(payload));
        Assert.Equal(400, error.Status);
        Assert.Equal("invalid_archive", error.Code);
    }
}
