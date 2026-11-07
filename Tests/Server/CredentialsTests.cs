using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using FitnessTracker.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using OpenIddict.Abstractions;
using OpenIddict.EntityFrameworkCore.Models;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет парольные и passkey-сценарии через настоящие MVC, Identity, antiforgery и SQLite.</summary>
[Trait("Category", "HTTP")]
public sealed class CredentialsTests
{
    /// <summary>Регистрация не подтверждает email, пароль хранится как hash, нормализованный повтор не создаёт аккаунт.</summary>
    [Fact]
    public async Task PasswordRegistrationAndLoginDoNotRequireEmailConfirmationAsync()
    {
        // Arrange: полностью пустая Identity-БД и форма с настоящим antiforgery cookie/token.
        using var factory = new AuthFactory();
        using var client = await AnonymousClientAsync(factory);
        using var created = await PostAsync(client, "/register", "/register", new()
        { ["email"] = "Example@fitness.test", ["password"] = "a-long-test-password", ["confirmPassword"] = "a-long-test-password", ["returnUrl"] = "https://attacker.test/" });
        Assert.Equal(HttpStatusCode.Redirect, created.StatusCode);
        Assert.Equal("/account", created.Headers.Location?.OriginalString);
        using (var scope = factory.Services.CreateScope())
        {
            var user = await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
            Assert.False(user.EmailConfirmed);
            Assert.NotNull(user.PasswordHash);
            Assert.NotEqual("a-long-test-password", user.PasswordHash);
            Assert.True(await scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>().CheckPasswordAsync(user, "a-long-test-password"));
        }

        // Act: выход в браузере, вход с другим регистром email, повторная регистрация того же локального адреса.
        using var logout = await PostAsync(client, "/account", "/account/logout", new());
        using var loggedIn = await PostAsync(client, "/login", "/login/password", new()
        { ["email"] = "example@FITNESS.test", ["password"] = "a-long-test-password" });
        Assert.Equal(HttpStatusCode.Redirect, loggedIn.StatusCode);
        using var duplicate = await PostAsync(client, "/register", "/register", new()
        { ["email"] = "example@fitness.test", ["password"] = "another-long-password", ["confirmPassword"] = "another-long-password" });

        // Assert: аккаунт один, повторный пароль не показывается в HTML.
        Assert.Equal(HttpStatusCode.BadRequest, duplicate.StatusCode);
        Assert.DoesNotContain("another-long-password", await duplicate.Content.ReadAsStringAsync());
        using var verification = factory.Services.CreateScope();
        Assert.Equal(1, await verification.ServiceProvider.GetRequiredService<AuthDbContext>().Users.CountAsync());
    }

    /// <summary>Вход не раскрывает существование email; пять ошибок блокируют даже верный пароль.</summary>
    [Fact]
    public async Task PasswordLoginEnforcesLockoutAndGenericErrorsAsync()
    {
        using var factory = new AuthFactory();
        using var client = await AnonymousClientAsync(factory);
        using (var scope = factory.Services.CreateScope())
        {
            var accounts = scope.ServiceProvider.GetRequiredService<EmailAccounts>();
            var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            Assert.True((await users.CreateAsync(accounts.NewUser("lock@fitness.test"), "correct-long-password")).Succeeded);
        }
        for (var index = 0; index < 5; index++)
        {
            using var rejected = await PostAsync(client, "/login", "/login/password", new()
            { ["email"] = "lock@fitness.test", ["password"] = "incorrect-password" });
            Assert.Equal(HttpStatusCode.Redirect, rejected.StatusCode);
        }
        using var locked = await PostAsync(client, "/login", "/login/password", new()
        { ["email"] = "lock@fitness.test", ["password"] = "correct-long-password" });
        Assert.StartsWith("/login?", locked.Headers.Location?.OriginalString);
        using var account = await client.GetAsync("/account");
        Assert.Equal(HttpStatusCode.Redirect, account.StatusCode);
        using var scope2 = factory.Services.CreateScope();
        var manager = scope2.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
        Assert.True(await manager.IsLockedOutAsync(await scope2.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync()));
    }

