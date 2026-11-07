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

    /// <summary>Регистрация сохраняет доступность провайдеров, CSRF и безопасное продолжение после ошибки пароля.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task RegistrationPreservesProviderAvailabilityAfterValidationFailureAsync(bool googleEnabled)
    {
        // Arrange: только полностью настроенный и включённый Google доступен для входа.
        using var factory = new AuthFactory(providerSettings: new Dictionary<string, string?>
        {
            ["Providers:Google:Enabled"] = googleEnabled.ToString(),
            ["Providers:Google:ClientId"] = "test-client",
            ["Providers:Google:ClientSecret"] = "test-secret"
        });
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            BaseAddress = new Uri("https://localhost"),
            AllowAutoRedirect = false
        });
        var initial = WebUtility.HtmlDecode(await client.GetStringAsync("/register?returnUrl=%2Faccount%3Fscreen%3Dkeys"));
        var token = Regex.Match(initial, "name=\"__RequestVerificationToken\"[^>]*value=\"([^\"]+)\"").Groups[1].Value;
        Assert.NotEmpty(token);

        // Act: пароль не проходит проверку; сервер возвращает ту же форму без credentials.
        using var response = await client.PostAsync("/register", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = token,
            ["email"] = "design@example.com",
            ["password"] = "short-private-password",
            ["confirmPassword"] = "different-private-password",
            ["returnUrl"] = "/account?screen=keys"
        }));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var repeated = WebUtility.HtmlDecode(await response.Content.ReadAsStringAsync());

        // Assert: в обеих версиях формы действуют прежние правила провайдеров и навигации.
        foreach (var html in new[] { initial, repeated })
        {
            Assert.Equal(googleEnabled, html.Contains("action=\"/login/google\"", StringComparison.Ordinal));
            Assert.Equal(!googleEnabled, html.Contains("unavailable-Google", StringComparison.Ordinal));
            Assert.Contains("unavailable-Apple", html);
            Assert.Contains("unavailable-Yandex", html);
            Assert.Contains("name=\"returnUrl\" value=\"/account?screen=keys\"", html);
            Assert.DoesNotContain("short-private-password", html);
            Assert.DoesNotContain("different-private-password", html);
            // Пустой ValidationSummary не должен добавлять inline style, запрещённый CSP.
            Assert.DoesNotContain("style=\"", html);
        }
        Assert.Contains("value=\"design@example.com\"", repeated);
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
