using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using FitLife.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using OpenIddict.Abstractions;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет реальные Auth/Backend, discovery/JWKS и RFC 7662 через in-memory HTTP без внешней сети.</summary>
[Trait("Category", "HTTP")]
public sealed class SessionRevocationTests
{
    private const string ARCHIVE = """{"format":"com.fitnesstracker.archive","version":4,"exportedAt":1700000000,"workouts":[],"templates":[],"bodyWeights":[]}""";

    /// <summary>Выход отзывает все поколения одной сессии немедленно, сохраняя другой вход того же пользователя.</summary>
    [Fact]
    public async Task LogoutRejectsExistingAccessTokensAndPreservesAnotherSessionAsync()
    {
        // Arrange: два независимых входа; первый уже успел ротировать refresh token.
        using var auth = new AuthFactory();
        using var browser = await auth.SignedInAsync();
        var first = await SignInAsync(browser);
        var second = await SignInAsync(browser);
        using var rotatedResponse = await RefreshAsync(browser, first.Refresh);
        Assert.Equal(HttpStatusCode.OK, rotatedResponse.StatusCode);
        var rotated = await ReadTokensAsync(rotatedResponse);
        using var transport = auth.Server.CreateHandler();
        using var backend = new BackendFactory(transport);
        using var firstDevice = backend.Client();
        using var secondDevice = backend.Client();
        firstDevice.DefaultRequestHeaders.Authorization = new("Bearer", first.Access);
        secondDevice.DefaultRequestHeaders.Authorization = new("Bearer", second.Access);
        var id = Guid.NewGuid();
        using var content = new StringContent(ARCHIVE);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        using var created = await firstDevice.PutAsync($"/v1/backups/{id}", content);
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);

        // Act: стандартный iOS revoke latest refresh, без client secret.
        using var revoked = await RevokeAsync(browser, rotated.Refresh);
        Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        using var repeat = await RevokeAsync(browser, rotated.Refresh);
        Assert.Equal(HttpStatusCode.OK, repeat.StatusCode);

