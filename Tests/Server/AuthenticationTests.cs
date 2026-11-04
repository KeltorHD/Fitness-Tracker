using System.Net;
using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FitnessTracker.Authentication;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace FitnessTracker.Server.Tests;

public sealed class AuthFactory : WebApplicationFactory<Authentication.Program>
{
    private readonly SqliteConnection connection = new("Data Source=:memory:");
    internal int CleanupCalls;
    internal bool CleanupFails;

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        connection.Open();
        builder.UseEnvironment("Testing");
        builder.UseSetting("Auth:Issuer", "https://localhost/");
        builder.UseSetting("Backend:InternalUrl", "https://backend.test/");
        builder.UseSetting("Backend:ServiceKey", BackendFactory.ServiceKey);
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<AuthDbContext>>();
            services.RemoveAll<IDbContextOptionsConfiguration<AuthDbContext>>();
            services.AddDbContext<AuthDbContext>(options => options.UseSqlite(connection).UseOpenIddict());
            services.AddHttpClient<BackupCleanup>().ConfigurePrimaryHttpMessageHandler(() => new CleanupHandler(this));
        });
    }

    internal async Task<HttpClient> SignedIn()
    {
        var client = CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost"), AllowAutoRedirect = false });
        using var scope = Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Database.EnsureCreatedAsync();
        await AuthConfiguration.RegisterClient(scope.ServiceProvider, new Microsoft.Extensions.Configuration.ConfigurationBuilder().Build());
        var manager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
        var user = new ApplicationUser { Id = Guid.NewGuid().ToString(), UserName = Guid.NewGuid().ToString("N"), DisplayName = "Test" };
        Assert.True((await manager.CreateAsync(user)).Succeeded);
        var principal = await scope.ServiceProvider.GetRequiredService<SignInManager<ApplicationUser>>().CreateUserPrincipalAsync(user);
        var options = scope.ServiceProvider.GetRequiredService<IOptionsMonitor<CookieAuthenticationOptions>>().Get(IdentityConstants.ApplicationScheme);
        var ticket = options.TicketDataFormat.Protect(new AuthenticationTicket(principal, new AuthenticationProperties
        { IssuedUtc = DateTimeOffset.UtcNow, ExpiresUtc = DateTimeOffset.UtcNow.AddHours(1) }, IdentityConstants.ApplicationScheme));
        client.DefaultRequestHeaders.Add("Cookie", $"{options.Cookie.Name}={ticket}");
        return client;
    }

    private sealed class CleanupHandler(AuthFactory owner) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Assert.Equal(BackendFactory.ServiceKey, request.Headers.GetValues("X-Service-Key").Single());
            Interlocked.Increment(ref owner.CleanupCalls);
            return Task.FromResult(new HttpResponseMessage(owner.CleanupFails ? HttpStatusCode.ServiceUnavailable : HttpStatusCode.NoContent));
        }
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing) connection.Dispose();
    }
}

