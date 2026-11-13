using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using FitLife.Authentication;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Http;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет настоящий OpenIddict flow Xiaomi, owner binding и шифрование credentials без сети.</summary>
public sealed class HealthConnectionTests
{
    /// <summary>Callback сохраняет только зашифрованные credentials, refresh использует отдельный endpoint, отзыв обновляет истёкший токен.</summary>
    [Fact]
    public async Task ConnectRefreshAndDisconnectUseProtectedOwnerBoundTokensAsync()
    {
        using var factory = Factory();
        using var client = await factory.SignedInAsync();
        var callback = await StartAsync(client);
        using var completed = await client.GetAsync(callback);
        Assert.Equal(HttpStatusCode.Redirect, completed.StatusCode);
        using var scope = factory.Services.CreateScope();
        var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        var row = await database.HealthConnections.SingleAsync();
        Assert.DoesNotContain("synthetic-access", row.ProtectedTokens);
        Assert.DoesNotContain("synthetic-refresh", row.ProtectedTokens);
        Assert.Null(row.AttemptId);
        var status = Assert.Single(await scope.ServiceProvider.GetRequiredService<HealthConnectionService>().StatusAsync(row.UserId, default));
        Assert.True(status.Connected);
        Assert.Equal(new[] { "bodyFatPercentage", "bodyWeight" }, status.Metrics);
        var json = JsonSerializer.Serialize(status);
        Assert.DoesNotContain("Token", json);
        using var grantRequest = new HttpRequestMessage(HttpMethod.Post, $"/internal/health/mi-fitness/{row.UserId}/grant");
        grantRequest.Headers.Add("X-Service-Key", BackendFactory.ServiceKey);
        using var grant = await client.SendAsync(grantRequest);
        Assert.Equal(HttpStatusCode.OK, grant.StatusCode);
        var grantJson = await grant.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("synthetic-rotated-access", grantJson.GetProperty("accessToken").GetString());
        Assert.False(grantJson.TryGetProperty("refreshToken", out _));
        await scope.ServiceProvider.GetRequiredService<HealthConnectionService>().DisconnectAsync(row.UserId, default);
        database.ChangeTracker.Clear();
        Assert.Empty((await database.HealthConnections.SingleAsync()).ProtectedTokens);
        using var replay = await client.GetAsync(callback);
        Assert.NotEqual(HttpStatusCode.Redirect, replay.StatusCode);
    }

