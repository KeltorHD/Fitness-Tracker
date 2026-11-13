using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет доставку HealthKit через настоящий JWT/introspection HTTP host и структурированные таблицы.</summary>
[Trait("Category", "HTTP")]
public sealed class AppleHealthSyncTests
{
    private static readonly DateTimeOffset _date = new(2024, 3, 30, 8, 0, 0, TimeSpan.Zero);

    /// <summary>Перезапрос потерянного ACK не меняет состояние; неизменяемый UUID дедуплицируется между устройствами.</summary>
    [Fact]
    public async Task RetryAndSecondDeviceDoNotDuplicateNativeSamplesAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var point = Quantity("bodyWeight", 72.35);
        var batch = Batch([point]);
        var first = await ApplyAsync(client, batch);
        var repeated = await ApplyAsync(client, batch);
        Assert.Equal(first.BatchId, repeated.BatchId);
        Assert.Equal(first.Sequence, repeated.Sequence);
        await ApplyAsync(client, Batch([point]));
        var snapshot = await ReadAsync(client, "bodyWeight");
        Assert.Equal(72.35, Assert.Single(snapshot.Quantities).Value);
        using var scope = factory.Services.CreateScope();
        Assert.Single(await scope.ServiceProvider.GetRequiredService<BackupDbContext>().Set<HealthSyncSample>().ToListAsync());
        using var wrongSequence = await client.PostAsJsonAsync(Path(), batch with { BatchId = Guid.NewGuid(), Quantities = [Quantity("bodyWeight", 71)] });
        Assert.Equal(HttpStatusCode.Conflict, wrongSequence.StatusCode);
        Assert.Equal(72.35, Assert.Single((await ReadAsync(client, "bodyWeight")).Quantities).Value);
    }

    /// <summary>Сервер хранит реальные фазы; удаление из одного устройства не воскрешается старым повтором другого.</summary>
    [Fact]
    public async Task ExplicitDeletionWinsOverStaleDevicesAndEmptyReadIsNotDeletionAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var weight = Quantity("bodyWeight", 75);
        var sleepId = Guid.NewGuid();
        var sleep = new HealthSleepRecord(sleepId, _date.AddHours(-7), _date, null, "watch:source", "Watch",
            [new(sleepId, _date.AddHours(-7), _date, "deep")]);
        var original = Batch([weight]) with { Sleep = [sleep] };
        await ApplyAsync(client, original);
        await ApplyAsync(client, original with { Sequence = 2, BatchId = Guid.NewGuid(), Quantities = [], Sleep = [] });
        var before = await ReadAsync(client, "bodyWeight,sleep");
        Assert.Single(before.Quantities);
        Assert.Equal("deep", Assert.Single(Assert.Single(before.Sleep).Segments).Stage);
        await ApplyAsync(client, Batch([]) with { DeletedIds = [weight.Id, sleepId] });
        await ApplyAsync(client, original with { DeviceId = Guid.NewGuid() });
        var after = await ReadAsync(client, "bodyWeight,sleep");
        Assert.Empty(after.Quantities);
        Assert.Empty(after.Sleep);
    }

    /// <summary>Исходные шаги не суммируются повторно, CAS требует нового чтения после конкурентного изменения.</summary>
    [Fact]
    public async Task FusedTotalsUseNativeValuesAndRejectStaleAggregateVersionsAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var initial = Batch([Quantity("steps", 100), Quantity("steps", 70)]);
        var ack = await ApplyAsync(client, initial);
        var bucket = Assert.Single(ack.Buckets);
        Assert.Empty((await ReadAsync(client, "steps")).Quantities);
        await ApplyAsync(client, Batch([]) with { Aggregates = [new(bucket, 110)] });
        Assert.Equal(110, Assert.Single((await ReadAsync(client, "steps")).Quantities).Value);
        var changed = Batch([Quantity("steps", 20)]);
        var next = await ApplyAsync(client, changed);
        Assert.Empty((await ReadAsync(client, "steps")).Quantities);
        var stale = await ApplyAsync(client, Batch([]) with { Aggregates = [new(bucket, 110)] });
        Assert.True(Assert.Single(stale.Buckets).Revision > bucket.Revision);
        var latest = Assert.Single(next.Buckets);
        await ApplyAsync(client, Batch([]) with { Aggregates = [new(latest, 125)] });
        Assert.Equal(125, Assert.Single((await ReadAsync(client, "steps")).Quantities).Value);
        var removed = await ApplyAsync(client, Batch([]) with { DeletedIds = [changed.Quantities[0].Id] });
        var deletedBucket = Assert.Single(removed.Buckets);
        Assert.Contains(changed.Quantities[0].Id, deletedBucket.ExcludedIds);
        var missingExclusions = await ApplyAsync(client, Batch([]) with { Aggregates = [new(deletedBucket with { ExcludedIds = [] }, 125)] });
        Assert.Contains(changed.Quantities[0].Id, Assert.Single(missingExclusions.Buckets).ExcludedIds);
        Assert.Empty((await ReadAsync(client, "steps")).Quantities);
        await ApplyAsync(client, Batch([]) with { Aggregates = [new(deletedBucket, null)] });
        Assert.Empty((await ReadAsync(client, "steps")).Quantities);
    }

    /// <summary>Новый timezone создаёт собственные сводки из повторно прочитанных UUID без дублирования измерений.</summary>
    [Fact]
    public async Task TimezoneRescanKeepsNativeIdentityAndIsolatesDailyTotalsAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var point = Quantity("steps", 100);
        var utc = await ApplyAsync(client, Batch([point]));
        await ApplyAsync(client, Batch([]) with { Aggregates = [new(Assert.Single(utc.Buckets), 100)] });
        var moscow = await ApplyAsync(client, Batch([point]) with { TimeZoneId = "Europe/Moscow" });
        var local = Assert.Single(moscow.Buckets);
        Assert.Equal("Europe/Moscow", local.TimeZoneId);
        Assert.Equal(21, local.Start.Hour);
        Assert.Single((await ReadAsync(client, "steps")).Quantities);
        Assert.Empty((await ReadAsync(client, "steps", "Europe/Moscow")).Quantities);
        await ApplyAsync(client, Batch([]) with { TimeZoneId = local.TimeZoneId, Aggregates = [new(local, 100)] });
        Assert.Equal(100, Assert.Single((await ReadAsync(client, "steps", "Europe/Moscow")).Quantities).Value);
    }

    /// <summary>Читающее устройство в другом поясе ставит дневную статистику в очередь, которую обслуживает передающий iPhone.</summary>
    [Fact]
    public async Task ReadOnlyDeviceRequestsNativeTotalsInItsTimezoneAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var first = await ApplyAsync(client, Batch([Quantity("steps", 100)]));
        await ApplyAsync(client, Batch([]) with { Aggregates = [new(Assert.Single(first.Buckets), 100)] });
        Assert.Empty((await ReadAsync(client, "steps", "Europe/Moscow")).Quantities);
        using var pending = await client.GetAsync("/v1/health/providers/appleHealth/pending");
        Assert.Equal(HttpStatusCode.OK, pending.StatusCode);
        var body = await pending.Content.ReadFromJsonAsync<JsonElement>();
        var bucket = Assert.Single(body.GetProperty("buckets").Deserialize<HealthSyncBucketData[]>(JsonSerializerOptions.Web)!);
        Assert.Equal("Europe/Moscow", bucket.TimeZoneId);
        await ApplyAsync(client, Batch([]) with { TimeZoneId = bucket.TimeZoneId, Aggregates = [new(bucket, 100)] });
        Assert.Equal(100, Assert.Single((await ReadAsync(client, "steps", "Europe/Moscow")).Quantities).Value);
        Assert.Equal(100, Assert.Single((await ReadAsync(client, "steps")).Quantities).Value);
    }

    /// <summary>Сервер учитывает обычный DST и день с отсутствующей полуночью.</summary>
    [Theory]
    [InlineData("Europe/Berlin", "2024-03-31T00:00:00Z", 23)]
    [InlineData("America/Sao_Paulo", "2018-11-04T04:00:00Z", 23)]
    public async Task BucketsUseRealCalendarBoundariesAsync(string zone, string instant, int hours)
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var date = DateTimeOffset.Parse(instant);
        var ack = await ApplyAsync(client, Batch([Quantity("steps", 1) with { Start = date, End = date }]) with { TimeZoneId = zone });
        var bucket = Assert.Single(ack.Buckets);
        Assert.Equal(hours, (bucket.End - bucket.Start).TotalHours);
        await ApplyAsync(client, Batch([]) with { TimeZoneId = zone, Aggregates = [new(bucket, 1)] });
    }

    /// <summary>Неверный пакет полностью откатывается без записи частичного health payload.</summary>
    [Theory]
    [InlineData("negative")]
    [InlineData("fractionalSteps")]
    [InlineData("duplicate")]
    [InlineData("emptyDevice")]
    [InlineData("unknownMetric")]
    [InlineData("sleep")]
    [InlineData("zone")]
    [InlineData("sequence")]
    public async Task RejectsInvalidBatchWithoutPartialSaveAsync(string failure)
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var point = Quantity("bodyWeight", 70);
        var batch = Batch([point]);
        batch = failure switch
        {
            "negative" => batch with { Quantities = [point with { Value = -1 }] },
            "fractionalSteps" => batch with { Quantities = [Quantity("steps", 1.5)] },
            "duplicate" => batch with { DeletedIds = [point.Id] },
            "emptyDevice" => batch with { DeviceId = Guid.Empty },
            "unknownMetric" => batch with { Quantities = [point with { Metric = "unknown" }] },
            "sleep" => batch with { Sleep = [new(Guid.NewGuid(), _date, _date.AddHours(1), 3600, "source", "source", [])] },
            "zone" => batch with { TimeZoneId = "not-a-zone" },
            _ => batch with { Sequence = 0 }
        };
        using var response = await client.PostAsJsonAsync(Path(), batch);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Empty((await ReadAsync(client, "bodyWeight")).Quantities);
    }

    /// <summary>JWT, introspection и owner isolation применяются к чтению и записи health history.</summary>
    [Fact]
    public async Task EnforcesOwnerAndRevokedSessionBeforeWritingAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        await ApplyAsync(client, Batch([Quantity("bodyWeight", 70)]));
        using var other = factory.Client(Guid.NewGuid().ToString());
        Assert.Empty((await ReadAsync(other, "bodyWeight")).Quantities);
        using var anonymous = factory.Client();
        using var unauthorized = await anonymous.PostAsJsonAsync(Path(), Batch([]));
        Assert.Equal(HttpStatusCode.Unauthorized, unauthorized.StatusCode);
        factory.Introspection.Active = false;
        using var revoked = await client.PostAsJsonAsync(Path(), Batch([Quantity("bodyWeight", 80)]));
        Assert.Equal(HttpStatusCode.Unauthorized, revoked.StatusCode);
        factory.Introspection.Active = true;
        Assert.Equal(70, Assert.Single((await ReadAsync(client, "bodyWeight")).Quantities).Value);
    }

    /// <summary>Дублирующиеся поля, неизвестные свойства и отсутствующие обязательные коллекции отклоняются на HTTP-границе.</summary>
    [Theory]
    [InlineData("duplicate")]
    [InlineData("missing")]
    [InlineData("overpost")]
    [InlineData("numeric")]
    public async Task RejectsAmbiguousJsonAsync(string error)
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var body = JsonSerializer.Serialize(Batch([]), JsonSerializerOptions.Web);
        if (error == "duplicate") body = body.Insert(1, "\"sequence\":1,");
        if (error == "overpost") body = body.Insert(1, "\"owner\":\"not-trusted\",");
        if (error == "numeric") body = body.Replace("\"sequence\":1", "\"sequence\":\"1\"");
        if (error == "missing") body = body.Replace("\"deletedIds\":[],", "");
        using var response = await client.PostAsync(Path(), new StringContent(body, Encoding.UTF8, "application/json"));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    /// <summary>Настоящий Codable payload Swift проходит HTTP без подстановки null или повторной сериализации C#.</summary>
    [Fact]
    public async Task AcceptsActualSwiftPayloadWithOmittedOptionalFieldsAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        await ApplyAsync(client, Batch([Quantity("steps", 10)]));
        var bytes = await File.ReadAllBytesAsync(System.IO.Path.Combine(AppContext.BaseDirectory, "Fixtures", "health-sync-contract.json"));
        using var request = new ByteArrayContent(bytes);
        request.Headers.ContentType = new("application/json");
        using var response = await client.PostAsync(Path(), request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var snapshot = await ReadAsync(client, "bodyWeight,sleep,steps");
        Assert.Equal(72.35, Assert.Single(snapshot.Quantities).Value);
        var report = Assert.Single(snapshot.Sleep);
        Assert.Null(report.AsleepSeconds);
        Assert.Equal("deep", Assert.Single(report.Segments).Stage);
        Assert.Equal("Часы", report.SourceName);
    }

    /// <summary>Создаёт синтетическую точку с настоящими единицами и постоянной датой.</summary>
    private static HealthQuantity Quantity(string metric, double value) => new(Guid.NewGuid(), metric, _date, _date, value, "source", "Source");
    /// <summary>Создаёт первую доставку отдельной установки.</summary>
    private static HealthSyncBatch Batch(HealthQuantity[] quantities) => new(Guid.NewGuid(), 1, Guid.NewGuid(), "UTC", _date, quantities, [], [], []);
    /// <summary>Возвращает фиксированный маршрут без owner ID.</summary>
    private static string Path() => "/v1/health/providers/appleHealth/changes";
    /// <summary>Проверяет реальный ACK HTTP-записи.</summary>
    private static async Task<HealthSyncAcknowledgement> ApplyAsync(HttpClient client, HealthSyncBatch batch)
    {
        using var response = await client.PostAsJsonAsync(Path(), batch);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<HealthSyncAcknowledgement>())!;
    }
    /// <summary>Читает серверную историю через общий provider endpoint.</summary>
    private static async Task<HealthDataSnapshot> ReadAsync(HttpClient client, string metrics, string zone = "UTC")
    {
        using var response = await client.GetAsync($"/v1/health/providers/appleHealth/data?start=2024-03-29T00:00:00Z&end=2024-03-31T00:00:00Z&metrics={metrics}&zoneName={Uri.EscapeDataString(zone)}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<HealthDataSnapshot>())!;
    }
}