public sealed class AuthenticationTests
{
    private static async Task<(string Code, string Verifier)> Code(HttpClient client)
    {
        var verifier = Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(32));
        var url = QueryHelpers.AddQueryString("/connect/authorize", new Dictionary<string, string?>
        {
            ["client_id"] = AuthConfiguration.ClientId,
            ["redirect_uri"] = AuthConfiguration.Callback,
            ["response_type"] = "code",
            ["scope"] = "openid profile offline_access backups",
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

    private static Task<HttpResponseMessage> Exchange(HttpClient client, string code, string verifier) =>
        client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = AuthConfiguration.ClientId,
            ["redirect_uri"] = AuthConfiguration.Callback,
            ["code"] = code,
            ["code_verifier"] = verifier
        }));

    private static Task<HttpResponseMessage> Refresh(HttpClient client, string refresh) =>
        client.PostAsync("/connect/token", new FormUrlEncodedContent(new Dictionary<string, string>
        { ["grant_type"] = "refresh_token", ["client_id"] = AuthConfiguration.ClientId, ["refresh_token"] = refresh }));

    [Fact]
    public async Task CodeFlowEnforcesPkceAndExactRedirectUri()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedIn();
        var (code, verifier) = await Code(client);
        var wrong = await Exchange(client, code, verifier + "wrong");
        Assert.Equal(HttpStatusCode.BadRequest, wrong.StatusCode);
        var fresh = await Code(client);
        using var token = await Exchange(client, fresh.Code, fresh.Verifier);
        Assert.Equal(HttpStatusCode.OK, token.StatusCode);
        var response = await token.Content.ReadFromJsonAsync<JsonElement>();
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(response.GetProperty("access_token").GetString());
        Assert.Equal("at+jwt", jwt.Header.Typ);
        Assert.Equal("RS256", jwt.Header.Alg);
        Assert.Equal("https://localhost/", jwt.Issuer);
        Assert.Contains(AuthConfiguration.Audience, jwt.Audiences);
        Assert.Equal(HttpStatusCode.BadRequest, (await Exchange(client, fresh.Code, fresh.Verifier)).StatusCode);
        var rejected = await client.GetAsync("/connect/authorize?client_id=fitnesstracker-ios&redirect_uri=https://attacker.test/&response_type=code&scope=backups");
        Assert.Equal(HttpStatusCode.BadRequest, rejected.StatusCode);
        var missingPkce = await client.GetAsync("/connect/authorize?client_id=fitnesstracker-ios&redirect_uri=fitnesstracker%3A%2F%2Foauth%2Fcallback&response_type=code&scope=backups");
        Assert.Contains("invalid_request", missingPkce.Headers.Location?.ToString() ?? await missingPkce.Content.ReadAsStringAsync());
        var plainPkce = await client.GetAsync("/connect/authorize?client_id=fitnesstracker-ios&redirect_uri=fitnesstracker%3A%2F%2Foauth%2Fcallback&response_type=code&scope=backups&code_challenge=abcdefghijklmnopqrstuvwxyz1234567890abcdefghijk&code_challenge_method=plain");
        Assert.Contains("invalid_request", plainPkce.Headers.Location?.ToString() ?? await plainPkce.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task RefreshRotationRejectsReplayAndRevokesTheSessionFamily()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedIn();
        var code = await Code(client);
        var tokens = await (await Exchange(client, code.Code, code.Verifier)).Content.ReadFromJsonAsync<JsonElement>();
        var refresh = tokens.GetProperty("refresh_token").GetString()!;
        using var rotated = await Refresh(client, refresh);
        Assert.Equal(HttpStatusCode.OK, rotated.StatusCode);
        var next = (await rotated.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("refresh_token").GetString()!;
        Assert.NotEqual(refresh, next);
        Assert.Equal(HttpStatusCode.BadRequest, (await Refresh(client, refresh)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Refresh(client, next)).StatusCode);
    }

    [Fact]
    public async Task PublicClientCanRevokeRefreshTokenWithoutAClientSecret()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedIn();
        var code = await Code(client);
        var tokens = await (await Exchange(client, code.Code, code.Verifier)).Content.ReadFromJsonAsync<JsonElement>();
        var refresh = tokens.GetProperty("refresh_token").GetString()!;
        using var revoked = await client.PostAsync("/connect/revoke", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["client_id"] = AuthConfiguration.ClientId,
            ["token"] = refresh,
            ["token_type_hint"] = "refresh_token"
        }));
        Assert.Equal(HttpStatusCode.OK, revoked.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Refresh(client, refresh)).StatusCode);
    }

    [Fact]
    public async Task AccountDeletionPreservesIdentityOnCleanupFailureAndRevokesTokensOnSuccess()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedIn();
        var code = await Code(client);
        var tokens = await (await Exchange(client, code.Code, code.Verifier)).Content.ReadFromJsonAsync<JsonElement>();
        client.DefaultRequestHeaders.Authorization = new("Bearer", tokens.GetProperty("access_token").GetString());
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/v1/account")).StatusCode);
        factory.CleanupFails = true;
        Assert.Equal(HttpStatusCode.InternalServerError, (await client.DeleteAsync("/v1/account")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/v1/account")).StatusCode);
        factory.CleanupFails = false;
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync("/v1/account")).StatusCode);
        Assert.Equal(2, factory.CleanupCalls);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/v1/account")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Refresh(client, tokens.GetProperty("refresh_token").GetString()!)).StatusCode);
        using var scope = factory.Services.CreateScope();
        var subject = new JwtSecurityTokenHandler().ReadJwtToken(tokens.GetProperty("access_token").GetString()).Subject;
        await foreach (var token in scope.ServiceProvider.GetRequiredService<OpenIddict.Abstractions.IOpenIddictTokenManager>().FindBySubjectAsync(subject))
            Assert.Fail("Deleted account retains a token payload.");
        await foreach (var grant in scope.ServiceProvider.GetRequiredService<OpenIddict.Abstractions.IOpenIddictAuthorizationManager>().FindBySubjectAsync(subject))
            Assert.Fail("Deleted account retains an authorization.");
    }

    [Fact]
    public async Task SameEmailDoesNotMergeProvidersAndLastLoginCannotBeRemoved()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedIn();
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

    [Fact]
    public async Task ProviderSelectionRequiresAntiforgeryAndLocalReturnUrl()
    {
        using var factory = new AuthFactory();
        using var client = await factory.SignedIn();
        var response = await client.PostAsync("/login/google", new FormUrlEncodedContent(new Dictionary<string, string>()));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var page = await client.GetStringAsync("/login?returnUrl=https://attacker.test");
        Assert.DoesNotContain("attacker.test", page);
    }
}
