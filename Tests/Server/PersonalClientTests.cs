using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FitnessTracker.Authentication;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using OpenIddict.Abstractions;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет отдельный Personal Team client, точный callback, PKCE и изоляцию от HTTPS client.</summary>
[Trait("Category", "HTTP")]
public sealed class PersonalClientTests
{
    private const string PERSONAL_SCHEME = "com.example.fitnesstracker";
    private const string PERSONAL_CALLBACK = PERSONAL_SCHEME + ":/ios/oauth/callback";

    /// <summary>Полный code/refresh/revoke flow работает без Apple App ID и сохраняет прежний HTTPS client.</summary>
    [Fact]
    public async Task PersonalFlowUsesPkceAndRotatesAndRevokesItsOwnTokensAsync()
    {
        // Arrange: Identity cookie настоящего пользователя и отдельный public client без AASA.
        using var factory = new AuthFactory(personalCallbackScheme: PERSONAL_SCHEME);
        using var client = await factory.SignedInAsync();

        // Act: обычный PKCE обмен с private-use URI вместо HTTPS redirect.
        var pending = await CodeAsync(client);
        using var issued = await ExchangeAsync(client, pending.Code, pending.Verifier);
        Assert.Equal(HttpStatusCode.OK, issued.StatusCode);
        var tokens = await issued.Content.ReadFromJsonAsync<JsonElement>();
        var access = tokens.GetProperty("access_token").GetString()!;
        var refresh = tokens.GetProperty("refresh_token").GetString()!;
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(access);
        Assert.Equal("RS256", jwt.Header.Alg);
        Assert.Equal("https://localhost/", jwt.Issuer);
        Assert.Contains(AuthConfiguration.Audience, jwt.Audiences);
        client.DefaultRequestHeaders.Authorization = new("Bearer", access);
        using var profile = await client.GetAsync("/v1/account");
        Assert.Equal(HttpStatusCode.OK, profile.StatusCode);

        using var wrongClient = await RefreshAsync(client, refresh, AuthConfiguration.ClientId);
        Assert.Equal(HttpStatusCode.BadRequest, wrongClient.StatusCode);
        using var rotation = await RefreshAsync(client, refresh);
        Assert.Equal(HttpStatusCode.OK, rotation.StatusCode);
        var replacement = await rotation.Content.ReadFromJsonAsync<JsonElement>();
        var rotated = replacement.GetProperty("refresh_token").GetString()!;
        Assert.NotEqual(refresh, rotated);
        using var revoked = await client.PostAsync("/connect/revoke", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = AuthConfiguration.PersonalClientId,
            ["token"] = rotated,
            ["token_type_hint"] = "refresh_token"
        }));
        Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        using var rejected = await RefreshAsync(client, rotated);
        Assert.Equal(HttpStatusCode.BadRequest, rejected.StatusCode);

        // Assert: настройки HTTPS client не расширились до private-use callback.
        using var scope = factory.Services.CreateScope();
        var manager = scope.ServiceProvider.GetRequiredService<IOpenIddictApplicationManager>();
        var full = await manager.FindByClientIdAsync(AuthConfiguration.ClientId);
        Assert.NotNull(full);
        Assert.Equal(AuthConfiguration.Callback, Assert.Single(await manager.GetRedirectUrisAsync(full)));
    }

    /// <summary>Код нельзя повторить, обменять другим клиентом, с другим verifier или другим callback.</summary>
    [Theory]
    [InlineData("verifier")]
    [InlineData("client")]
    [InlineData("redirect")]
    [InlineData("replay")]
    public async Task RejectsCodeMisuseAsync(string misuse)
    {
        using var factory = new AuthFactory(personalCallbackScheme: PERSONAL_SCHEME);
        using var client = await factory.SignedInAsync();
        var pending = await CodeAsync(client);
        if (misuse == "replay")
        {
            using var accepted = await ExchangeAsync(client, pending.Code, pending.Verifier);
            Assert.Equal(HttpStatusCode.OK, accepted.StatusCode);
        }
        using var rejected = await ExchangeAsync(client, pending.Code,
            misuse == "verifier" ? pending.Verifier + "wrong" : pending.Verifier,
            misuse == "client" ? AuthConfiguration.ClientId : AuthConfiguration.PersonalClientId,
            misuse == "redirect" ? AuthConfiguration.Callback : PERSONAL_CALLBACK);
        Assert.Equal(HttpStatusCode.BadRequest, rejected.StatusCode);
        Assert.False((await rejected.Content.ReadFromJsonAsync<JsonElement>()).TryGetProperty("access_token", out _));
    }

    /// <summary>Каждый клиент принимает только собственный callback; неизвестные схемы и пути не дают code.</summary>
    [Theory]
    [InlineData(AuthConfiguration.ClientId, PERSONAL_CALLBACK)]
    [InlineData(AuthConfiguration.PersonalClientId, AuthConfiguration.Callback)]
    [InlineData(AuthConfiguration.PersonalClientId, "com.example.other:/ios/oauth/callback")]
    [InlineData(AuthConfiguration.PersonalClientId, "com.example.fitnesstracker://host/ios/oauth/callback")]
    [InlineData(AuthConfiguration.PersonalClientId, "com.example.fitnesstracker:/other")]
    public async Task RejectsUnregisteredRedirectAsync(string clientId, string redirect)
    {
        using var factory = new AuthFactory(personalCallbackScheme: PERSONAL_SCHEME);
        using var client = await factory.SignedInAsync();
        using var response = await client.GetAsync(AuthorizationUrl(clientId, redirect, "challenge", "S256"));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Null(response.Headers.Location);
    }

    /// <summary>Personal client требует PKCE S256 даже при верной Identity cookie.</summary>
    [Theory]
    [InlineData(null, null)]
    [InlineData("abcdefghijklmnopqrstuvwxyz1234567890abcdefghijk", "plain")]
    public async Task RequiresS256Async(string? challenge, string? method)
    {
        using var factory = new AuthFactory(personalCallbackScheme: PERSONAL_SCHEME);
        using var client = await factory.SignedInAsync();
        using var response = await client.GetAsync(AuthorizationUrl(AuthConfiguration.PersonalClientId, PERSONAL_CALLBACK, challenge, method));
        if (response.Headers.Location is { } location)
            Assert.Equal("invalid_request", QueryHelpers.ParseQuery(location.Query)["error"].ToString());
        else
        {
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.Contains("invalid_request", await response.Content.ReadAsStringAsync());
        }
    }

    /// <summary>Пустая настройка не оставляет доступным ранее включённый Personal client и его refresh tokens.</summary>
    [Fact]
    public async Task DisablingPersonalClientRemovesItsRegistrationAndTokensAsync()
    {
        using var factory = new AuthFactory(personalCallbackScheme: PERSONAL_SCHEME);
        using var client = await factory.SignedInAsync();
        var pending = await CodeAsync(client);
        using var issued = await ExchangeAsync(client, pending.Code, pending.Verifier);
        var tokens = await issued.Content.ReadFromJsonAsync<JsonElement>();
        using var scope = factory.Services.CreateScope();
        var config = scope.ServiceProvider.GetRequiredService<IConfiguration>();
        config["Auth:PersonalCallbackScheme"] = "";
        await AuthConfiguration.RegisterClient(scope.ServiceProvider, config);
        var manager = scope.ServiceProvider.GetRequiredService<IOpenIddictApplicationManager>();
        Assert.Null(await manager.FindByClientIdAsync(AuthConfiguration.PersonalClientId));
        Assert.NotNull(await manager.FindByClientIdAsync(AuthConfiguration.ClientId));
        using var introspection = new HttpRequestMessage(HttpMethod.Post, "/connect/introspect");
        introspection.Headers.Authorization = new("Basic", Convert.ToBase64String(
            Encoding.UTF8.GetBytes(AuthConfiguration.Audience + ":" + AuthFactory.IntrospectionSecret)));
        introspection.Content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["token"] = tokens.GetProperty("access_token").GetString()!,
            ["token_type_hint"] = "access_token"
        });
        using var status = await client.SendAsync(introspection);
        Assert.Equal(HttpStatusCode.OK, status.StatusCode);
        Assert.False((await status.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("active").GetBoolean());
        using var refresh = await RefreshAsync(client, tokens.GetProperty("refresh_token").GetString()!);
        Assert.Equal(HttpStatusCode.Unauthorized, refresh.StatusCode);
        Assert.Equal("invalid_client", (await refresh.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("error").GetString());
    }

    /// <summary>Не принимает произвольный URI, короткую generic-схему или символы конфигурационной инъекции.</summary>
    [Theory]
    [InlineData("fitnesstracker")]
    [InlineData("https")]
    [InlineData("com.example.fitnesstracker:/callback")]
    [InlineData("com.example.fitnesstracker\n")]
    [InlineData("Com.example.fitnesstracker")]
    [InlineData("com..example")]
    [InlineData("com.-example")]
    [InlineData("com.example-")]
    public async Task RejectsInvalidConfiguredSchemeAsync(string scheme)
    {
        using var factory = new AuthFactory(personalCallbackScheme: scheme);
        await Assert.ThrowsAsync<InvalidOperationException>(() => factory.SignedInAsync());
    }

    /// <summary>Собирает authorize request без произвольного return URL.</summary>
    private static string AuthorizationUrl(string clientId, string redirect, string? challenge, string? method) =>
        QueryHelpers.AddQueryString("/connect/authorize", new Dictionary<string, string?>
        {
            ["client_id"] = clientId,
            ["redirect_uri"] = redirect,
            ["response_type"] = "code",
            ["scope"] = "profile offline_access",
            ["state"] = "personal-state",
            ["code_challenge"] = challenge,
            ["code_challenge_method"] = method
        });

    /// <summary>Получает code через настоящий OpenIddict и проверяет точную схему/путь/state в redirect.</summary>
    private static async Task<(string Code, string Verifier)> CodeAsync(HttpClient client)
    {
        var verifier = Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(32));
        var challenge = Base64UrlEncoder.Encode(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
        using var response = await client.GetAsync(AuthorizationUrl(AuthConfiguration.PersonalClientId, PERSONAL_CALLBACK, challenge, "S256"));
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.NotNull(response.Headers.Location);
        var callback = response.Headers.Location;
        Assert.Equal(PERSONAL_CALLBACK, callback.GetLeftPart(UriPartial.Path));
        var query = QueryHelpers.ParseQuery(callback.Query);
        Assert.Equal("personal-state", query["state"].ToString());
        Assert.False(query.ContainsKey("error"));
        return (query["code"].ToString(), verifier);
    }

    /// <summary>Обменивает одноразовый code со всеми параметрами исходной попытки.</summary>
    private static Task<HttpResponseMessage> ExchangeAsync(HttpClient client, string code, string verifier,
        string clientId = AuthConfiguration.PersonalClientId, string redirect = PERSONAL_CALLBACK) =>
        client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = clientId,
            ["redirect_uri"] = redirect,
            ["code"] = code,
            ["code_verifier"] = verifier
        }));

    /// <summary>Проверяет привязку refresh token к выбранному public client.</summary>
    private static Task<HttpResponseMessage> RefreshAsync(HttpClient client, string refresh, string clientId = AuthConfiguration.PersonalClientId) =>
        client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        { ["grant_type"] = "refresh_token", ["client_id"] = clientId, ["refresh_token"] = refresh }));
}
