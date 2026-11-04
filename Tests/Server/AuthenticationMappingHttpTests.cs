using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FitnessTracker.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет реальные MVC binding/Mapster/service границы без внешних OAuth-провайдеров.</summary>
[Trait("Category", "HTTP")]
public sealed class AuthenticationMappingHttpTests
{
    /// <summary>Лишние поля формы не меняют чужую identity, а публичный профиль сохраняет точный JSON-контракт.</summary>
    [Fact]
    public async Task RegistrationRejectsOverpostingAndProfileOnlyContainsPublicFieldsAsync()
    {
        // Arrange: существующий независимый аккаунт и анонимный браузер нового пользователя.
        using var factory = new AuthFactory();
        using var client = await CredentialsTests.AnonymousClientAsync(factory);
        string existingId;
        string existingHash;
        using (var scope = factory.Services.CreateScope())
        {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var user = new ApplicationUser { UserName = Guid.NewGuid().ToString("N"), DisplayName = "Existing" };
            Assert.True((await users.CreateAsync(user, "Existing-password-123")).Succeeded);
            existingId = user.Id;
            existingHash = user.PasswordHash!;
        }

        // Act: клиент пытается назначить доверенные поля, отсутствующие в разрешённой request/command модели.
        using var registration = await CredentialsTests.PostAsync(client, "/register", "/register", new()
        {
            ["email"] = "new@fitness.test",
            ["password"] = "New-account-password-123",
            ["confirmPassword"] = "New-account-password-123",
            ["Id"] = existingId,
            ["UserId"] = existingId,
            ["EmailConfirmed"] = "true",
            ["SecurityStamp"] = "injected-stamp",
            ["PasswordHash"] = "injected-hash",
            ["DisplayName"] = "Injected name"
        });
        Assert.Equal(HttpStatusCode.Redirect, registration.StatusCode);
        using (var scope = factory.Services.CreateScope())
        {
            var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            Assert.Equal(2, await database.Users.CountAsync());
            Assert.Equal(existingHash, (await database.Users.SingleAsync(user => user.Id == existingId)).PasswordHash);
            var created = await database.Users.SingleAsync(user => user.Id != existingId);
            Assert.False(created.EmailConfirmed);
            Assert.NotEqual("injected-stamp", created.SecurityStamp);
            Assert.NotEqual("injected-hash", created.PasswordHash);
            Assert.Equal("Пользователь", created.DisplayName);
        }

        // Assert: настоящий OAuth exchange ведёт к профилю нового владельца, без приватных Identity полей.
        var verifier = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
        var authorizeUrl = QueryHelpers.AddQueryString("/connect/authorize", new Dictionary<string, string?>
        {
            ["client_id"] = AuthConfiguration.ClientId,
            ["redirect_uri"] = AuthConfiguration.Callback,
            ["response_type"] = "code",
            ["scope"] = "profile offline_access backups",
            ["state"] = "mapping-state",
            ["code_challenge"] = WebEncoders.Base64UrlEncode(SHA256.HashData(Encoding.ASCII.GetBytes(verifier))),
            ["code_challenge_method"] = "S256"
        });
        using var authorization = await client.GetAsync(authorizeUrl);
        Assert.Equal(HttpStatusCode.Redirect, authorization.StatusCode);
        var callback = Assert.IsType<Uri>(authorization.Headers.Location);
        var query = QueryHelpers.ParseQuery(callback.Query);
        Assert.Equal("mapping-state", query["state"].ToString());
        using var exchange = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = AuthConfiguration.ClientId,
            ["redirect_uri"] = AuthConfiguration.Callback,
            ["code"] = query["code"].ToString(),
            ["code_verifier"] = verifier
        }));
        Assert.Equal(HttpStatusCode.OK, exchange.StatusCode);
        var tokens = await exchange.Content.ReadFromJsonAsync<JsonElement>();
        client.DefaultRequestHeaders.Authorization = new("Bearer", tokens.GetProperty("access_token").GetString());
        using var response = await client.GetAsync("/v1/account");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var profile = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(new[] { "createdAt", "id", "logins", "name" }, profile.EnumerateObject().Select(property => property.Name).Order().ToArray());
        Assert.NotEqual(existingId, profile.GetProperty("id").GetString());
        Assert.Equal("Пользователь", profile.GetProperty("name").GetString());
        Assert.Equal("Email", Assert.Single(profile.GetProperty("logins").EnumerateArray()).GetString());
    }

    /// <summary>HTTP-маппинг сохраняет сообщение ошибки после redirect и не возвращает credential в HTML.</summary>
    [Fact]
    public async Task FailedPasswordLoginKeepsSafeMessageAcrossRedirectAsync()
    {
        using var factory = new AuthFactory();
        using var client = await CredentialsTests.AnonymousClientAsync(factory);
        using var login = await CredentialsTests.PostAsync(client, "/login", "/login/password", new()
        { ["email"] = "unknown@fitness.test", ["password"] = "private-password-marker" });

        Assert.Equal(HttpStatusCode.Redirect, login.StatusCode);
        using var page = await client.GetAsync(Assert.IsType<Uri>(login.Headers.Location));
        Assert.Equal(HttpStatusCode.OK, page.StatusCode);
        var html = WebUtility.HtmlDecode(await page.Content.ReadAsStringAsync());
        Assert.Contains("Не удалось войти. Проверьте email и пароль или попробуйте позже.", html);
        Assert.DoesNotContain("private-password-marker", html);
        Assert.DoesNotContain("unknown@fitness.test", html);
    }
}
