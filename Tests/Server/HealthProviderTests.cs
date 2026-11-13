using System.Buffers.Binary;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FitLife.Backend;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет реальные преобразования Xiaomi и защищённый HTTP-контракт без внешней сети.</summary>
public sealed class HealthProviderTests
{
    private static readonly DateTimeOffset _end = BackendFactory.BackupTime;
    private static readonly DateTimeOffset _start = _end.AddDays(-1);

    /// <summary>Частичное согласие не раскрывает соседнюю категорию того же DataPoint; без нужных scopes облако не вызывается.</summary>
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task ReadsOnlyActuallyGrantedMetricsAsync(bool permitted)
    {
        using var grant = new HttpClient(new Handler(_ => Json(new { accessToken = "test", clientId = "123", metrics = new[] { permitted ? "bodyWeight" : "steps" } })));
        var calls = 0;
        using var cloud = new HttpClient(new Handler(_ =>
        {
            calls++;
            return Points(Point("com.xiaomi.weight.instantaneous", new { fieldName = "weight", floatValue = 72.5 }, new { fieldName = "body_fat_rate", floatValue = 20.5 }));
        }));
        var provider = Provider(grant, cloud);
        if (permitted)
        {
            var snapshot = await provider.ReadAsync(Guid.NewGuid().ToString(), _start, _end, ["bodyWeight", "bodyFatPercentage"], TimeZoneInfo.Utc, default);
            Assert.Equal("bodyWeight", Assert.Single(snapshot.Metrics));
            Assert.Equal("bodyWeight", Assert.Single(snapshot.Quantities).Metric);
            Assert.Equal(1, calls);
        }
        else
        {
            var error = await Assert.ThrowsAsync<HealthDataException>(() => provider.ReadAsync(Guid.NewGuid().ToString(), _start, _end, ["bodyWeight", "bodyFatPercentage"], TimeZoneInfo.Utc, default));
            Assert.Equal(403, error.Status);
            Assert.Equal("health_permission_required", error.Code);
            Assert.Equal(0, calls);
        }
    }

    /// <summary>Общие единицы, partial grants, nonce, реальные фазы и устойчивые UUID сохраняются при повторе.</summary>
    [Fact]
    public async Task NormalizesActualDataWithoutInventingActiveEnergyOrSleepStagesAsync()
    {
        var owner = Guid.NewGuid().ToString();
        var grant = new Handler(request =>
        {
            Assert.Equal($"/internal/health/mi-fitness/{owner}/grant", request.RequestUri!.AbsolutePath);
            Assert.Equal(BackendFactory.ServiceKey, request.Headers.GetValues("X-Service-Key").Single());
            return Json(new { accessToken = "synthetic-access", clientId = "123", metrics = new[] { "steps", "totalEnergy", "bodyWeight", "bodyFatPercentage", "heartRate", "restingHeartRate", "bloodOxygen", "sleep" } });
        });
        var nonces = new HashSet<string>();
        var cloud = new Handler(request =>
        {
            Assert.Equal("https", request.RequestUri!.Scheme);
            Assert.Equal("hlthopen.io.mi.com", request.RequestUri.Host);
            Assert.Equal("synthetic-access", request.Headers.Authorization!.Parameter);
            var nonce = request.Headers.GetValues("X-Client-Nonce").Single();
            Assert.True(nonces.Add(nonce));
            Assert.Equal((uint)(_end.ToUnixTimeSeconds() / 60), BinaryPrimitives.ReadUInt32BigEndian(WebEncoders.Base64UrlDecode(nonce).AsSpan(8)));
            var query = QueryHelpers.ParseQuery(request.RequestUri.Query);
            if (request.RequestUri.AbsolutePath.EndsWith("dailies"))
                return Points(Point("com.xiaomi.steps.total", new { fieldName = "steps", integerValue = 0 }),
                    Point("com.xiaomi.calories.total", new { fieldName = "calories_total", floatValue = 2042.5 }));
            var type = query["dataTypeName"].ToString();
            if (type == "com.xiaomi.sleep.health") return Json(new
            {
                healthRecords = new[] {
                new { dataTypeName = type, startTime = _start.ToUnixTimeMilliseconds(), endTime = _end.ToUnixTimeMilliseconds(),
                    originDataSourceId = "watch", value = new[] {new {fieldName = "all_sleep_duration", integerValue = 360}},
                    subData = new Dictionary<string, object> { ["com.xiaomi.sleep_state.delta"] = new {dataPoints = new[] {
                        Phase(2, _start, _start.AddHours(1)), Phase(6, _start.AddHours(1), _start.AddHours(2)) } } } }
            },
                hasMore = false
            });
            var values = type switch
            {
                "com.xiaomi.weight.instantaneous" => new object[] { new { fieldName = "weight", floatValue = 72.35 }, new { fieldName = "body_fat_rate", floatValue = 21.4 } },
                "com.xiaomi.spo2.instantaneous" => [new { fieldName = "spo2", floatValue = 97.5 }],
                _ => [new { fieldName = "bpm", floatValue = 63.5 }]
            };
            return Points(Point(type, values));
        });
        using var grantClient = new HttpClient(grant);
        using var cloudClient = new HttpClient(cloud);
        var provider = Provider(grantClient, cloudClient);
        string[] metrics = ["steps", "totalEnergy", "bodyWeight", "bodyFatPercentage", "heartRate", "restingHeartRate", "bloodOxygen", "sleep"];
        var first = await provider.ReadAsync(owner, _start, _end, metrics, TimeZoneInfo.Utc, default);
        var second = await provider.ReadAsync(owner, _start, _end, metrics, TimeZoneInfo.Utc, default);
        Assert.Equal(7, first.Quantities.Count);
        Assert.Equal(72.35, Assert.Single(first.Quantities, item => item.Metric == "bodyWeight").Value);
        Assert.Equal(0, Assert.Single(first.Quantities, item => item.Metric == "steps").Value);
        Assert.DoesNotContain(first.Quantities, item => item.Metric == "activeEnergy");
        var sleep = Assert.Single(first.Sleep);
        Assert.Equal(21600, sleep.AsleepSeconds);
        Assert.Equal("deep", Assert.Single(sleep.Segments).Stage);
        Assert.Equal(first.Quantities.Select(item => item.Id), second.Quantities.Select(item => item.Id));
        Assert.Equal(sleep.Id, Assert.Single(second.Sleep).Id);
    }

