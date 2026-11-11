using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет запрет ослабленных и некорректных JWT на настоящем middleware Backend.</summary>
[Trait("Category", "HTTP")]
public sealed class BackendSecurityTests
{
    /// <summary>Нельзя заменить RSA подпись, убрать exp или использовать токен до начала его действия.</summary>
    [Theory]
    [InlineData("unsigned")]
    [InlineData("hmac")]
    [InlineData("missing-expiration")]
    [InlineData("not-yet-valid")]
    public async Task RejectsWeakenedAndInvalidLifetimeTokensAsync(string invalid)
    {
        // Arrange: атакующий знает публичный RSA-ключ, но не приватный ключ сервера.
        using var factory = new BackendFactory();
        using var client = factory.Client();
        var credentials = invalid switch
        {
            "unsigned" => null,
            "hmac" => new SigningCredentials(
                new SymmetricSecurityKey(factory.Key.Rsa.ExportSubjectPublicKeyInfo()) { KeyId = factory.Key.KeyId },
                SecurityAlgorithms.HmacSha256),
            _ => new SigningCredentials(factory.Key, SecurityAlgorithms.RsaSha256)
        };
        var token = new JwtSecurityToken("https://auth.test/", "fitnesstracker-api",
            [new Claim("sub", Guid.NewGuid().ToString()), new Claim("scope", "backups")],
            notBefore: invalid == "not-yet-valid" ? DateTime.UtcNow.AddMinutes(5) : null,
            expires: invalid == "missing-expiration" ? null : DateTime.UtcNow.AddMinutes(10),
            signingCredentials: credentials);
        token.Header["typ"] = "at+jwt";
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));

        // Act: ошибка JWT должна остановить как чтение, так и запись до валидации архива.
        using var read = await client.GetAsync("/v1/backups");
        using var write = await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", new StringContent("{}"));

        // Assert: нет ни доступа к данным, ни побочных записей при ошибке подписи/времени.
        Assert.Equal(HttpStatusCode.Unauthorized, read.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, write.StatusCode);
        Assert.Equal(0, factory.Introspection.Calls);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<BackupDbContext>().Backups.ToListAsync());
    }
}