    /// <summary>Другой cookie-пользователь, подменённый state и устаревшая попытка не могут принять чужую привязку.</summary>
    [Theory]
    [InlineData("owner")]
    [InlineData("state")]
    [InlineData("attempt")]
    public async Task CallbackRejectsWrongOwnerOrStaleStateAsync(string misuse)
    {
        using var factory = Factory();
        using var client = await factory.SignedInAsync();
        string[] stateCookies = [];
        var callback = await StartAsync(client, cookies => stateCookies = cookies);
        using var other = misuse == "owner" ? await factory.SignedInAsync() : null;
        if (misuse == "owner")
        {
            other!.DefaultRequestHeaders.Add("Cookie", string.Join("; ", stateCookies));
        }
        if (misuse == "state") callback += "tampered";
        if (misuse == "attempt") _ = await StartAsync(client);
        using var rejected = await (other ?? client).GetAsync(callback);
        Assert.NotEqual(HttpStatusCode.Redirect, rejected.StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.All(await scope.ServiceProvider.GetRequiredService<AuthDbContext>().HealthConnections.ToArrayAsync(), row => Assert.Empty(row.ProtectedTokens));
    }

    /// <summary>CSRF, внутренний service key и отсутствие настройки проверяются до изменения привязки.</summary>
    [Fact]
    public async Task RejectsUnauthenticatedAndUntrustedMutationsAsync()
    {
        using var factory = Factory();
        using var client = await factory.SignedInAsync();
        using var csrf = await client.PostAsync("/account/health/mi-fitness/connect", new FormUrlEncodedContent([]));
        Assert.Equal(HttpStatusCode.BadRequest, csrf.StatusCode);
        using var internalRequest = await client.PostAsync($"/internal/health/mi-fitness/{Guid.NewGuid()}/grant", null);
        Assert.Equal(HttpStatusCode.Unauthorized, internalRequest.StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<AuthDbContext>().HealthConnections.ToArrayAsync());
    }

    /// <summary>Отказ отзыва и повреждение шифротекста сохраняют данные для безопасного повтора.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task FailedDisconnectDoesNotEraseCredentialsAsync(bool corrupt)
    {
        using var factory = Factory(revokeFails: true);
        using var client = await factory.SignedInAsync();
        using var completed = await client.GetAsync(await StartAsync(client));
        Assert.Equal(HttpStatusCode.Redirect, completed.StatusCode);
        using var scope = factory.Services.CreateScope();
        var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        var row = await database.HealthConnections.SingleAsync();
        if (corrupt) { row.ProtectedTokens = "corrupted-ciphertext"; await database.SaveChangesAsync(); }
        await Assert.ThrowsAsync<AuthenticationOperationException>(() => scope.ServiceProvider.GetRequiredService<HealthConnectionService>().DisconnectAsync(row.UserId, default));
        database.ChangeTracker.Clear();
        Assert.NotEmpty((await database.HealthConnections.SingleAsync()).ProtectedTokens);
    }

    /// <summary>Создаёт challenge через настоящую antiforgery форму и возвращает callback с проверяемым state.</summary>
    private static async Task<string> StartAsync(HttpClient client, Action<string[]>? captureCookies = null)
    {
        var page = await client.GetStringAsync("/account/health");
        var token = WebUtility.HtmlDecode(Regex.Match(page, "name=\"__RequestVerificationToken\"[^>]*value=\"([^\"]+)\"").Groups[1].Value);
        Assert.NotEmpty(token);
        using var response = await client.PostAsync("/account/health/mi-fitness/connect", new FormUrlEncodedContent(new Dictionary<string, string> { ["__RequestVerificationToken"] = token, ["returnUrl"] = "/account" }));
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        captureCookies?.Invoke(response.Headers.TryGetValues("Set-Cookie", out var cookies) ? cookies.Where(cookie => cookie.Contains("OpenIddict", StringComparison.OrdinalIgnoreCase)).Select(cookie => cookie.Split(';')[0]).ToArray() : []);
        var target = response.Headers.Location!;
        Assert.Equal("account.xiaomi.com", target.Host);
        var query = QueryHelpers.ParseQuery(target.Query);
        Assert.Equal("healthkit", query["scope_provider"].ToString());
        Assert.Equal("false", query["skip_confirm"].ToString());
        Assert.Equal("https://localhost/callback/health/mi-fitness", query["redirect_uri"].ToString());
        return QueryHelpers.AddQueryString("/callback/health/mi-fitness", new Dictionary<string, string?> { ["code"] = "synthetic-code", ["state"] = query["state"].ToString() });
    }

    /// <summary>Подменяет исключительно HTTP Xiaomi и распределённую блокировку, оставляя Identity/OpenIddict реальными.</summary>
    private static AuthFactory Factory(bool revokeFails = false) => new(providerSettings: new Dictionary<string, string?>
    {
        ["HealthProviders:MiFitness:Enabled"] = "true",
        ["HealthProviders:MiFitness:ClientId"] = "123",
        ["HealthProviders:MiFitness:ClientSecret"] = "synthetic-client-secret"
    }, configureServices: services =>
    {
        services.RemoveAll<IHealthConnectionLocks>();
        services.AddSingleton<IHealthConnectionLocks, TestLocks>();
        services.PostConfigureAll<HttpClientFactoryOptions>(options => options.HttpMessageHandlerBuilderActions.Add(builder =>
        {
            if (builder.Name?.Contains("OpenIddict", StringComparison.OrdinalIgnoreCase) == true || builder.Name == "xiaomi-health-revoke")
                builder.PrimaryHandler = new XiaomiHandler(revokeFails);
        }));
    });

    /// <summary>Не использует PostgreSQL только в SQLite HTTP fixture; реальные advisory locks проверяются отдельно.</summary>
    private sealed class TestLocks : IHealthConnectionLocks
    {
        private readonly SemaphoreSlim _gate = new(1);
        /// <summary>Сериализует тестовые операции без задержек.</summary>
        public async Task<IAsyncDisposable> AcquireAsync(string userId, CancellationToken cancellationToken) { await _gate.WaitAsync(cancellationToken); return new Lease(_gate); }
        /// <summary>Гарантирует освобождение semaphore.</summary>
        private sealed class Lease(SemaphoreSlim gate) : IAsyncDisposable
        {
            /// <summary>Освобождает единственный захват.</summary>
            public ValueTask DisposeAsync() { gate.Release(); return ValueTask.CompletedTask; }
        }
    }
    /// <summary>Проверяет документированные form параметры и возвращает Xiaomi prefix/MAC quirks.</summary>
    private sealed class XiaomiHandler(bool revokeFails) : HttpMessageHandler
    {
        /// <summary>Никакой реальной сети; неверный endpoint делает тест ошибочным.</summary>
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var form = QueryHelpers.ParseQuery(await request.Content!.ReadAsStringAsync(cancellationToken));
            Assert.Equal("123", form["client_id"].ToString());
            Assert.Equal("synthetic-client-secret", form["client_secret"].ToString());
            if (request.RequestUri!.Host == "open.account.xiaomi.com")
            {
                Assert.Equal("synthetic-rotated-access", form["access_token"].ToString());
                return new(revokeFails ? HttpStatusCode.ServiceUnavailable : HttpStatusCode.OK) { Content = JsonContent.Create(new { code = 0 }) };
            }
            Assert.Equal("account.xiaomi.com", request.RequestUri.Host);
            var refresh = form["grant_type"] == "refresh_token";
            Assert.Equal(refresh ? "/oauth2/refresh/token" : "/oauth2/token", request.RequestUri.AbsolutePath);
            Assert.Equal("0", form["pt"].ToString());
            if (refresh) Assert.Equal("https://localhost/callback/health/mi-fitness", form["redirect_uri"].ToString());
            var body = JsonSerializer.Serialize(new { access_token = refresh ? "synthetic-rotated-access" : "synthetic-access", refresh_token = "synthetic-refresh", expires_in = refresh ? 3600 : 30, token_type = "mac", scope = "200010 200013", openId = "synthetic-xiaomi-user" });
            return new(HttpStatusCode.OK) { Content = new StringContent("&&&START&&&" + body, System.Text.Encoding.UTF8, "application/json") };
        }
    }
}
