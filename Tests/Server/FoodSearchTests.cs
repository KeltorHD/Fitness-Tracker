using System.Net;
using System.Net.Http.Json;
using FitnessTracker.Backend;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет HTTP-прокси каталога без реальной сети и без зависимости от наличия продукта у поставщика.</summary>
[Trait("Category", "HTTP")]
public sealed class FoodSearchTests
{
    /// <summary>Запрос без аккаунта получает проверенные данные; повтор использует кеш и не расходует ключ снова.</summary>
    [Fact]
    public async Task PublicBarcodeRequestPreservesNutritionSourceAndUsesCacheAsync()
    {
        var handler = new ProviderHandler();
        using var fixture = new BackendFactory();
        using var factory = fixture.WithWebHostBuilder(builder => builder
            .ConfigureAppConfiguration((_, configuration) => configuration.AddInMemoryCollection(
                new Dictionary<string, string?> { ["FoodSearch:PerekApiKey"] = "test-provider-key" }))
            .ConfigureServices(services => services.AddHttpClient("perek").ConfigurePrimaryHttpMessageHandler(() => handler)));
        using var client = factory.CreateClient();
        for (var i = 0; i < 2; i++)
        {
            using var response = await client.GetAsync("/v1/foods/search?q=7622210769459");
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            var result = await response.Content.ReadFromJsonAsync<Response>();
            var product = Assert.Single(Assert.IsType<Response>(result).Products);
            Assert.Equal("7622210769459", product.Barcode);
            Assert.Equal("grams", product.Unit);
            Assert.Equal(480, product.Per100Units.Calories);
            Assert.Equal("https://perek.us/food/test/oreo", product.SourceURL);
        }
        Assert.Equal(1, handler.Calls);
    }

    /// <summary>Ошибочные, пустые и отсутствующие карточки не превращаются в продукт с нулевыми КБЖУ.</summary>
    [Theory]
    [InlineData("missing", 200)]
    [InlineData("incomplete", 200)]
    [InlineData("broken", 502)]
    [InlineData("outage", 503)]
    [InlineData("limited", 429)]
    public async Task HandlesProviderFailuresWithoutLeakingPayloadAsync(string query, int status)
    {
        var handler = new ProviderHandler();
        using var fixture = new BackendFactory();
        using var factory = fixture.WithWebHostBuilder(builder => builder
            .ConfigureAppConfiguration((_, configuration) => configuration.AddInMemoryCollection(
                new Dictionary<string, string?> { ["FoodSearch:PerekApiKey"] = "test-provider-key" }))
            .ConfigureServices(services => services.AddHttpClient("perek").ConfigurePrimaryHttpMessageHandler(() => handler)));
        using var client = factory.CreateClient();
        using var response = await client.GetAsync("/v1/foods/search?q=" + query);
        Assert.Equal(status, (int)response.StatusCode);
        var body = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain("test-provider-key", body);
        Assert.DoesNotContain("private upstream", body);
        if (query == "limited")
        {
            Assert.NotNull(response.Headers.RetryAfter);
            using var retry = await client.GetAsync("/v1/foods/search?q=another");
            Assert.Equal(HttpStatusCode.TooManyRequests, retry.StatusCode);
            Assert.Equal(1, handler.Calls);
        }
        if (status == 200)
        {
            var payload = await response.Content.ReadFromJsonAsync<Response>();
            Assert.Empty(Assert.IsType<Response>(payload).Products);
        }
    }