    /// <summary>Повтор cursor, противоречивые версии и неверные JSON-типы не выдают частичный успех.</summary>
    [Theory]
    [InlineData("cursor")]
    [InlineData("conflict")]
    [InlineData("shape")]
    [InlineData("numeric")]
    public async Task RejectsMalformedOrContradictoryPagesAsync(string failure)
    {
        using var grant = new HttpClient(new Handler(_ => Json(new { accessToken = "test", clientId = "123", metrics = new[] { "bodyWeight" } })));
        using var cloud = new HttpClient(new Handler(_ => failure switch
        {
            "cursor" => Json(new { group = new[] { new { dataSet = new[] { new { dataPoints = Array.Empty<object>() } } } }, cursor = 42, hasMore = true }),
            "conflict" => Points(Point("com.xiaomi.weight.instantaneous", new { fieldName = "weight", floatValue = 70.5 }), Point("com.xiaomi.weight.instantaneous", new { fieldName = "weight", floatValue = 71.5 })),
            "numeric" => Points(Point("com.xiaomi.weight.instantaneous", new { fieldName = "weight", floatValue = "secret-invalid-number" })),
            _ => Json(new { group = new[] { false } })
        }));
        var error = await Assert.ThrowsAsync<HealthDataException>(() => Provider(grant, cloud).ReadAsync(Guid.NewGuid().ToString(), _start, _end, ["bodyWeight"], TimeZoneInfo.Utc, default));
        Assert.Equal(502, error.Status);
        Assert.Equal("invalid_health_response", error.Code);
        Assert.DoesNotContain("secret", error.Message);
    }

    /// <summary>Внешние ошибки становятся безопасными категориями; отказ Xiaomi не отзывает FitLife JWT.</summary>
    [Theory]
    [InlineData(401, 403, "health_not_connected")]
    [InlineData(403, 403, "health_permission_required")]
    [InlineData(429, 429, "health_rate_limited")]
    [InlineData(503, 503, "health_provider_unavailable")]
    public async Task MapsExternalFailuresAsync(int external, int status, string code)
    {
        using var grant = new HttpClient(new Handler(_ => Json(new { accessToken = "test", clientId = "123", metrics = new[] { "bodyWeight" } })));
        using var cloud = new HttpClient(new Handler(_ => new((HttpStatusCode)external) { Content = new StringContent("private-health-payload") }));
        var error = await Assert.ThrowsAsync<HealthDataException>(() => Provider(grant, cloud).ReadAsync(Guid.NewGuid().ToString(), _start, _end, ["bodyWeight"], TimeZoneInfo.Utc, default));
        Assert.Equal(status, error.Status);
        Assert.Equal(code, error.Code);
        Assert.DoesNotContain("private", error.Message);
    }

