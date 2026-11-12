using System.Collections.Concurrent;
using System.Data.Common;
using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Xml.Linq;
using FitLife.Authentication;
using FitLife.Backend;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using OpenIddict.Abstractions;
using Xunit;

namespace FitLife.Server.Tests;

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
            // В прежней схеме нового столбца ещё нет: вставляем реальные старые поля, не текущую EF-модель.
            await database.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO "AspNetUsers" ("Id", "UserName", "DisplayName", "CreatedAt", "EmailConfirmed",
                    "PhoneNumberConfirmed", "TwoFactorEnabled", "LockoutEnabled", "AccessFailedCount")
                VALUES ({owner}, {owner}, 'Существующий аккаунт', now(), false, false, false, true, 0)
                """, cancellationToken);
        }

        // Act: обычный Production Main без CLI-флагов применяет миграции и регистрирует clients.
        var errors = new StartupCommandErrors();
        using (var factory = new StartupFactory<Authentication.Program>(fixture.ConnectionString, commandErrors: errors))
        using (var client = factory.CreateClient())
        {
            using var health = await client.GetAsync("/health", cancellationToken);
            Assert.Equal(HttpStatusCode.OK, health.StatusCode);
            Assert.Empty(errors.Errors);
        }
        await using (var database = new AuthDbContext(options))
        {
            Assert.Equal(4, (await database.Database.GetAppliedMigrationsAsync(cancellationToken)).Count());
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
        Assert.False((await verification.Users.SingleAsync(cancellationToken)).EmailConfirmationRequired);
        Assert.False((await verification.Users.SingleAsync(cancellationToken)).EmailConfirmed);
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

    /// <summary>Production startup сохраняет отдельный Personal client, обновляет его callback и удаляет при отключении.</summary>
    [Fact]
    public async Task AuthStartupConfiguresPersonalClientWithoutChangingHttpsClientAsync()
    {
        // Arrange/Act: обычный startup с явно разрешённой private-use URI scheme.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        foreach (var scheme in new string?[] { "com.example.first", "com.example.second", null })
        {
            using var factory = new StartupFactory<Authentication.Program>(fixture.ConnectionString, personalCallbackScheme: scheme);
            using var client = factory.CreateClient();
            using var health = await client.GetAsync("/health", cancellationToken);
            Assert.Equal(HttpStatusCode.OK, health.StatusCode);
            await using var scope = factory.Services.CreateAsyncScope();
            var manager = scope.ServiceProvider.GetRequiredService<IOpenIddictApplicationManager>();
            var full = await manager.FindByClientIdAsync(AuthConfiguration.ClientId, cancellationToken);
            Assert.NotNull(full);
            Assert.Equal(AuthConfiguration.Callback, Assert.Single(await manager.GetRedirectUrisAsync(full, cancellationToken)));
            var personal = await manager.FindByClientIdAsync(AuthConfiguration.PersonalClientId, cancellationToken);
            if (scheme is null) Assert.Null(personal);
            else
            {
                Assert.NotNull(personal);
                Assert.Equal(scheme + ":/ios/oauth/callback", Assert.Single(await manager.GetRedirectUrisAsync(personal, cancellationToken)));
            }
            // Assert: перезапуск не создаёт дубликаты или миграции ради регистрации клиента.
            var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            Assert.Equal(scheme is null ? 2 : 3,
                await database.Set<OpenIddict.EntityFrameworkCore.Models.OpenIddictEntityFrameworkCoreApplication>().CountAsync(cancellationToken));
            Assert.Empty(await database.Database.GetPendingMigrationsAsync(cancellationToken));
        }
    }

    /// <summary>Обычный startup обновляет прежний идентификатор архива до первого успешного HTTP-ответа.</summary>
    [Fact]
    public async Task BackendStartupMigratesPreviousArchiveIdentifierAsync()
    {
        // Arrange: существующая БД прежней схемы и резервная копия с корректными контрольными метаданными.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options;
        var id = Guid.NewGuid();
        var owner = Guid.NewGuid().ToString();
        var payload = """{"format":"com.fitnesstracker.archive","version":4,"exportedAt":1700000000,"workouts":[],"templates":[],"bodyWeights":[]}"""u8.ToArray();
        await using (var database = new BackupDbContext(options))
        {
            await database.GetService<IMigrator>().MigrateAsync("20261103183121_InitialBackups", cancellationToken);
            database.Backups.Add(new BackupRecord
            {
                Id = id,
                OwnerId = owner,
                ArchiveVersion = 4,
                CreatedAtMilliseconds = 1700000000123,
                Payload = payload,
                Size = payload.Length,
                Sha256 = Convert.ToHexStringLower(SHA256.HashData(payload))
            });
            await database.SaveChangesAsync(cancellationToken);
        }

        // Act: запуск Production Backend без ручного --migrate.
        var errors = new StartupCommandErrors();
        using var factory = new StartupFactory<Backend.Program>(fixture.ConnectionString, commandErrors: errors);
        using var client = factory.CreateClient();
        using var health = await client.GetAsync("/health", cancellationToken);

        // Assert: listener открыт после миграции, содержимое и метаданные уже согласованы.
        Assert.Equal(HttpStatusCode.OK, health.StatusCode);
        Assert.Empty(errors.Errors);
        await using var verification = new BackupDbContext(options);
        var backup = await verification.Backups.SingleAsync(cancellationToken);
        Assert.Equal(id, backup.Id);
        Assert.Equal(owner, backup.OwnerId);
        Assert.Equal(1700000000123, backup.CreatedAtMilliseconds);
        Assert.Equal(4, backup.ArchiveVersion);
        Assert.Equal(4, BackupArchiveValidator.Validate(backup.Payload));
        Assert.Equal(backup.Payload.Length, backup.Size);
        Assert.Equal(Convert.ToHexStringLower(SHA256.HashData(backup.Payload)), backup.Sha256);
        Assert.Empty(await verification.Database.GetPendingMigrationsAsync(cancellationToken));
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
        using var protectionFiles = new ProtectionFiles();
        var payload = TrainingFixture.Archive([]);
        string protectedValue;
        var errors = new StartupCommandErrors();
        using (var factory = new StartupFactory<Backend.Program>(fixture.ConnectionString,
            commandErrors: errors, protectionFiles: protectionFiles))
        using (var client = factory.CreateClient())
        {
            using var health = await client.GetAsync("/health", cancellationToken);
            Assert.Equal(HttpStatusCode.OK, health.StatusCode);
            Assert.Empty(errors.Errors);
            var protector = factory.Services.GetRequiredService<IDataProtectionProvider>().CreateProtector("startup-persistence");
            protectedValue = protector.Protect("survives-restart");
            var keys = Directory.GetFiles(Path.Combine(protectionFiles.Directory, "keys"), "key-*.xml");
            Assert.NotEmpty(keys);
            foreach (var key in keys)
            {
                var document = XDocument.Load(key);
                Assert.Contains(document.Descendants(), element => element.Name.LocalName == "encryptedSecret");
                Assert.DoesNotContain(document.Descendants(), element => element.Name.LocalName == "masterKey");
            }
            await using var database = new BackupDbContext(options);
            database.Backups.Add(new BackupRecord
            {
                Id = id,
                OwnerId = owner,
                Payload = payload,
                Size = payload.Length,
                ArchiveVersion = 4,
                Sha256 = Convert.ToHexStringLower(SHA256.HashData(payload))
            });
            database.DeletedAccounts.Add(new DeletedAccount { Id = Guid.NewGuid().ToString() });
            await database.SaveChangesAsync(cancellationToken);
        }

        // Assert: повторный startup идемпотентен и не сбрасывает данные.
        using var restarted = new StartupFactory<Backend.Program>(fixture.ConnectionString, protectionFiles: protectionFiles);
        using var restartedClient = restarted.CreateClient();
        using var restartedHealth = await restartedClient.GetAsync("/health", cancellationToken);
        Assert.Equal(HttpStatusCode.OK, restartedHealth.StatusCode);
        var restartedProtector = restarted.Services.GetRequiredService<IDataProtectionProvider>().CreateProtector("startup-persistence");
        Assert.Equal("survives-restart", restartedProtector.Unprotect(protectedValue));
        await using var verification = new BackupDbContext(options);
        var backup = await verification.Backups.SingleAsync(cancellationToken);
        Assert.Equal(id, backup.Id);
        Assert.Equal(owner, backup.OwnerId);
        Assert.Equal(payload, backup.Payload);
        Assert.Single(await verification.DeletedAccounts.ToListAsync(cancellationToken));
        Assert.Equal(3, (await verification.Database.GetAppliedMigrationsAsync(cancellationToken)).Count());
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
            WHERE datname = current_database() AND application_name = 'FitLife startup'
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

    /// <summary>Фиксирует настоящие ошибки SQL при bootstrap, в том числе перехваченные самим провайдером EF.</summary>
    private sealed class StartupCommandErrors : DbCommandInterceptor
    {
        /// <summary>SQL-сбои, которые не должны возникать при нормальной инициализации.</summary>
        public ConcurrentQueue<Exception> Errors { get; } = new();

        /// <summary>Сохраняет исключение до того, как Npgsql обработает отсутствие history как пустую схему.</summary>
        public override Task CommandFailedAsync(DbCommand command, CommandErrorEventData eventData,
            CancellationToken cancellationToken = default)
        {
            Errors.Enqueue(eventData.Exception);
            return Task.CompletedTask;
        }
    }

    /// <summary>Владеет отдельными временными PFX/DP-файлами для проверки перезапуска host.</summary>
    private sealed class ProtectionFiles : IDisposable
    {
        /// <summary>Каталог принадлежит только текущему тесту.</summary>
        public string Directory { get; } = Path.Combine(Path.GetTempPath(), "fitness-startup-" + Guid.NewGuid().ToString("N"));

        /// <summary>Удаляет временные ключи после завершения всех использовавших их host.</summary>
        public void Dispose()
        {
            if (System.IO.Directory.Exists(Directory)) System.IO.Directory.Delete(Directory, recursive: true);
        }
    }

    /// <summary>Запускает настоящий Production Main с тестовой БД, отдельными PFX/DP keys и без внешних провайдеров.</summary>
    private sealed class StartupFactory<TProgram> : WebApplicationFactory<TProgram> where TProgram : class
    {
        private readonly ProtectionFiles _protectionFiles;
        private readonly bool _ownsProtectionFiles;
        private readonly Dictionary<string, string?> _settings;
        private readonly StartupCommandErrors? _commandErrors;

        /// <summary>Создаёт исключительно временные ключи; рабочая конфигурация не используется.</summary>
        public StartupFactory(string connectionString, string introspectionSecret = AuthFactory.IntrospectionSecret,
            StartupCommandErrors? commandErrors = null, ProtectionFiles? protectionFiles = null, string? personalCallbackScheme = null)
        {
            _ownsProtectionFiles = protectionFiles is null;
            _protectionFiles = protectionFiles ?? new ProtectionFiles();
            _commandErrors = commandErrors;
            Directory.CreateDirectory(_protectionFiles.Directory);
            var pfx = Path.Combine(_protectionFiles.Directory, "test.pfx");
            if (!File.Exists(pfx))
            {
                using var rsa = RSA.Create(2048);
                var request = new CertificateRequest("CN=FitLife isolated startup", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
                using var certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddDays(1));
                File.WriteAllBytes(pfx, certificate.Export(X509ContentType.Pfx, "test-only-password"));
            }
            _settings = new()
            {
                ["ConnectionStrings:Database"] = connectionString,
                ["Auth:Issuer"] = "https://localhost/",
                ["Auth:RedirectUri"] = AuthConfiguration.Callback,
                ["Auth:PersonalCallbackScheme"] = personalCallbackScheme,
                ["Auth:IntrospectionClientSecret"] = introspectionSecret,
                ["Certificates:Signing:Path"] = pfx,
                ["Certificates:Signing:Password"] = "test-only-password",
                ["Certificates:Encryption:Path"] = pfx,
                ["Certificates:Encryption:Password"] = "test-only-password",
                ["DataProtection:Path"] = Path.Combine(_protectionFiles.Directory, "keys"),
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
            if (_commandErrors is not null)
                builder.ConfigureServices(services =>
                {
                    if (typeof(TProgram) == typeof(Authentication.Program))
                        services.ConfigureDbContext<AuthDbContext>(options => options.AddInterceptors(_commandErrors));
                    else
                        services.ConfigureDbContext<BackupDbContext>(options => options.AddInterceptors(_commandErrors));
                });
        }

        /// <summary>Завершает host и удаляет только собственные временные ключи.</summary>
        protected override void Dispose(bool disposing)
        {
            try { base.Dispose(disposing); }
            finally { if (disposing && _ownsProtectionFiles) _protectionFiles.Dispose(); }
        }
    }
}