        // Assert: тот же подписанный JWT больше не читает и не удаляет данные; второе устройство работает.
        using var staleRead = await firstDevice.GetAsync($"/v1/backups/{id}");
        using var staleDelete = await firstDevice.DeleteAsync($"/v1/backups/{id}");
        Assert.Equal(HttpStatusCode.Unauthorized, staleRead.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, staleDelete.StatusCode);
        firstDevice.DefaultRequestHeaders.Authorization = new("Bearer", rotated.Access);
        using var staleRotated = await firstDevice.GetAsync("/v1/backups");
        Assert.Equal(HttpStatusCode.Unauthorized, staleRotated.StatusCode);
        using var refreshRejected = await RefreshAsync(browser, rotated.Refresh);
        Assert.Equal(HttpStatusCode.BadRequest, refreshRejected.StatusCode);
        Assert.Equal(ARCHIVE, await secondDevice.GetStringAsync($"/v1/backups/{id}"));
        using var otherRefresh = await RefreshAsync(browser, second.Refresh);
        Assert.Equal(HttpStatusCode.OK, otherRefresh.StatusCode);
    }

    /// <summary>Отвязка провайдера останавливает уже проверенный Backend JWT без ожидания его exp.</summary>
    [Fact]
    public async Task ProviderRemovalImmediatelyStopsBackendAccessAsync()
    {
        using var auth = new AuthFactory();
        using var browser = await auth.SignedInAsync();
        using var scope = auth.Services.CreateScope();
        var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
        var user = await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
        Assert.True((await users.AddLoginAsync(user, new UserLoginInfo("Google", "google-subject", "Google"))).Succeeded);
        Assert.True((await users.AddLoginAsync(user, new UserLoginInfo("Apple", "apple-subject", "Apple"))).Succeeded);
        var tokens = await SignInAsync(browser);
        using var transport = auth.Server.CreateHandler();
        using var backend = new BackendFactory(transport);
        using var client = backend.Client();
        client.DefaultRequestHeaders.Authorization = new("Bearer", tokens.Access);
        using var before = await client.GetAsync("/v1/backups");
        Assert.Equal(HttpStatusCode.OK, before.StatusCode);

        Assert.True(await scope.ServiceProvider.GetRequiredService<ExternalAccounts>().Unlink(user, "Google", default));
        using var after = await client.GetAsync("/v1/backups");

        Assert.Equal(HttpStatusCode.Unauthorized, after.StatusCode);
    }

    /// <summary>Удаление Identity/token entries прекращает доступ Backend, даже пока подпись JWT и exp допустимы.</summary>
    [Fact]
    public async Task AccountDeletionImmediatelyStopsBackendAccessAsync()
    {
        using var auth = new AuthFactory();
        using var browser = await auth.SignedInAsync();
        var tokens = await SignInAsync(browser);
        using var transport = auth.Server.CreateHandler();
        using var backend = new BackendFactory(transport);
        using var client = backend.Client();
        client.DefaultRequestHeaders.Authorization = new("Bearer", tokens.Access);
        using var before = await client.GetAsync("/v1/backups");
        Assert.Equal(HttpStatusCode.OK, before.StatusCode);
        browser.DefaultRequestHeaders.Authorization = new("Bearer", tokens.Access);

        using var deleted = await browser.DeleteAsync("/v1/account");
        using var after = await client.GetAsync("/v1/backups");

        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, after.StatusCode);
    }

    /// <summary>Обнаруженный replay refresh немедленно закрывает доступ обоим поколениям access token.</summary>
    [Fact]
    public async Task RefreshReplayImmediatelyStopsBackendAccessAsync()
    {
        using var auth = new AuthFactory();
        using var browser = await auth.SignedInAsync();
        var tokens = await SignInAsync(browser);
        using var rotatedResponse = await RefreshAsync(browser, tokens.Refresh);
        Assert.Equal(HttpStatusCode.OK, rotatedResponse.StatusCode);
        var rotated = await ReadTokensAsync(rotatedResponse);
        using var transport = auth.Server.CreateHandler();
        using var backend = new BackendFactory(transport);
        using var client = backend.Client();
        client.DefaultRequestHeaders.Authorization = new("Bearer", tokens.Access);
        using var before = await client.GetAsync("/v1/backups");
        Assert.Equal(HttpStatusCode.OK, before.StatusCode);

        using var replay = await RefreshAsync(browser, tokens.Refresh);
        Assert.Equal(HttpStatusCode.BadRequest, replay.StatusCode);
        using var oldAccess = await client.GetAsync("/v1/backups");
        client.DefaultRequestHeaders.Authorization = new("Bearer", rotated.Access);
        using var rotatedAccess = await client.GetAsync("/v1/backups");

        Assert.Equal(HttpStatusCode.Unauthorized, oldAccess.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, rotatedAccess.StatusCode);
    }

    /// <summary>Отозванный grant запрещает даже valid token entry, появившуюся после массового отзыва токенов.</summary>
    [Fact]
    public async Task RevokedAuthorizationStopsAccessWithValidTokenEntryAsync()
    {
        using var auth = new AuthFactory();
        using var browser = await auth.SignedInAsync();
        var tokens = await SignInAsync(browser);
        using var transport = auth.Server.CreateHandler();
        using var backend = new BackendFactory(transport);
        using var client = backend.Client();
        client.DefaultRequestHeaders.Authorization = new("Bearer", tokens.Access);
        using var before = await client.GetAsync("/v1/backups");
        Assert.Equal(HttpStatusCode.OK, before.StatusCode);

        using var scope = auth.Services.CreateScope();
        var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        var user = await database.Users.SingleAsync();
        await scope.ServiceProvider.GetRequiredService<IOpenIddictAuthorizationManager>().RevokeBySubjectAsync(user.Id);
        // Не изменяем статус access token: защита должна проверить также authorization.
        var token = await database.Set<OpenIddict.EntityFrameworkCore.Models.OpenIddictEntityFrameworkCoreToken>()
            .AsNoTracking()
            .SingleAsync(value => value.Type == OpenIddictConstants.TokenTypeIdentifiers.AccessToken);
        Assert.Equal(OpenIddictConstants.Statuses.Valid, token.Status);
        using var after = await client.GetAsync("/v1/backups");

        Assert.Equal(HttpStatusCode.Unauthorized, after.StatusCode);
    }

    /// <summary>Кеш JWKS не позволяет продолжать доступ при отказе Auth; тот же JWT работает после восстановления.</summary>
    [Fact]
    public async Task AuthOutageFailsClosedAndRecoveryPreservesSessionAsync()
    {
        using var auth = new AuthFactory();
        using var browser = await auth.SignedInAsync();
        var tokens = await SignInAsync(browser);
        using var transport = new SwitchableAuthTransport(auth.Server.CreateHandler());
        using var backend = new BackendFactory(transport);
        using var client = backend.Client();
        client.DefaultRequestHeaders.Authorization = new("Bearer", tokens.Access);
        using var before = await client.GetAsync("/v1/backups");
        Assert.Equal(HttpStatusCode.OK, before.StatusCode);

        transport.Unavailable = true;
        using var outage = await client.GetAsync("/v1/backups");

        Assert.Equal(HttpStatusCode.ServiceUnavailable, outage.StatusCode);
        Assert.Empty(outage.Headers.WwwAuthenticate);
        transport.Unavailable = false;
        using var recovered = await client.GetAsync("/v1/backups");
        Assert.Equal(HttpStatusCode.OK, recovered.StatusCode);
    }

    /// <summary>Недоступный Auth при первом запросе, без кеша discovery/JWKS, также даёт 503, а не invalid_token.</summary>
    [Fact]
    public async Task ColdStartAuthOutageReturnsServiceUnavailableAsync()
    {
        using var auth = new AuthFactory();
        using var browser = await auth.SignedInAsync();
        var tokens = await SignInAsync(browser);
        using var transport = new SwitchableAuthTransport(auth.Server.CreateHandler()) { Unavailable = true };
        using var backend = new BackendFactory(transport);
        using var client = backend.Client();
        client.DefaultRequestHeaders.Authorization = new("Bearer", tokens.Access);

        using var response = await client.GetAsync("/v1/backups");

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Empty(response.Headers.WwwAuthenticate);
    }

    /// <summary>Интроспекция требует отдельный confidential secret; публичный iOS и чужая audience не подходят.</summary>
    [Fact]
    public async Task IntrospectionRequiresDedicatedServerCredentialsAndAudienceAsync()
    {
        using var auth = new AuthFactory();
        using var browser = await auth.SignedInAsync();
        var tokens = await SignInAsync(browser);
        foreach (var credentials in new[]
        {
            (AuthConfiguration.Audience, "wrong-secret"),
            (AuthConfiguration.Audience, BackendFactory.ServiceKey),
            (AuthConfiguration.ClientId, "")
        })
        {
            using var denied = await IntrospectAsync(browser, tokens.Access, credentials.Item1, credentials.Item2);
            Assert.InRange((int)denied.StatusCode, 400, 499);
        }
        using var allowed = await IntrospectAsync(browser, tokens.Access, AuthConfiguration.Audience, AuthFactory.IntrospectionSecret);
        Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        Assert.True((await allowed.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("active").GetBoolean());
        Assert.DoesNotContain("fitnesstracker:security_stamp", await allowed.Content.ReadAsStringAsync());

        using var scope = auth.Services.CreateScope();
        var manager = scope.ServiceProvider.GetRequiredService<IOpenIddictApplicationManager>();
        await manager.CreateAsync(new OpenIddictApplicationDescriptor
        {
            ClientId = "other-api",
            ClientSecret = AuthFactory.IntrospectionSecret,
            ClientType = OpenIddictConstants.ClientTypes.Confidential,
            Permissions = { OpenIddictConstants.Permissions.Endpoints.Introspection }
        });
        using var otherAudience = await IntrospectAsync(browser, tokens.Access, "other-api", AuthFactory.IntrospectionSecret);
        Assert.Equal(HttpStatusCode.OK, otherAudience.StatusCode);
        Assert.False((await otherAudience.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("active").GetBoolean());
    }

    /// <summary>Получает настоящую пару через authorization code с PKCE, а не создаёт JWT вручную.</summary>
    private static async Task<(string Access, string Refresh)> SignInAsync(HttpClient client, CancellationToken cancellationToken = default)
    {
        var verifier = Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(32));
        using var authorize = await client.GetAsync(QueryHelpers.AddQueryString("/connect/authorize", new Dictionary<string, string?>
        {
            ["client_id"] = AuthConfiguration.ClientId,
            ["redirect_uri"] = AuthConfiguration.Callback,
            ["response_type"] = "code",
            ["scope"] = "openid profile offline_access",
            ["state"] = "introspection-state",
            ["code_challenge"] = Base64UrlEncoder.Encode(SHA256.HashData(System.Text.Encoding.ASCII.GetBytes(verifier))),
            ["code_challenge_method"] = "S256"
        }), cancellationToken);
        Assert.Equal(HttpStatusCode.Redirect, authorize.StatusCode);
        var query = QueryHelpers.ParseQuery(authorize.Headers.Location!.Query);
        Assert.Equal("introspection-state", query["state"].ToString());
        using var exchange = await client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = AuthConfiguration.ClientId,
            ["redirect_uri"] = AuthConfiguration.Callback,
            ["code"] = query["code"].ToString(),
            ["code_verifier"] = verifier
        }), cancellationToken);
        Assert.Equal(HttpStatusCode.OK, exchange.StatusCode);
        return await ReadTokensAsync(exchange, cancellationToken);
    }

    /// <summary>Извлекает только необходимые тесту credentials из успешного protocol response.</summary>
    private static async Task<(string Access, string Refresh)> ReadTokensAsync(HttpResponseMessage response,
        CancellationToken cancellationToken = default)
    {
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(cancellationToken);
        return (body.GetProperty("access_token").GetString()!, body.GetProperty("refresh_token").GetString()!);
    }

    /// <summary>Ротирует refresh через стандартный публичный endpoint.</summary>
    private static Task<HttpResponseMessage> RefreshAsync(HttpClient client, string refresh, CancellationToken cancellationToken = default) =>
        client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        { ["client_id"] = AuthConfiguration.ClientId, ["grant_type"] = "refresh_token", ["refresh_token"] = refresh }), cancellationToken);

    /// <summary>Повторяет существующий wire-контракт выхода iOS.</summary>
    private static Task<HttpResponseMessage> RevokeAsync(HttpClient client, string refresh, CancellationToken cancellationToken = default) =>
        client.PostAsync("/connect/revoke", new FormUrlEncodedContent(new Dictionary<string, string>
        { ["client_id"] = AuthConfiguration.ClientId, ["token"] = refresh, ["token_type_hint"] = "refresh_token" }), cancellationToken);

    /// <summary>Вызывает настоящий RFC 7662 endpoint с отдельными server credentials.</summary>
    private static Task<HttpResponseMessage> IntrospectAsync(HttpClient client, string token, string clientId, string secret,
        CancellationToken cancellationToken = default) =>
        client.PostAsync("/connect/introspect", new FormUrlEncodedContent(new Dictionary<string, string>
        { ["client_id"] = clientId, ["client_secret"] = secret, ["token"] = token, ["token_type_hint"] = "access_token" }), cancellationToken);

    /// <summary>Отключает только транспорт к настоящему Auth, не подменяя его токены или логику introspection.</summary>
    private sealed class SwitchableAuthTransport(HttpMessageHandler inner) : DelegatingHandler(inner)
    {
        /// <summary>Имитирует временный отказ сервиса после успешных discovery/JWKS и introspection.</summary>
        internal bool Unavailable { get; set; }
        /// <summary>Передаёт обычный запрос в in-memory Auth либо отвечает 503.</summary>
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Unavailable ? Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)) : base.SendAsync(request, cancellationToken);
    }
}
