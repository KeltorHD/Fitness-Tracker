using System.Net;
using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FitnessTracker.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет собственный OAuth/Identity-сервер через HTTP без внешних провайдеров.</summary>
[Trait("Category", "HTTP")]
public sealed class AuthenticationTests
{
    /// <summary>Без сессии или при блокировке prompt=none возвращает login_required без кода и браузерного редиректа на провайдера.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task SilentAuthorizationRequiresAnAllowedUserAsync(bool blocked)
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedInAsync();
        if (blocked)
        {
            using var scope = factory.Services.CreateScope();
            var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var user = await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
            Assert.True((await users.SetLockoutEnabledAsync(user, true)).Succeeded);
            Assert.True((await users.SetLockoutEndDateAsync(user, DateTimeOffset.MaxValue)).Succeeded);
        }
        else client.DefaultRequestHeaders.Remove("Cookie");
        var request = QueryHelpers.AddQueryString("/connect/authorize", new Dictionary<string, string?>
        {
            ["client_id"] = AuthConfiguration.ClientId,
            ["redirect_uri"] = AuthConfiguration.Callback,
            ["response_type"] = "code",
            ["scope"] = "profile",
            ["state"] = "expected-state",
            ["code_challenge"] = Base64UrlEncoder.Encode(SHA256.HashData("fixed-verifier-for-prompt-none-test"u8.ToArray())),
            ["code_challenge_method"] = "S256",
            ["prompt"] = "none"
        });

