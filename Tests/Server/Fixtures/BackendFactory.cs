using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using FitnessTracker.Backend;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FitnessTracker.Server.Tests;

/// <summary>Запускает настоящий API с собственной SQLite, ключом JWT и изолированной конфигурацией.</summary>
public sealed class BackendFactory : WebApplicationFactory<Backend.Program>
{
    private readonly SqliteConnection _connection = new("Data Source=:memory:");
    private readonly BackupSaveInterceptor _saves = new();
    /// <summary>Собственный ключ подписи JWT; освобождается вместе с fixture.</summary>
    internal readonly RsaSecurityKey Key = new(RSA.Create(2048)) { KeyId = "test" };
    /// <summary>Синтетический ключ только для внутреннего HTTP-контракта тестового host.</summary>
    internal const string ServiceKey = "server-tests-service-key-at-least-32-characters";
    /// <summary>Фиксированная дата сохранения копий, независимая от даты выполнения теста.</summary>
    internal static readonly DateTimeOffset BackupTime = new(2024, 3, 31, 1, 30, 15, TimeSpan.Zero);

    /// <summary>Позволяет проверить откат HTTP-операции при отказе записи.</summary>
    internal BackupSaveInterceptor Saves => _saves;

    /// <summary>Отделяет тест от appsettings, пользовательских env keys, реальной БД и discovery-запросов.</summary>
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        _connection.Open();
        builder.UseEnvironment("Testing");
        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.Sources.Clear();
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Backend:ServiceKey"] = ServiceKey,
                ["AllowedHosts"] = "localhost",
                ["Logging:LogLevel:Default"] = "None"
            });
        });
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<BackupDbContext>>();
            services.RemoveAll<IDbContextOptionsConfiguration<BackupDbContext>>();
            services.AddDbContext<BackupDbContext>(options => options.UseSqlite(_connection).AddInterceptors(_saves));
            services.RemoveAll<TimeProvider>();
            services.AddSingleton<TimeProvider>(new FrozenTimeProvider(BackupTime));
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

    /// <summary>Создаёт HTTP-клиент с явно заданными свойствами JWT либо без аутентификации.</summary>
    internal HttpClient Client(string? owner = null, string scope = "backups", string audience = "fitnesstracker-api",
        DateTime? expires = null, SecurityKey? key = null, string issuer = "https://auth.test/", string tokenType = "at+jwt")
    {
        var client = CreateClient(new WebApplicationFactoryClientOptions
        {
            BaseAddress = new Uri("https://localhost"),
            AllowAutoRedirect = false
        });
        using var serviceScope = Services.CreateScope();
        serviceScope.ServiceProvider.GetRequiredService<BackupDbContext>().Database.EnsureCreated();
        if (owner is not null)
        {
            var token = new JwtSecurityToken(issuer, audience,
                [new Claim("sub", owner), new Claim("scope", scope)],
                expires: expires ?? DateTime.UtcNow.AddMinutes(5),
                signingCredentials: new SigningCredentials(key ?? Key, SecurityAlgorithms.RsaSha256));
            token.Header["typ"] = tokenType;
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
        }
        return client;
    }

    /// <summary>Освобождает host, SQLite и приватный тестовый ключ при любом результате проверки.</summary>
    protected override void Dispose(bool disposing)
    {
        try { base.Dispose(disposing); }
        finally
        {
            if (disposing) { _connection.Dispose(); Key.Rsa.Dispose(); }
        }
    }
}
