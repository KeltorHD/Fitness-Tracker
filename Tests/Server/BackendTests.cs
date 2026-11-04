using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using FitnessTracker.Backend;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace FitnessTracker.Server.Tests;

public sealed class BackendFactory : WebApplicationFactory<Backend.Program>
{
    private readonly SqliteConnection connection = new("Data Source=:memory:");
    internal readonly RsaSecurityKey Key = new(RSA.Create(2048)) { KeyId = "test" };
    internal const string ServiceKey = "server-tests-service-key-at-least-32-characters";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        connection.Open();
        builder.UseEnvironment("Testing");
        builder.UseSetting("Backend:ServiceKey", ServiceKey);
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<BackupDbContext>>();
            services.RemoveAll<IDbContextOptionsConfiguration<BackupDbContext>>();
            services.AddDbContext<BackupDbContext>(options => options.UseSqlite(connection));
            services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
            {
                options.Authority = null;
                options.ConfigurationManager = null;
                options.Configuration = null;
                options.TokenValidationParameters.ValidIssuer = "https://auth.test/";
                options.TokenValidationParameters.ValidAudience = "fitnesstracker-api";
                options.TokenValidationParameters.IssuerSigningKey = Key;
            });
        });
    }

    internal HttpClient Client(string? owner = null, string scope = "backups", string audience = "fitnesstracker-api",
        DateTime? expires = null, SecurityKey? key = null)
    {
        var client = CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost"), AllowAutoRedirect = false });
        using var serviceScope = Services.CreateScope();
        serviceScope.ServiceProvider.GetRequiredService<BackupDbContext>().Database.EnsureCreated();
        if (owner is not null)
        {
            var token = new JwtSecurityToken("https://auth.test/", audience,
                [new Claim("sub", owner), new Claim("scope", scope)],
                expires: expires ?? DateTime.UtcNow.AddMinutes(5),
                signingCredentials: new SigningCredentials(key ?? Key, SecurityAlgorithms.RsaSha256));
            token.Header["typ"] = "at+jwt";
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
        }
        return client;
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing) { connection.Dispose(); (Key.Rsa).Dispose(); }
    }
}

public sealed class BackendTests
{
    private static readonly byte[] Archive = Encoding.UTF8.GetBytes(
        """{"format":"com.fitnesstracker.archive","version":4,"exportedAt":1700000000,"workouts":[],"templates":[],"bodyWeights":[]}""");

    private static ByteArrayContent Content(byte[]? data = null)
    {
        var content = new ByteArrayContent(data ?? Archive);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/vnd.fitnesstracker+json");
        return content;
    }

    [Fact]
    public async Task BackupRoundTripIsImmutableIdempotentAndIsolatedBySubject()
    {
        using var factory = new BackendFactory();
        using var owner = factory.Client(Guid.NewGuid().ToString());
        using var other = factory.Client(Guid.NewGuid().ToString());
        var id = Guid.NewGuid();
        using var uploaded = await owner.PutAsync($"/v1/backups/{id}", Content());
        Assert.Equal(HttpStatusCode.Created, uploaded.StatusCode);
        var info = await uploaded.Content.ReadFromJsonAsync<BackupInfo>();
        Assert.Equal(Convert.ToHexStringLower(SHA256.HashData(Archive)), info!.Sha256);
        Assert.Equal(Archive.Length, info.Size);
        Assert.Equal(HttpStatusCode.OK, (await owner.PutAsync($"/v1/backups/{id}", Content())).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await owner.PutAsync($"/v1/backups/{id}", Content(Encoding.UTF8.GetBytes(
            Encoding.UTF8.GetString(Archive).Replace("1700000000", "1700000001"))))).StatusCode);
        Assert.Equal(Archive, await owner.GetByteArrayAsync($"/v1/backups/{id}"));
        Assert.Single((await owner.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
        Assert.Empty((await other.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
        Assert.Equal(HttpStatusCode.NotFound, (await other.GetAsync($"/v1/backups/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await other.DeleteAsync($"/v1/backups/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await owner.DeleteAsync($"/v1/backups/{id}")).StatusCode);
        Assert.Empty((await owner.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
    }

    [Fact]
    public async Task RejectsUnauthenticatedWrongScopeAudienceSignatureAndExpiredTokens()
    {
        using var factory = new BackendFactory();
        var id = Guid.NewGuid().ToString();
        using var anonymous = factory.Client();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/v1/backups")).StatusCode);
        using var wrongScope = factory.Client(id, scope: "profile");
        Assert.Equal(HttpStatusCode.Forbidden, (await wrongScope.GetAsync("/v1/backups")).StatusCode);
        using var wrongAudience = factory.Client(id, audience: "another-api");
        Assert.Equal(HttpStatusCode.Unauthorized, (await wrongAudience.GetAsync("/v1/backups")).StatusCode);
        using var expired = factory.Client(id, expires: DateTime.UtcNow.AddMinutes(-10));
        Assert.Equal(HttpStatusCode.Unauthorized, (await expired.GetAsync("/v1/backups")).StatusCode);
        using var rsa = RSA.Create(2048);
        using var wrongSignature = factory.Client(id, key: new RsaSecurityKey(rsa) { KeyId = "other" });
        Assert.Equal(HttpStatusCode.Unauthorized, (await wrongSignature.GetAsync("/v1/backups")).StatusCode);
    }

    [Fact]
    public async Task RejectsMalformedOversizedUnsupportedArchivesAndQuotaWithoutEvictingBackups()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content("{}"u8.ToArray()))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content(
            Encoding.UTF8.GetBytes(Encoding.UTF8.GetString(Archive).Replace("\"version\":4", "\"version\":99"))))).StatusCode);
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}",
            Content(new byte[BackupStorage.MaximumBytes + 1]))).StatusCode);
        for (var index = 0; index < BackupStorage.MaximumCopies; index++)
            Assert.Equal(HttpStatusCode.Created, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content())).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content())).StatusCode);
        Assert.Equal(BackupStorage.MaximumCopies, (await client.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!.Length);
    }

    [Fact]
    public async Task AccountCleanupRequiresServiceCredentialAndBlocksUploadsWithOldAccessTokens()
    {
        using var factory = new BackendFactory();
        var id = Guid.NewGuid().ToString();
        using var client = factory.Client(id);
        Assert.Equal(HttpStatusCode.Created, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content())).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.DeleteAsync($"/internal/users/{id}/backups")).StatusCode);
        client.DefaultRequestHeaders.Add("X-Service-Key", BackendFactory.ServiceKey);
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/internal/users/{id}/backups")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/internal/users/{id}/backups")).StatusCode);
        Assert.Empty((await client.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content())).StatusCode);
    }
}