        using var response = await client.GetAsync(request);

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var query = QueryHelpers.ParseQuery(response.Headers.Location!.Query);
        Assert.Equal("login_required", query["error"].ToString());
        Assert.Equal("expected-state", query["state"].ToString());
        Assert.False(query.ContainsKey("code"));
    }

    /// <summary>API аккаунта требует bearer вместо cookie и не зависит от разрешений функций Backend.</summary>
    [Fact]
    public async Task AccountApiRequiresBearerTokenWithoutBackendScopesAsync()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedInAsync();
        using var cookieOnly = await client.GetAsync("/v1/account");
        Assert.Equal(HttpStatusCode.Unauthorized, cookieOnly.StatusCode);
        var code = await CodeAsync(client, "profile offline_access");
        using var issued = await ExchangeAsync(client, code.Code, code.Verifier);
        Assert.Equal(HttpStatusCode.OK, issued.StatusCode);
        var tokens = await issued.Content.ReadFromJsonAsync<JsonElement>();
        client.DefaultRequestHeaders.Authorization = new("Bearer", tokens.GetProperty("access_token").GetString());

        var access = new JwtSecurityTokenHandler().ReadJwtToken(tokens.GetProperty("access_token").GetString());
        Assert.DoesNotContain(access.Claims, claim => claim.Type == "scope" && claim.Value.Split(' ').Contains("backups"));

        using var profile = await client.GetAsync("/v1/account");
        using var deletion = await client.DeleteAsync("/v1/account");

        Assert.Equal(HttpStatusCode.OK, profile.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, deletion.StatusCode);
        Assert.Equal(1, factory.CleanupCalls);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.ToListAsync());
    }
    /// <summary>Заблокированному Identity-пользователю нельзя обменивать ранее выданные code/refresh tokens.</summary>
    [Fact]
    public async Task BlockedUserCannotExchangeCodeOrRefreshAsync()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedInAsync();
        var initial = await CodeAsync(client);
        using var issued = await ExchangeAsync(client, initial.Code, initial.Verifier);
        Assert.Equal(HttpStatusCode.OK, issued.StatusCode);
        var tokens = await issued.Content.ReadFromJsonAsync<JsonElement>();
        var pending = await CodeAsync(client);
        var subject = new JwtSecurityTokenHandler().ReadJwtToken(tokens.GetProperty("access_token").GetString()).Subject;
        using (var scope = factory.Services.CreateScope())
        {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var user = Assert.IsType<ApplicationUser>(await users.FindByIdAsync(subject));
            Assert.True((await users.SetLockoutEnabledAsync(user, true)).Succeeded);
            Assert.True((await users.SetLockoutEndDateAsync(user, DateTimeOffset.MaxValue)).Succeeded);
        }

        using var code = await ExchangeAsync(client, pending.Code, pending.Verifier);
        using var refresh = await RefreshAsync(client, tokens.GetProperty("refresh_token").GetString()!);

        Assert.Equal(HttpStatusCode.BadRequest, code.StatusCode);
        Assert.Equal("invalid_grant", (await code.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
        Assert.Equal(HttpStatusCode.BadRequest, refresh.StatusCode);
    }
    /// <summary>Создаёт настоящий authorization code и проверяет state callback.</summary>
    private static async Task<(string Code, string Verifier)> CodeAsync(HttpClient client, string scope = "openid profile offline_access")
    {
        var verifier = Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(32));
        var url = QueryHelpers.AddQueryString("/connect/authorize", new Dictionary<string, string?>
        {
            ["client_id"] = AuthConfiguration.ClientId,
            ["redirect_uri"] = AuthConfiguration.Callback,
            ["response_type"] = "code",
            ["scope"] = scope,
            ["state"] = "test-state",
            ["code_challenge"] = Base64UrlEncoder.Encode(SHA256.HashData(Encoding.ASCII.GetBytes(verifier))),
            ["code_challenge_method"] = "S256"
        });
        var response = await client.GetAsync(url);
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        var query = QueryHelpers.ParseQuery(response.Headers.Location!.Query);
        Assert.False(query.ContainsKey("error"), response.Headers.Location.ToString());
        Assert.Equal("test-state", query["state"].ToString());
        return (query["code"].ToString(), verifier);
    }

    /// <summary>Обменивает код через form-urlencoded token endpoint.</summary>
    private static Task<HttpResponseMessage> ExchangeAsync(HttpClient client, string code, string verifier) =>
        client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = AuthConfiguration.ClientId,
            ["redirect_uri"] = AuthConfiguration.Callback,
            ["code"] = code,
            ["code_verifier"] = verifier
        }));

    /// <summary>Запрашивает ротацию с явно переданным refresh token.</summary>
    private static Task<HttpResponseMessage> RefreshAsync(HttpClient client, string refresh) =>
        client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        { ["grant_type"] = "refresh_token", ["client_id"] = AuthConfiguration.ClientId, ["refresh_token"] = refresh }));

    /// <summary>Проверяет PKCE, одноразовость кода, тип/issuer/audience JWT и точный зарегистрированный callback.</summary>
    [Fact]
    public async Task CodeFlowEnforcesPkceAndExactRedirectUriAsync()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedInAsync();
        var (code, verifier) = await CodeAsync(client);
        var wrong = await ExchangeAsync(client, code, verifier + "wrong");
        Assert.Equal(HttpStatusCode.BadRequest, wrong.StatusCode);
        var fresh = await CodeAsync(client);
        using var token = await ExchangeAsync(client, fresh.Code, fresh.Verifier);
        Assert.Equal(HttpStatusCode.OK, token.StatusCode);
        var response = await token.Content.ReadFromJsonAsync<JsonElement>();
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(response.GetProperty("access_token").GetString());
        Assert.Equal("at+jwt", jwt.Header.Typ);
        Assert.Equal("RS256", jwt.Header.Alg);
        Assert.Equal("https://localhost/", jwt.Issuer);
        Assert.Contains(AuthConfiguration.Audience, jwt.Audiences);
        Assert.DoesNotContain(jwt.Claims, claim => claim.Type == "fitnesstracker:security_stamp");
        Assert.Equal(HttpStatusCode.BadRequest, (await ExchangeAsync(client, fresh.Code, fresh.Verifier)).StatusCode);
        var rejected = await client.GetAsync("/connect/authorize?client_id=fitnesstracker-ios&redirect_uri=https://attacker.test/&response_type=code&scope=profile");
        Assert.Equal(HttpStatusCode.BadRequest, rejected.StatusCode);
        var missingPkce = await client.GetAsync("/connect/authorize?client_id=fitnesstracker-ios&redirect_uri=https%3A%2F%2Fauth.example.com%2Fios%2Foauth%2Fcallback&response_type=code&scope=profile");
        Assert.Contains("invalid_request", missingPkce.Headers.Location?.ToString() ?? await missingPkce.Content.ReadAsStringAsync());
        var plainPkce = await client.GetAsync("/connect/authorize?client_id=fitnesstracker-ios&redirect_uri=https%3A%2F%2Fauth.example.com%2Fios%2Foauth%2Fcallback&response_type=code&scope=profile&code_challenge=abcdefghijklmnopqrstuvwxyz1234567890abcdefghijk&code_challenge_method=plain");
        Assert.Contains("invalid_request", plainPkce.Headers.Location?.ToString() ?? await plainPkce.Content.ReadAsStringAsync());
    }

    /// <summary>Повтор старого refresh token отзывает всю семью, включая уже выданный следующий refresh.</summary>
    [Fact]
    public async Task RefreshRotationRejectsReplayAndRevokesTheSessionFamilyAsync()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedInAsync();
        var code = await CodeAsync(client);
        var tokens = await (await ExchangeAsync(client, code.Code, code.Verifier)).Content.ReadFromJsonAsync<JsonElement>();
        var refresh = tokens.GetProperty("refresh_token").GetString()!;
        using var rotated = await RefreshAsync(client, refresh);
        Assert.Equal(HttpStatusCode.OK, rotated.StatusCode);
        var next = (await rotated.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("refresh_token").GetString()!;
        Assert.NotEqual(refresh, next);
        Assert.Equal(HttpStatusCode.BadRequest, (await RefreshAsync(client, refresh)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await RefreshAsync(client, next)).StatusCode);
    }

    /// <summary>Публичный iOS-клиент отзывает свой refresh token без client secret.</summary>
    [Fact]
    public async Task PublicClientCanRevokeRefreshTokenWithoutAClientSecretAsync()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedInAsync();
        var code = await CodeAsync(client);
        var tokens = await (await ExchangeAsync(client, code.Code, code.Verifier)).Content.ReadFromJsonAsync<JsonElement>();
        var refresh = tokens.GetProperty("refresh_token").GetString()!;
        using var revoked = await client.PostAsync("/connect/revoke", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = AuthConfiguration.ClientId,
            ["token"] = refresh,
            ["token_type_hint"] = "refresh_token"
        }));
        Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await RefreshAsync(client, refresh)).StatusCode);
    }

    /// <summary>Отказ Backend сохраняет аккаунт; повтор удаляет Identity, grants и payloads сессий.</summary>
    [Fact]
    public async Task AccountDeletionPreservesIdentityOnCleanupFailureAndRevokesTokensOnSuccessAsync()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedInAsync();
        var code = await CodeAsync(client);
        var tokens = await (await ExchangeAsync(client, code.Code, code.Verifier)).Content.ReadFromJsonAsync<JsonElement>();
        client.DefaultRequestHeaders.Authorization = new("Bearer", tokens.GetProperty("access_token").GetString());
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/v1/account")).StatusCode);
        factory.CleanupFails = true;
        Assert.Equal(HttpStatusCode.InternalServerError, (await client.DeleteAsync("/v1/account")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/v1/account")).StatusCode);
        factory.CleanupFails = false;
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync("/v1/account")).StatusCode);
        Assert.Equal(2, factory.CleanupCalls);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/v1/account")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await RefreshAsync(client, tokens.GetProperty("refresh_token").GetString()!)).StatusCode);
        using var scope = factory.Services.CreateScope();
        var subject = new JwtSecurityTokenHandler().ReadJwtToken(tokens.GetProperty("access_token").GetString()).Subject;
        await foreach (var token in scope.ServiceProvider.GetRequiredService<OpenIddict.Abstractions.IOpenIddictTokenManager>().FindBySubjectAsync(subject))
            Assert.Fail("Deleted account retains a token payload.");
        await foreach (var grant in scope.ServiceProvider.GetRequiredService<OpenIddict.Abstractions.IOpenIddictAuthorizationManager>().FindBySubjectAsync(subject))
            Assert.Fail("Deleted account retains an authorization.");
    }

    /// <summary>Совпадение email не связывает пользователей, а последний login нельзя отключить.</summary>
    [Fact]
    public async Task SameEmailDoesNotMergeProvidersAndLastLoginCannotBeRemovedAsync()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedInAsync();
        using var scope = factory.Services.CreateScope();
        var accounts = scope.ServiceProvider.GetRequiredService<ExternalAccounts>();
        var principal = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Email, "same@example.test")]));
        var google = await accounts.SignIn("Google", "google-subject", principal, default);
        var apple = await accounts.SignIn("Apple", "apple-subject", principal, default);
        Assert.NotEqual(google.Id, apple.Id);
        Assert.Equal(google.Id, (await accounts.SignIn("Google", "google-subject", principal, default)).Id);
        Assert.False(await accounts.Unlink(google, "Google", default));
        var manager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
        Assert.False((await manager.AddLoginAsync(apple, new UserLoginInfo("Google", "google-subject", "Google"))).Succeeded);
    }

    /// <summary>Успешная отвязка закрывает старые OAuth-сессии; запрет последнего login сохраняет действующие токены.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task ProviderRemovalRevokesExistingSessionsAsync(bool canUnlink)
    {
        // Arrange: две независимые OAuth-сессии одного пользователя и один либо два способа входа.
        using var factory = new AuthFactory();
        using var client = await factory.SignedInAsync();
        using var scope = factory.Services.CreateScope();
        var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
        var user = await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
        Assert.True((await users.AddLoginAsync(user, new UserLoginInfo("Google", "google-subject", "Google"))).Succeeded);
        if (canUnlink)
            Assert.True((await users.AddLoginAsync(user, new UserLoginInfo("Apple", "apple-subject", "Apple"))).Succeeded);
        var code = await CodeAsync(client);
        using var issued = await ExchangeAsync(client, code.Code, code.Verifier);
        Assert.Equal(HttpStatusCode.OK, issued.StatusCode);
        var tokens = await issued.Content.ReadFromJsonAsync<JsonElement>();
        var pending = await CodeAsync(client);
        client.DefaultRequestHeaders.Authorization = new("Bearer", tokens.GetProperty("access_token").GetString());
        using var initialProfile = await client.GetAsync("/v1/account");
        Assert.Equal(HttpStatusCode.OK, initialProfile.StatusCode);

        // Act: тот же сервис использует браузерный endpoint отвязки провайдера.
        var unlinked = await scope.ServiceProvider.GetRequiredService<ExternalAccounts>().Unlink(user, "Google", default);
        using var refresh = await RefreshAsync(client, tokens.GetProperty("refresh_token").GetString()!);
        using var exchange = await ExchangeAsync(client, pending.Code, pending.Verifier);
        using var profile = await client.GetAsync("/v1/account");

        // Assert: старые refresh/code/access Auth больше не работают только после фактического удаления login.
        Assert.Equal(canUnlink, unlinked);
        Assert.Equal(canUnlink ? HttpStatusCode.BadRequest : HttpStatusCode.OK, refresh.StatusCode);
        Assert.Equal(canUnlink ? HttpStatusCode.BadRequest : HttpStatusCode.OK, exchange.StatusCode);
        Assert.Equal(canUnlink ? HttpStatusCode.Unauthorized : HttpStatusCode.OK, profile.StatusCode);
        var remaining = await users.GetLoginsAsync(user);
        Assert.Single(remaining);
        Assert.Equal(canUnlink ? "Apple" : "Google", remaining[0].LoginProvider);
    }

    /// <summary>Запрос со старой cookie, начатый до отвязки, не создаёт рабочую сессию после отзыва.</summary>
    [Fact]
    public async Task ProviderRemovalRejectsSessionIssuedByInFlightCookieAsync()
    {
        // Arrange: cookie проверяется до отвязки, а authorization сохраняется уже после неё.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(1));
        var pause = new PausedCookieAuthentication(deadline.Token);
        using var factory = new AuthFactory(claimsTransformation: pause);
        using var client = await factory.SignedInAsync();
        using var scope = factory.Services.CreateScope();
        var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
        var user = await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
        Assert.True((await users.AddLoginAsync(user, new UserLoginInfo("Google", "google-subject", "Google"))).Succeeded);
        Assert.True((await users.AddLoginAsync(user, new UserLoginInfo("Apple", "apple-subject", "Apple"))).Succeeded);

        // Act: управляем порядок через сигнал настоящего authentication middleware, без задержек.
        var pending = CodeAsync(client);
        try
        {
            await pause.CookieValidated.WaitAsync(deadline.Token);
            Assert.True(await scope.ServiceProvider.GetRequiredService<ExternalAccounts>().Unlink(user, "Google", deadline.Token));
        }
        finally
        {
            pause.Resume();
            await pending.WaitAsync(deadline.Token);
        }
        var code = await pending;
        using var exchange = await ExchangeAsync(client, code.Code, code.Verifier);

        // Assert: даже сохранённый после массового отзыва code не продлевает доступ старой cookie.
        Assert.Equal(HttpStatusCode.BadRequest, exchange.StatusCode);
        Assert.Equal("invalid_grant", (await exchange.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
    }

    /// <summary>Вход требует antiforgery; внешний returnUrl не попадает в браузерную форму.</summary>
    [Fact]
    public async Task ProviderSelectionRequiresAntiforgeryAndLocalReturnUrlAsync()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedInAsync();
        var response = await client.PostAsync("/login/google", new FormUrlEncodedContent(new Dictionary<string, string>()));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var page = await client.GetStringAsync("/login?returnUrl=https://attacker.test");
        Assert.DoesNotContain("attacker.test", page);
    }
}
