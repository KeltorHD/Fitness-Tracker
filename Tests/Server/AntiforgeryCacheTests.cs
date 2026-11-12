using System.Net;
using System.Net.Http.Headers;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Xunit;
using static FitLife.Server.Tests.CredentialsTests;

namespace FitLife.Server.Tests;

/// <summary>Проверяет запрет кеширования форм без предупреждения о перезаписи заголовков antiforgery.</summary>
[Trait("Category", "HTTP")]
public sealed class AntiforgeryCacheTests
{
    private const string ANTIFORGERY_CATEGORY = "Microsoft.AspNetCore.Antiforgery.DefaultAntiforgery";

    /// <summary>Анонимные и авторизованные формы содержат токен и безопасные заголовки без события 8.</summary>
    [Theory]
    [InlineData("/login", false)]
    [InlineData("/register", false)]
    [InlineData("/email/verify", false)]
    [InlineData("/email/confirm?userId=00000000-0000-0000-0000-000000000001&code=synthetic_token", false)]
    [InlineData("/account", true)]
    public async Task FormsDoNotOverrideAntiforgeryCacheHeadersAsync(string path, bool signedIn)
    {
        using var logs = new TestEmailLogs(ANTIFORGERY_CATEGORY);
        using var factory = new AuthFactory(providerSettings: logs.Settings);
        using var client = signedIn ? await factory.SignedInAsync() : await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using var response = await client.GetAsync(path);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("name=\"__RequestVerificationToken\"", await response.Content.ReadAsStringAsync());
        AssertPrivateResponse(response);
        Assert.DoesNotContain(logs.Entries, entry => entry.EventId == 8);
    }

    /// <summary>Повтор формы после серверной ошибки валидации также сохраняет защиту и чистые логи.</summary>
    [Fact]
    public async Task ValidationResponseDoesNotOverrideAntiforgeryCacheHeadersAsync()
    {
        using var logs = new TestEmailLogs(ANTIFORGERY_CATEGORY);
        using var factory = new AuthFactory(providerSettings: logs.Settings);
        using var client = await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using var response = await PostAsync(client, "/register", "/register", new()
        { ["email"] = "new@example.com", ["password"] = "short", ["confirmPassword"] = "short" });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var html = await response.Content.ReadAsStringAsync();
        Assert.Contains("name=\"__RequestVerificationToken\"", html);
        Assert.Contains("Пароль должен содержать от 12 до 128 символов.", WebUtility.HtmlDecode(html));
        AssertPrivateResponse(response);
        Assert.DoesNotContain(logs.Entries, entry => entry.EventId == 8);
        Assert.Empty(factory.EmailSender.Messages);
    }

    /// <summary>Проверяет семантику HTTP-запрета хранения и повторного использования ответа без ревалидации.</summary>
    private static void AssertPrivateResponse(HttpResponseMessage response)
    {
        var cache = Assert.IsType<CacheControlHeaderValue>(response.Headers.CacheControl);
        Assert.True(cache.NoCache);
        Assert.True(cache.NoStore);
        Assert.Contains(response.Headers.Pragma, directive => directive.Name == "no-cache");
    }
}