    /// <summary>Ненастроенный поставщик не вызывается, а слишком длинный поиск отклоняется до сети.</summary>
    [Fact]
    public async Task MissingConfigurationAndInvalidQueryNeverCallProviderAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.CreateClient();
        using var unavailable = await client.GetAsync("/v1/foods/search?q=milk");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, unavailable.StatusCode);
        using var invalid = await client.GetAsync("/v1/foods/search?q=1");
        Assert.Equal(HttpStatusCode.BadRequest, invalid.StatusCode);
    }

    /// <summary>Общий дневной бюджет действует между пользователями и восстанавливается по UTC, а не после каждого запроса.</summary>
    [Fact]
    public async Task SharedDailyBudgetResetsOnlyOnTheNextUtcDayAsync()
    {
        var handler = new ProviderHandler();
        var clock = new CatalogClock();
        using var fixture = new BackendFactory();
        using var factory = fixture.WithWebHostBuilder(builder => builder
            .ConfigureAppConfiguration((_, configuration) => configuration.AddInMemoryCollection(
                new Dictionary<string, string?> { ["FoodSearch:PerekApiKey"] = "test-provider-key" }))
            .ConfigureServices(services =>
            {
                services.AddSingleton<TimeProvider>(clock);
                services.AddHttpClient("perek").ConfigurePrimaryHttpMessageHandler(() => handler);
            }));
        var search = factory.Services.GetRequiredService<FoodSearch>();
        for (var index = 0; index < 450; index++)
        {
            clock.Current += TimeSpan.FromMinutes(1);
            Assert.Equal(200, (await search.SearchAsync("food" + index, CancellationToken.None)).Status);
        }
        Assert.Equal(429, (await search.SearchAsync("over budget", CancellationToken.None)).Status);
        Assert.Equal(450, handler.Calls);
        clock.Current = new DateTimeOffset(2026, 11, 11, 0, 0, 0, TimeSpan.Zero);
        Assert.Equal(200, (await search.SearchAsync("next day", CancellationToken.None)).Status);
        Assert.Equal(451, handler.Calls);
    }

    /// <summary>Управляемые часы для границ общего бюджета без задержек и зависимости от реального времени.</summary>
    private sealed class CatalogClock : TimeProvider
    {
        /// <summary>Текущее время проверки в UTC.</summary>
        public DateTimeOffset Current { get; set; } = new(2026, 11, 10, 0, 0, 0, TimeSpan.Zero);
        /// <summary>Возвращает установленный момент проверки.</summary>
        public override DateTimeOffset GetUtcNow() => Current;
    }

    /// <summary>Публичный контракт ответа каталога.</summary>
    private sealed record Response(FoodSearchProduct[] Products);

    /// <summary>Транспортные ответы по запросу без внешней сети и общих изменяемых fixtures.</summary>
    private sealed class ProviderHandler : HttpMessageHandler
    {
        /// <summary>Число фактических вызовов поставщика.</summary>
        public int Calls { get; private set; }
        /// <summary>Возвращает карточку либо выбранную запросом ошибку.</summary>
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            Assert.Equal("https", request.RequestUri!.Scheme);
            Assert.Equal("perek.us", request.RequestUri.Host);
            Assert.Equal("test-provider-key", Assert.Single(request.Headers.GetValues("X-Api-Key")));
            var query = request.RequestUri.Query;
            var status = query.Contains("missing", StringComparison.Ordinal) ? HttpStatusCode.NotFound :
                query.Contains("outage", StringComparison.Ordinal) ? HttpStatusCode.ServiceUnavailable :
                query.Contains("limited", StringComparison.Ordinal) ? HttpStatusCode.TooManyRequests : HttpStatusCode.OK;
            var product = """{"id":"test/oreo","name":"Oreo","brand":{"name":"Oreo"},"unit":"г","per100":{"kcal":480,"protein":5,"fat":20,"carbs":70},"url":"https://perek.us/food/test/oreo"}""";
            if (query.Contains("incomplete", StringComparison.Ordinal)) product = """{"id":"empty","name":"Empty","unit":"г","per100":{"kcal":100}}""";
            var body = request.RequestUri.AbsolutePath.Contains("/barcode/", StringComparison.Ordinal) ? "{\"food\":" + product + "}" : "{\"foods\":[" + product + "]}";
            if (query.Contains("broken", StringComparison.Ordinal)) body = "private upstream";
            var response = new HttpResponseMessage(status) { Content = new StringContent(body) };
            if (status == HttpStatusCode.TooManyRequests) response.Headers.RetryAfter = new(TimeSpan.FromMinutes(2));
            return Task.FromResult(response);
        }
    }
}