    /// <summary>JWT subject и introspection обязательны; owner из query не используется.</summary>
    [Fact]
    public async Task HttpUsesOnlyValidatedOwnerAndStopsOnRevocationAsync()
    {
        var provider = new CapturingProvider();
        using var factory = new BackendFactory(configureServices: services => services.AddSingleton<IHealthDataProvider>(provider));
        var owner = Guid.NewGuid().ToString();
        using var client = factory.Client(owner);
        var url = "/v1/health/providers/test/data?start=2024-03-30T00:00:00Z&end=2024-03-31T00:00:00Z&metrics=steps&zoneName=UTC&owner=" + Guid.NewGuid();
        using var read = await client.GetAsync(url);
        Assert.Equal(HttpStatusCode.OK, read.StatusCode);
        Assert.Equal(owner, provider.Owner);
        factory.Introspection.Active = false;
        using var revoked = await client.GetAsync(url);
        Assert.Equal(HttpStatusCode.Unauthorized, revoked.StatusCode);
        Assert.Equal(1, provider.Calls);
        using var anonymous = factory.Client();
        using var denied = await anonymous.GetAsync(url);
        Assert.Equal(HttpStatusCode.Unauthorized, denied.StatusCode);
    }

    /// <summary>Создаёт реальную реализацию с двумя полностью изолированными HTTP-транспортами.</summary>
    private static XiaomiHealthProvider Provider(HttpClient grant, HttpClient cloud) => new(cloud, new(grant,
        new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> { ["Backend:ServiceKey"] = BackendFactory.ServiceKey }).Build()), new FrozenTimeProvider(_end));
    /// <summary>Формирует документированный набор групп Xiaomi.</summary>
    private static HttpResponseMessage Points(params object[] points) => Json(new { group = new[] { new { dataSet = new[] { new { dataPoints = points } } } }, hasMore = false });
    /// <summary>Создаёт измерение с настоящей миллисекундной шкалой времени.</summary>
    private static object Point(string type, params object[] values) => new { dataTypeName = type, startTime = _start.ToUnixTimeMilliseconds(), endTime = _start.ToUnixTimeMilliseconds(), originDataSourceId = "watch", value = values };
    /// <summary>Формирует только явно заданный интервал фазы.</summary>
    private static object Phase(int state, DateTimeOffset start, DateTimeOffset end) => new { startTime = start.ToUnixTimeMilliseconds(), endTime = end.ToUnixTimeMilliseconds(), value = new[] { new { fieldName = "sleep_state", integerValue = state } } };
    /// <summary>Возвращает JSON без реальных credentials или сети.</summary>
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    /// <summary>Проверяемый HTTP boundary; отмена не превращается в успешный ответ.</summary>
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        /// <summary>Вызывает синхронную детерминированную фикстуру.</summary>
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) { cancellationToken.ThrowIfCancellationRequested(); return Task.FromResult(respond(request)); }
    }
    /// <summary>Фиксирует owner после настоящих JWT/introspection middleware.</summary>
    private sealed class CapturingProvider : IHealthDataProvider
    {
        /// <summary>Отдельный источник существует только в fixture.</summary>
        public string Id => "test";
        /// <summary>Последний проверенный владелец.</summary>
        public string? Owner { get; private set; }
        /// <summary>Количество фактических обращений.</summary>
        public int Calls { get; private set; }
        /// <summary>Отдаёт пустые реальные данные, не подменяя их числами.</summary>
        public Task<HealthDataSnapshot> ReadAsync(string owner, DateTimeOffset start, DateTimeOffset end, string[] metrics, TimeZoneInfo timeZone, CancellationToken cancellationToken)
        { Owner = owner; Calls++; return Task.FromResult(new HealthDataSnapshot(Id, start, end, _end, metrics, [], [])); }
    }
}
