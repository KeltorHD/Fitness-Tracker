using System.Net;
using System.Text.RegularExpressions;
using FitnessTracker.Authentication;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет полноту конфигурации внешних способов входа без обращения к провайдерам.</summary>
[Trait("Category", "Unit")]
public sealed class ProviderConfigurationTests
{
    /// <summary>Одного Enabled недостаточно; нужны все credentials, а выключенный провайдер остаётся недоступным.</summary>
    [Theory]
    [InlineData("Google")]
    [InlineData("Yandex")]
    public void ExternalProviderRequiresCompleteConfiguration(string provider)
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            [$"Providers:{provider}:Enabled"] = "true",
            [$"Providers:{provider}:ClientId"] = "test-client"
        }).Build();
        Assert.False(AuthConfiguration.Enabled(configuration, provider));
        configuration[$"Providers:{provider}:ClientSecret"] = "test-secret";
        Assert.True(AuthConfiguration.Enabled(configuration, provider));
        configuration[$"Providers:{provider}:Enabled"] = "false";
        Assert.False(AuthConfiguration.Enabled(configuration, provider));
        Assert.False(AuthConfiguration.Enabled(configuration, "Unknown"));
    }

    /// <summary>Apple без настроенного private key недоступен и не ломает страницу входа.</summary>
    [Fact]
    public void AppleRequiresExistingPrivateKey()
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Providers:Apple:Enabled"] = "true",
            ["Providers:Apple:ClientId"] = "test-client",
            ["Providers:Apple:TeamId"] = "test-team",
            ["Providers:Apple:KeyId"] = "test-key",
            ["Providers:Apple:PrivateKeyPath"] = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".p8")
        }).Build();
        Assert.False(AuthConfiguration.Enabled(configuration, "Apple"));
    }
}

/// <summary>Проверяет доступные/ненастроенные кнопки в настоящем Razor HTTP без внешнего OAuth.</summary>
[Trait("Category", "HTTP")]
public sealed class ProviderSelectionTests
{
    /// <summary>Ненастроенные способы видны с tooltip и остаются закрыты на сервере даже при ручном POST.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task UnconfiguredProvidersRemainVisibleAndCannotStartLoginAsync(bool enabledWithoutCredentials)
    {
        // Arrange: включённый, но незаполненный провайдер тоже не считается доступным.
        using var factory = new AuthFactory(providerSettings: new Dictionary<string, string?>
        {
            ["Providers:Google:Enabled"] = enabledWithoutCredentials.ToString(),
            ["Providers:Google:ClientId"] = "",
            ["Providers:Google:ClientSecret"] = ""
        });
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            BaseAddress = new Uri("https://localhost"),
            AllowAutoRedirect = false
        });
        var html = WebUtility.HtmlDecode(await client.GetStringAsync("/login"));

        // Assert: формы отсутствуют, доступность и подсказки присутствуют для каждого провайдера.
        foreach (var provider in new[] { "Apple", "Google", "Yandex" })
        {
            Assert.Contains($"aria-disabled=\"true\" tabindex=\"0\" aria-describedby=\"unavailable-{provider}\"", html);
            Assert.Contains($"id=\"unavailable-{provider}\" class=\"provider-tooltip\" role=\"tooltip\">В разработке", html);
            Assert.DoesNotContain($"action=\"/login/{provider.ToLowerInvariant()}\"", html);
        }
        var token = WebUtility.HtmlDecode(Regex.Match(html,
            "name=\"__RequestVerificationToken\"[^>]*value=\"([^\"]+)\"").Groups[1].Value);
        Assert.NotEmpty(token);
        using var response = await client.PostAsync("/login/google", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token,
            ["returnUrl"] = "/account"
        }));
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    /// <summary>Настроенный Google получает обычную форму; остальные способы серые также в управлении аккаунтом.</summary>
    [Fact]
    public async Task ConfiguredProviderRemainsUsableOnLoginAndAccountAsync()
    {
        using var factory = new AuthFactory(providerSettings: new Dictionary<string, string?>
        {
            ["Providers:Google:Enabled"] = "true",
            ["Providers:Google:ClientId"] = "test-client",
            ["Providers:Google:ClientSecret"] = "test-secret"
        });
        using var client = await factory.SignedInAsync();
        foreach (var path in new[] { "/login", "/account" })
        {
            var html = WebUtility.HtmlDecode(await client.GetStringAsync(path));
            Assert.Contains("action=\"/login/google\"", html);
            Assert.DoesNotContain("unavailable-Google", html);
            Assert.Contains("unavailable-Apple", html);
            Assert.Contains("unavailable-Yandex", html);
        }
    }
}