    /// <summary>Парольные и passkey POST нельзя выполнять без CSRF-защиты.</summary>
    [Theory]
    [InlineData("/register")]
    [InlineData("/login/password")]
    [InlineData("/passkeys/register/options")]
    [InlineData("/passkeys/login/options")]
    public async Task CredentialEndpointsRequireAntiforgeryAsync(string endpoint)
    {
        using var factory = new AuthFactory();
        using var client = await AnonymousClientAsync(factory);
        using var response = await client.PostAsync(endpoint, new FormUrlEncodedContent(new Dictionary<string, string>()));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.ToListAsync());
    }

    /// <summary>Парольный аккаунт не объединяется с внешним профилем, даже если у них одинаковый email.</summary>
    [Fact]
    public async Task LocalRegistrationDoesNotMergeExternalEmailAsync()
    {
        using var factory = new AuthFactory();
        using var client = await AnonymousClientAsync(factory);
        using (var scope = factory.Services.CreateScope())
        {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var external = new ApplicationUser { UserName = Guid.NewGuid().ToString("N"), Email = "same@fitness.test" };
            Assert.True((await users.CreateAsync(external)).Succeeded);
            Assert.True((await users.AddLoginAsync(external, new UserLoginInfo("Google", "unrelated-subject", "Google"))).Succeeded);
        }
        using var created = await PostAsync(client, "/register", "/register", new()
        { ["email"] = "same@fitness.test", ["password"] = "a-long-test-password", ["confirmPassword"] = "a-long-test-password" });
        Assert.Equal(HttpStatusCode.Redirect, created.StatusCode);
        using var verification = factory.Services.CreateScope();
        var database = verification.ServiceProvider.GetRequiredService<AuthDbContext>();
        Assert.Equal(2, await database.Users.CountAsync());
        Assert.Single(await database.UserLogins.ToListAsync());
    }

    /// <summary>Реальная ES256 регистрация создаёт аккаунт без пароля; assertion входит, повтор challenge отклоняется.</summary>
    [Fact]
    public async Task PasskeySupportsPasswordlessRegistrationAndSignInAsync()
    {
        // Arrange: программный аутентификатор подписывает реальные стандартные WebAuthn-данные.
        using var factory = new AuthFactory();
        using var client = await AnonymousClientAsync(factory);
        using var authenticator = new SoftwarePasskey();
        using var optionsResponse = await PostAsync(client, "/register", "/passkeys/register/options", new() { ["email"] = "passkey@fitness.test" });
        Assert.Equal(HttpStatusCode.OK, optionsResponse.StatusCode);
        var options = await optionsResponse.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("localhost", options.GetProperty("rp").GetProperty("id").GetString());
        Assert.Equal("required", options.GetProperty("authenticatorSelection").GetProperty("userVerification").GetString());
        using var registered = await PostAsync(client, "/register", "/passkeys/register", new() { ["credential"] = authenticator.Create(options) });
        Assert.Equal(HttpStatusCode.OK, registered.StatusCode);
        using (var scope = factory.Services.CreateScope())
        {
            var user = await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
            var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            Assert.False(user.EmailConfirmed);
            Assert.False(await users.HasPasswordAsync(user));
            Assert.Single(await users.GetPasskeysAsync(user));
        }

        // Act: после выхода пароль не нужен; сервер проверяет подпись сохранённым публичным ключом.
        using var logout = await PostAsync(client, "/account", "/account/logout", new());
        // Парольные попытки не блокируют пользователя, у которого есть только passkey.
        for (var attempt = 0; attempt < 5; attempt++)
        {
            using var passwordAttempt = await PostAsync(client, "/login", "/login/password", new()
            { ["email"] = "passkey@fitness.test", ["password"] = "incorrect-password" });
            Assert.Equal(HttpStatusCode.Redirect, passwordAttempt.StatusCode);
        }
        using var duplicateOptions = await PostAsync(client, "/register", "/passkeys/register/options", new() { ["email"] = "different@fitness.test" });
        using var duplicateKey = await PostAsync(client, "/register", "/passkeys/register", new()
        { ["credential"] = authenticator.Create(await duplicateOptions.Content.ReadFromJsonAsync<JsonElement>()) });
        Assert.Equal(HttpStatusCode.BadRequest, duplicateKey.StatusCode);
        // Create перезаписал тестовый user handle: восстанавливаем исходный, как в реальном аутентификаторе.
        _ = authenticator.Create(options);
        using var request = await PostAsync(client, "/login", "/passkeys/login/options", new());
        var credential = authenticator.Assert(await request.Content.ReadFromJsonAsync<JsonElement>(), counter: 0);
        using var signedIn = await PostAsync(client, "/login", "/passkeys/login", new() { ["credential"] = credential });
        Assert.Equal(HttpStatusCode.OK, signedIn.StatusCode);
        using var account = await client.GetAsync("/account");
        Assert.Equal(HttpStatusCode.OK, account.StatusCode);
        using var missingId = await PostAsync(client, "/account", "/account/passkeys/remove", new());
        Assert.Equal(HttpStatusCode.BadRequest, missingId.StatusCode);

        // Assert: нельзя удалить единственный credential и повторно использовать уже предъявленный challenge.
        using var scope2 = factory.Services.CreateScope();
        var user2 = await scope2.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
        var key = Assert.Single(await scope2.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>().GetPasskeysAsync(user2));
        using var lastKey = await PostAsync(client, "/account", "/account/passkeys/remove", new()
        { ["credentialId"] = Microsoft.AspNetCore.WebUtilities.WebEncoders.Base64UrlEncode(key.CredentialId) });
        Assert.Equal(HttpStatusCode.Conflict, lastKey.StatusCode);
        using var replay = await PostAsync(client, "/login", "/passkeys/login", new() { ["credential"] = credential });
        Assert.Equal(HttpStatusCode.BadRequest, replay.StatusCode);
    }

    /// <summary>Чужой origin и отсутствие user verification не создают профиль даже с корректной структурой attestation.</summary>
    [Theory]
    [InlineData("https://attacker.test", true)]
    [InlineData("https://sub.localhost", true)]
    [InlineData("https://localhost", false)]
    public async Task PasskeyRegistrationRejectsWrongOriginAndMissingVerificationAsync(string origin, bool verified)
    {
        using var factory = new AuthFactory();
        using var client = await AnonymousClientAsync(factory);
        using var authenticator = new SoftwarePasskey();
        using var request = await PostAsync(client, "/register", "/passkeys/register/options", new() { ["email"] = "rejected@fitness.test" });
        var options = await request.Content.ReadFromJsonAsync<JsonElement>();
        using var response = await PostAsync(client, "/register", "/passkeys/register", new()
        { ["credential"] = authenticator.Create(options, origin, verified) });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.ToListAsync());
    }

    /// <summary>Неверная подпись, origin, RP и отсутствие UV не дают сессию; удаление ключа отзывает старый grant.</summary>
    [Fact]
    public async Task AddedPasskeyValidatesAssertionsAndRemovalRevokesSessionsAsync()
    {
        using var factory = new AuthFactory();
        using var client = await AnonymousClientAsync(factory);
        using var authenticator = new SoftwarePasskey();
        using var registered = await PostAsync(client, "/register", "/register", new()
        { ["email"] = "enroll@fitness.test", ["password"] = "a-long-test-password", ["confirmPassword"] = "a-long-test-password" });
        Assert.Equal(HttpStatusCode.Redirect, registered.StatusCode);
        using var options = await PostAsync(client, "/account", "/account/passkeys/options", new());
        Assert.Equal(HttpStatusCode.OK, options.StatusCode);
        using var enrollment = await PostAsync(client, "/account", "/account/passkeys", new()
        { ["credential"] = authenticator.Create(await options.Content.ReadFromJsonAsync<JsonElement>()), ["name"] = "Мой iPhone" });
        Assert.Equal(HttpStatusCode.OK, enrollment.StatusCode);
        using var logout = await PostAsync(client, "/account", "/account/logout", new());
        // Каждому отказу соответствует новый challenge: исключаем отказ только из-за повторного запроса.
        for (var attempt = 0; attempt < 4; attempt++)
        {
            using var challenge = await PostAsync(client, "/login", "/passkeys/login/options", new());
            Assert.Equal(HttpStatusCode.OK, challenge.StatusCode);
            var json = await challenge.Content.ReadFromJsonAsync<JsonElement>();
            var credential = authenticator.Assert(json,
                rp: attempt == 0 ? "attacker.test" : "localhost",
                origin: attempt == 1 ? "https://attacker.test" : "https://localhost",
                userVerified: attempt != 2, corruptSignature: attempt == 3);
            using var rejected = await PostAsync(client, "/login", "/passkeys/login", new() { ["credential"] = credential });
            Assert.Equal(HttpStatusCode.BadRequest, rejected.StatusCode);
        }
        using var request = await PostAsync(client, "/login", "/passkeys/login/options", new());
        var assertion = authenticator.Assert(await request.Content.ReadFromJsonAsync<JsonElement>());
        using var success = await PostAsync(client, "/login", "/passkeys/login", new() { ["credential"] = assertion });
        Assert.Equal(HttpStatusCode.OK, success.StatusCode);
        string id;
        string grantId;
        string oldStamp;
        using (var scope = factory.Services.CreateScope())
        {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var user = await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
            var key = Assert.Single(await users.GetPasskeysAsync(user));
            Assert.Equal("Мой iPhone", key.Name);
            id = Microsoft.AspNetCore.WebUtilities.WebEncoders.Base64UrlEncode(key.CredentialId);
            oldStamp = user.SecurityStamp!;
            var manager = scope.ServiceProvider.GetRequiredService<IOpenIddictAuthorizationManager>();
            var grant = await manager.CreateAsync(new OpenIddictAuthorizationDescriptor
            { Subject = user.Id, Status = OpenIddictConstants.Statuses.Valid, Type = OpenIddictConstants.AuthorizationTypes.Permanent });
            grantId = (await manager.GetIdAsync(grant))!;
        }
        using var removed = await PostAsync(client, "/account", "/account/passkeys/remove", new() { ["credentialId"] = id });
        Assert.Equal(HttpStatusCode.Redirect, removed.StatusCode);
        using var verification = factory.Services.CreateScope();
        var database = verification.ServiceProvider.GetRequiredService<AuthDbContext>();
        var profile = await database.Users.SingleAsync();
        Assert.NotEqual(oldStamp, profile.SecurityStamp);
        Assert.Empty(await verification.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>().GetPasskeysAsync(profile));
        Assert.Equal(OpenIddictConstants.Statuses.Revoked,
            (await database.Set<OpenIddictEntityFrameworkCoreAuthorization>().SingleAsync(grant => grant.Id == grantId)).Status);
    }

    /// <summary>Создаёт анонимный браузер с отдельными cookies и пустую одноразовую SQLite-БД.</summary>
    internal static async Task<HttpClient> AnonymousClientAsync(AuthFactory factory)
    {
        var client = factory.CreateClient(new WebApplicationFactoryClientOptions
        { BaseAddress = new Uri("https://localhost"), AllowAutoRedirect = false });
        using var scope = factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Database.EnsureCreatedAsync();
        await AuthConfiguration.RegisterClient(scope.ServiceProvider, scope.ServiceProvider.GetRequiredService<IConfiguration>());
        return client;
    }

    /// <summary>Загружает настоящий antiforgery token из Razor-формы и отправляет действие через тот же браузер.</summary>
    internal static async Task<HttpResponseMessage> PostAsync(HttpClient client, string page, string endpoint, Dictionary<string, string> fields)
    {
        using var form = await client.GetAsync(page);
        Assert.Equal(HttpStatusCode.OK, form.StatusCode);
        var html = await form.Content.ReadAsStringAsync();
        var match = Regex.Match(html, "name=\"__RequestVerificationToken\"[^>]*value=\"([^\"]+)\"");
        Assert.True(match.Success, "Razor did not render an antiforgery token.");
        fields["__RequestVerificationToken"] = WebUtility.HtmlDecode(match.Groups[1].Value);
        return await client.PostAsync(endpoint, new FormUrlEncodedContent(fields));
    }
}
