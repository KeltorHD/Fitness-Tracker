using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет безопасную публикацию webcredentials и отсутствие OAuth-кода на fallback странице.</summary>
[Trait("Category", "HTTP")]
public sealed class AppAssociationTests
{
    /// <summary>Не публикует фиктивную привязку, пока App ID не настроен корректно.</summary>
    [Theory]
    [InlineData(null, HttpStatusCode.NotFound)]
    [InlineData("not-an-apple-app-id", HttpStatusCode.ServiceUnavailable)]
    [InlineData("AB12CD34EF.ru.example.fitness", HttpStatusCode.OK)]
    public async Task PublishesOnlyConfiguredAppIdentifierAsync(string? identifier, HttpStatusCode status)
    {
        using var factory = new AuthFactory(appleAppIdentifier: identifier);
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions
        { BaseAddress = new Uri("https://localhost"), AllowAutoRedirect = false });
        using var response = await client.GetAsync("/.well-known/apple-app-site-association");
        Assert.Equal(status, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore is true);
        Assert.True(response.Headers.CacheControl?.NoCache is true);
        if (status != HttpStatusCode.OK) return;
        var association = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(identifier, Assert.Single(association.GetProperty("webcredentials").GetProperty("apps").EnumerateArray()).GetString());
        Assert.False(association.TryGetProperty("applinks", out _));
    }

    /// <summary>Fallback не отражает код/state, не перенаправляет на произвольный адрес и запрещает кеширование.</summary>
    [Fact]
    public async Task CallbackFallbackDoesNotReflectAuthorizationSecretsAsync()
    {
        using var factory = new AuthFactory();
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });
        using var response = await client.GetAsync("/ios/oauth/callback?code=secret-code&state=secret-state&returnUrl=https://attacker.test");
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var content = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain("secret-", content);
        Assert.DoesNotContain("attacker", content);
        Assert.Null(response.Headers.Location);
        Assert.True(response.Headers.CacheControl?.NoStore is true);
        Assert.True(response.Headers.CacheControl?.NoCache is true);
    }
}
