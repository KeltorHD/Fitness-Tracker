using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using FitnessTracker.Authentication;
using FitnessTracker.Backend;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using OpenIddict.Abstractions;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет обычный Production startup на отдельных PostgreSQL-БД без ручного --migrate.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class StartupMigrationTests
{
    /// <summary>Новый сервер и обновление прежней схемы готовы до первого HTTP; повторный запуск сохраняет аккаунт и clients.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task AuthStartupMigratesAndPreservesDataOnRestartAsync(bool previousSchema)
    {
        // Arrange: пустая БД либо прежняя схема без passkeys с существующим аккаунтом.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<AuthDbContext>().UseNpgsql(fixture.ConnectionString).UseOpenIddict().Options;
        var owner = Guid.NewGuid().ToString();
        if (previousSchema)
        {
            await using var database = new AuthDbContext(options);
            await database.GetService<IMigrator>().MigrateAsync("20261103183016_InitialAuth", cancellationToken);
            database.Users.Add(new ApplicationUser { Id = owner, UserName = owner, DisplayName = "Существующий аккаунт" });
            await database.SaveChangesAsync(cancellationToken);
        }

        // Act: обычный Production Main без CLI-флагов применяет миграции и регистрирует clients.
        using (var factory = new StartupFactory<Authentication.Program>(fixture.ConnectionString))
        using (var client = factory.CreateClient())
        {
            using var health = await client.GetAsync("/health", cancellationToken);
            Assert.Equal(HttpStatusCode.OK, health.StatusCode);
        }
        await using (var database = new AuthDbContext(options))
        {
            Assert.Equal(2, (await database.Database.GetAppliedMigrationsAsync(cancellationToken)).Count());
            Assert.Empty(await database.Database.GetPendingMigrationsAsync(cancellationToken));
            Assert.Empty(await database.UserPasskeys.ToListAsync(cancellationToken));
            if (!previousSchema)
            {
                database.Users.Add(new ApplicationUser { Id = owner, UserName = owner, DisplayName = "Существующий аккаунт" });
                await database.SaveChangesAsync(cancellationToken);
            }
        }

        // Assert: повторный startup не создаёт дубликаты и обновляет confidential secret.
        var rotatedSecret = AuthFactory.IntrospectionSecret + "-rotated";
        using var restarted = new StartupFactory<Authentication.Program>(fixture.ConnectionString, rotatedSecret);
        using var restartedClient = restarted.CreateClient();
        using var restartedHealth = await restartedClient.GetAsync("/health", cancellationToken);
        Assert.Equal(HttpStatusCode.OK, restartedHealth.StatusCode);
        await using var scope = restarted.Services.CreateAsyncScope();
        var verification = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        Assert.Equal("Существующий аккаунт", (await verification.Users.SingleAsync(cancellationToken)).DisplayName);
        Assert.Equal(2, await verification.Set<OpenIddict.EntityFrameworkCore.Models.OpenIddictEntityFrameworkCoreApplication>().CountAsync(cancellationToken));
        var applications = scope.ServiceProvider.GetRequiredService<IOpenIddictApplicationManager>();
        var ios = await applications.FindByClientIdAsync(AuthConfiguration.ClientId, cancellationToken);
        Assert.NotNull(ios);
        Assert.Equal(AuthConfiguration.Callback, Assert.Single(await applications.GetRedirectUrisAsync(ios, cancellationToken)));
        var backend = await applications.FindByClientIdAsync(AuthConfiguration.Audience, cancellationToken);
        Assert.NotNull(backend);
        Assert.True(await applications.ValidateClientSecretAsync(backend, rotatedSecret, cancellationToken));
        Assert.False(await applications.ValidateClientSecretAsync(backend, AuthFactory.IntrospectionSecret, cancellationToken));
    }

    /// <summary>Backend создаёт схему перед HTTP и при повторном запуске сохраняет архив и запрет удалённого аккаунта.</summary>
    [Fact]
    public async Task BackendStartupMigratesAndPreservesBackupsOnRestartAsync()
    {
        // Arrange/Act: первый обычный startup на пустой БД.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options;
        var id = Guid.NewGuid();
        var owner = Guid.NewGuid().ToString();
        using (var factory = new StartupFactory<Backend.Program>(fixture.ConnectionString))
        using (var client = factory.CreateClient())
        {
            using var health = await client.GetAsync("/health", cancellationToken);
            Assert.Equal(HttpStatusCode.OK, health.StatusCode);
            await using var database = new BackupDbContext(options);
            database.Backups.Add(new BackupRecord { Id = id, OwnerId = owner, Payload = [1, 2, 3], Size = 3, Sha256 = "preserved" });
            database.DeletedAccounts.Add(new DeletedAccount { Id = Guid.NewGuid().ToString() });
            await database.SaveChangesAsync(cancellationToken);
        }

        // Assert: повторный startup идемпотентен и не сбрасывает данные.
        using var restarted = new StartupFactory<Backend.Program>(fixture.ConnectionString);
        using var restartedClient = restarted.CreateClient();
        using var restartedHealth = await restartedClient.GetAsync("/health", cancellationToken);
        Assert.Equal(HttpStatusCode.OK, restartedHealth.StatusCode);
        await using var verification = new BackupDbContext(options);
        var backup = await verification.Backups.SingleAsync(cancellationToken);
        Assert.Equal(id, backup.Id);
        Assert.Equal(owner, backup.OwnerId);
        Assert.Equal(new byte[] { 1, 2, 3 }, backup.Payload);
        Assert.Single(await verification.DeletedAccounts.ToListAsync(cancellationToken));
        Assert.Single(await verification.Database.GetAppliedMigrationsAsync(cancellationToken));
    }

    /// <summary>Ошибка миграции обоих сервисов прерывает запуск до доступности HTTP.</summary>
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task MigrationFailurePreventsHttpStartupAsync(bool authentication)
    {
        // Arrange: конфликтующая таблица имитирует повреждённую либо неподходящую схему.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using (var connection = new NpgsqlConnection(fixture.ConnectionString))
        {
            await connection.OpenAsync(cancellationToken);
            var sql = authentication ? "CREATE TABLE \"AspNetUsers\" (\"Conflict\" int)" : "CREATE TABLE \"Backups\" (\"Conflict\" int)";
            await using var command = new NpgsqlCommand(sql, connection);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        // Act/Assert: WebApplicationFactory не может получить даже первый HTTP-клиент.
        Exception failure;
        if (authentication)
        {
            using var factory = new StartupFactory<Authentication.Program>(fixture.ConnectionString);
            failure = Assert.ThrowsAny<Exception>(() => factory.CreateClient());
        }
        else
        {
            using var factory = new StartupFactory<Backend.Program>(fixture.ConnectionString);
            failure = Assert.ThrowsAny<Exception>(() => factory.CreateClient());
        }
        Assert.Equal(PostgresErrorCodes.DuplicateTable, Assert.IsType<PostgresException>(failure.GetBaseException()).SqlState);
    }

    /// <summary>Два Auth host одновременно проходят первый startup без дубликатов OAuth clients.</summary>
    [Fact]
    public async Task ConcurrentAuthStartupSerializesClientRegistrationAsync()
    {
        // Arrange: отдельная БД; удерживаем startup lock до встречи обоих host.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var gate = new NpgsqlConnection(fixture.ConnectionString);
        await gate.OpenAsync(cancellationToken);
        await using (var acquire = new NpgsqlCommand("SELECT pg_advisory_lock(447295635001)", gate))
            await acquire.ExecuteNonQueryAsync(cancellationToken);
        using var first = new StartupFactory<Authentication.Program>(fixture.ConnectionString);
        using var second = new StartupFactory<Authentication.Program>(fixture.ConnectionString);

        // Act: CreateClient синхронно запускает host; оба должны ожидать один PostgreSQL lock.
        var firstStart = Task.Run(() => first.CreateClient(), cancellationToken);
        var secondStart = Task.Run(() => second.CreateClient(), cancellationToken);
        await using (var waiting = new NpgsqlCommand("""
            SELECT count(*) FROM pg_stat_activity
            WHERE datname = current_database() AND application_name = 'FitnessTracker startup'
                AND wait_event_type = 'Lock'
            """, gate))
        {
            while ((long)(await waiting.ExecuteScalarAsync(cancellationToken))! != 2)
            {
                if (firstStart.IsFaulted) await firstStart;
                if (secondStart.IsFaulted) await secondStart;
            }
        }
        await using (var release = new NpgsqlCommand("SELECT pg_advisory_unlock(447295635001)", gate))
            await release.ExecuteNonQueryAsync(cancellationToken);
        var starts = await Task.WhenAll(firstStart, secondStart);
        using var firstClient = starts[0];
        using var secondClient = starts[1];

        // Assert: оба host принимают HTTP, а регистрации остаются единственными.
        using var firstHealth = await firstClient.GetAsync("/health", cancellationToken);
        using var secondHealth = await secondClient.GetAsync("/health", cancellationToken);
        Assert.Equal(HttpStatusCode.OK, firstHealth.StatusCode);
        Assert.Equal(HttpStatusCode.OK, secondHealth.StatusCode);
        await using var scope = first.Services.CreateAsyncScope();
        Assert.Equal(2, await scope.ServiceProvider.GetRequiredService<AuthDbContext>()
            .Set<OpenIddict.EntityFrameworkCore.Models.OpenIddictEntityFrameworkCoreApplication>().CountAsync(cancellationToken));
    }

    /// <summary>Запускает настоящий Production Main с тестовой БД, отдельными PFX/DP keys и без внешних провайдеров.</summary>
    private sealed class StartupFactory<TProgram> : WebApplicationFactory<TProgram> where TProgram : class
    {
        private readonly string _directory = Path.Combine(Path.GetTempPath(), "fitness-startup-" + Guid.NewGuid().ToString("N"));
        private readonly Dictionary<string, string?> _settings;

        /// <summary>Создаёт исключительно временные ключи; рабочая конфигурация не используется.</summary>
        public StartupFactory(string connectionString, string introspectionSecret = AuthFactory.IntrospectionSecret)
        {
            Directory.CreateDirectory(_directory);
            using var rsa = RSA.Create(2048);
            var request = new CertificateRequest("CN=FitnessTracker isolated startup", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            using var certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddDays(1));
            var pfx = Path.Combine(_directory, "test.pfx");
            File.WriteAllBytes(pfx, certificate.Export(X509ContentType.Pfx, "test-only-password"));
            _settings = new()
            {
                ["ConnectionStrings:Database"] = connectionString,
                ["Auth:Issuer"] = "https://localhost/",
                ["Auth:RedirectUri"] = AuthConfiguration.Callback,
                ["Auth:IntrospectionClientSecret"] = introspectionSecret,
                ["Certificates:Signing:Path"] = pfx,
                ["Certificates:Signing:Password"] = "test-only-password",
                ["Certificates:Encryption:Path"] = pfx,
                ["Certificates:Encryption:Password"] = "test-only-password",
                ["DataProtection:Path"] = Path.Combine(_directory, "keys"),
                ["Providers:Google:Enabled"] = "false",
                ["Providers:Apple:Enabled"] = "false",
                ["Providers:Yandex:Enabled"] = "false",
                ["AllowedHosts"] = "localhost",
                ["Logging:LogLevel:Default"] = "None"
            };
        }

        /// <summary>Задаёт тестовые настройки до bootstrap и сохраняет Production-путь инициализации БД.</summary>
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Production");
            foreach (var setting in _settings) builder.UseSetting(setting.Key, setting.Value);
            builder.ConfigureAppConfiguration((_, configuration) =>
            {
                configuration.Sources.Clear();
                configuration.AddInMemoryCollection(_settings);
            });
        }

        /// <summary>Завершает host и удаляет только собственные временные ключи.</summary>
        protected override void Dispose(bool disposing)
        {
            try { base.Dispose(disposing); }
            finally { if (disposing && Directory.Exists(_directory)) Directory.Delete(_directory, recursive: true); }
        }
    }
}
