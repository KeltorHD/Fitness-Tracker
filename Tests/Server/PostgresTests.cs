using FitnessTracker.Authentication;
using FitnessTracker.Backend;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection;
using OpenIddict.Abstractions;
using OpenIddict.EntityFrameworkCore.Models;
using OpenIddict.Server;
using System.Security.Claims;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет настоящие PostgreSQL-миграции и конкурирующие операции в изолированных базах.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class PostgresTests
{
    /// <summary>Миграция passkey сохраняет прежние аккаунты/длинные поля; штатное JSONB-хранилище Identity работает после обновления.</summary>
    [Fact]
    public async Task PasskeyMigrationPreservesExistingAccountsAndRoundTripsIdentityDataAsync()
    {
        // Arrange: первоначальная схема и существующий парольный аккаунт с внешним login.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var provider = CreateAuthProvider(fixture.ConnectionString);
        string owner;
        string passwordHash;
        byte[] credentialId = System.Security.Cryptography.RandomNumberGenerator.GetBytes(32);
        byte[] publicKey = [1, 2, 3, 4];
        await using (var scope = provider.CreateAsyncScope())
        {
            var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            await database.GetService<IMigrator>().MigrateAsync("20261103183016_InitialAuth", cancellationToken);
            var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var user = new ApplicationUser
            { UserName = Guid.NewGuid().ToString("N"), PhoneNumber = new string('1', 300), Email = "legacy@fitness.test" };
            owner = user.Id;
            passwordHash = users.PasswordHasher.HashPassword(user, "Legacy-password-123!");
            var normalizedName = users.NormalizeName(user.UserName);
            var oldStamp = Guid.NewGuid().ToString();
            var providerKey = new string('s', 180);
            // Текущая EF-модель содержит новый столбец: старую строку создаём только полями прежней схемы.
            await database.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO "AspNetUsers" ("Id", "UserName", "NormalizedUserName", "DisplayName", "CreatedAt",
                    "Email", "EmailConfirmed", "PasswordHash", "SecurityStamp", "PhoneNumber", "PhoneNumberConfirmed",
                    "TwoFactorEnabled", "LockoutEnabled", "AccessFailedCount")
                VALUES ({owner}, {user.UserName}, {normalizedName}, 'Legacy', now(), {user.Email}, false,
                    {passwordHash}, {oldStamp}, {user.PhoneNumber}, false, false, true, 0)
                """, cancellationToken);
            await database.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO "AspNetUserLogins" ("LoginProvider", "ProviderKey", "ProviderDisplayName", "UserId")
                VALUES ('Google', {providerKey}, 'Google', {owner})
                """, cancellationToken);

            // Act: применение новой additive migration к базе с данными, затем сохранение passkey через настоящий UserManager.
            await database.Database.MigrateAsync(cancellationToken);
            Assert.False(database.Database.HasPendingModelChanges());
            user = Assert.IsType<ApplicationUser>(await users.FindByIdAsync(owner));
            Assert.False(user.EmailConfirmationRequired);
            Assert.False(user.EmailConfirmed);
            var passkey = new UserPasskeyInfo(credentialId, publicKey, DateTimeOffset.UtcNow, 0,
                ["internal"], true, true, true, [5, 6], [7, 8])
            { Name = "Мой iPhone" };
            Assert.True((await users.AddOrUpdatePasskeyAsync(user, passkey)).Succeeded);
            // Одноразовая БД: воспроизводим upgrade последней прежней схемы с уже сохранённым passkey.
            await database.GetService<IMigrator>().MigrateAsync("20261104110640_AddPasskeys", cancellationToken);
            await database.Database.MigrateAsync(cancellationToken);
        }

        // Assert: новый scope читает JSONB с байтами и флагами; legacy password/login не изменились.
        await using (var scope = provider.CreateAsyncScope())
        {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var user = Assert.IsType<ApplicationUser>(await users.FindByIdAsync(owner));
            Assert.Equal(passwordHash, user.PasswordHash);
            Assert.False(user.EmailConfirmationRequired);
            Assert.False(user.EmailConfirmed);
            Assert.Equal(300, user.PhoneNumber?.Length);
            Assert.Equal(180, Assert.Single(await users.GetLoginsAsync(user)).ProviderKey.Length);
            Assert.True(await users.CheckPasswordAsync(user, "Legacy-password-123!"));
            var passkey = Assert.Single(await users.GetPasskeysAsync(user));
            Assert.Equal(credentialId, passkey.CredentialId);
            Assert.Equal(publicKey, passkey.PublicKey);
            Assert.Equal("Мой iPhone", passkey.Name);
            Assert.True(passkey.IsBackedUp);
            Assert.True(passkey.IsBackupEligible);
            Assert.Equal(owner, (await users.FindByPasskeyIdAsync(credentialId))?.Id);
            passkey.SignCount = 2;
            Assert.True((await users.AddOrUpdatePasskeyAsync(user, passkey)).Succeeded);
        }
        await using (var scope = provider.CreateAsyncScope())
        {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var user = Assert.IsType<ApplicationUser>(await users.FindByIdAsync(owner));
            Assert.Equal(2u, Assert.Single(await users.GetPasskeysAsync(user)).SignCount);
            Assert.True((await users.DeleteAsync(user)).Succeeded);
            Assert.Null(await users.FindByPasskeyIdAsync(credentialId));
        }
    }

    /// <summary>Logout атомарно отзывает только выбранную сессию; отказ записи токенов откатывает также grant.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task SessionRevocationIsAtomicAndIsolatedAsync(bool rejectTokenUpdate)
    {
        // Arrange: реальные строки двух сессий одного пользователя в отдельной PostgreSQL-БД.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var provider = CreateAuthProvider(fixture.ConnectionString);
        await using var scope = provider.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        await database.Database.MigrateAsync(cancellationToken);
        var authorizations = scope.ServiceProvider.GetRequiredService<IOpenIddictAuthorizationManager>();
        var tokens = scope.ServiceProvider.GetRequiredService<IOpenIddictTokenManager>();
        var owner = Guid.NewGuid().ToString();
        var grants = new List<string>();
        var tokenIds = new List<string>();
        for (var index = 0; index < 2; index++)
        {
            var grant = await authorizations.CreateAsync(new OpenIddictAuthorizationDescriptor
            {
                Subject = owner,
                Status = OpenIddictConstants.Statuses.Valid,
                Type = OpenIddictConstants.AuthorizationTypes.Permanent
            }, cancellationToken);
            var grantId = Assert.IsType<string>(await authorizations.GetIdAsync(grant, cancellationToken));
            grants.Add(grantId);
            var token = await tokens.CreateAsync(new OpenIddictTokenDescriptor
            {
                Subject = owner,
                AuthorizationId = grantId,
                Status = OpenIddictConstants.Statuses.Valid,
                Type = OpenIddictConstants.TokenTypeIdentifiers.RefreshToken
            }, cancellationToken);
            tokenIds.Add(Assert.IsType<string>(await tokens.GetIdAsync(token, cancellationToken)));
        }
        if (rejectTokenUpdate)
        {
            // Trigger существует только в случайной тестовой БД и имитирует отказ второй части транзакции.
            await database.Database.ExecuteSqlRawAsync("""
                CREATE FUNCTION reject_test_revocation() RETURNS trigger LANGUAGE plpgsql AS $$
                BEGIN RAISE EXCEPTION 'Synthetic token revocation failure.'; END; $$;
                CREATE TRIGGER reject_test_revocation BEFORE UPDATE ON "OpenIddictTokens"
                FOR EACH ROW EXECUTE FUNCTION reject_test_revocation();
                """, cancellationToken);
        }
        var context = new OpenIddictServerEvents.HandleRevocationRequestContext(new OpenIddictServerTransaction())
        {
            GenericTokenPrincipal = new ClaimsPrincipal(new ClaimsIdentity()).SetTokenId(tokenIds[0])
        };
        var handler = new RevokeSessionHandler(database, tokens, authorizations);

        // Act: вызывается тот же обработчик после штатной protocol/client проверки OpenIddict.
        if (rejectTokenUpdate)
        {
            var error = await Assert.ThrowsAnyAsync<Exception>(() => handler.HandleAsync(context).AsTask());
            Assert.Equal("P0001", Assert.IsType<Npgsql.PostgresException>(error.GetBaseException()).SqlState);
        }
        else
        {
            await handler.HandleAsync(context);
            Assert.False(context.IsRejected);
        }

        // Assert: свежий DbContext проверяет commit/rollback и сохранность второй сессии.
        await using var verification = new AuthDbContext(new DbContextOptionsBuilder<AuthDbContext>()
            .UseNpgsql(fixture.ConnectionString)
            .UseOpenIddict()
            .Options);
        for (var index = 0; index < 2; index++)
        {
            var expected = index == 0 && !rejectTokenUpdate ? OpenIddictConstants.Statuses.Revoked : OpenIddictConstants.Statuses.Valid;
            var grant = await verification.Set<OpenIddictEntityFrameworkCoreAuthorization>()
                .SingleAsync(value => value.Id == grants[index], cancellationToken);
            var token = await verification.Set<OpenIddictEntityFrameworkCoreToken>()
                .SingleAsync(value => value.Id == tokenIds[index], cancellationToken);
            Assert.Equal(expected, grant.Status);
            Assert.Equal(expected, token.Status);
        }
    }

    /// <summary>Настоящий PostgreSQL сохраняет удаление login и отзыв grants/tokens вместе со сменой SecurityStamp.</summary>
    [Fact]
    public async Task ProviderRemovalPersistsSessionRevocationAsync()
    {
        // Arrange: одноразовая Auth-БД с Identity и OpenIddict; нет внешних OAuth-провайдеров.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var provider = CreateAuthProvider(fixture.ConnectionString);
        await using var scope = provider.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        await database.Database.MigrateAsync(cancellationToken);
        var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
        var user = new ApplicationUser { Id = Guid.NewGuid().ToString(), UserName = Guid.NewGuid().ToString("N") };
        Assert.True((await users.CreateAsync(user)).Succeeded);
        Assert.True((await users.AddLoginAsync(user, new UserLoginInfo("Google", "google-subject", "Google"))).Succeeded);
        Assert.True((await users.AddLoginAsync(user, new UserLoginInfo("Apple", "apple-subject", "Apple"))).Succeeded);
        var originalStamp = user.SecurityStamp;
        var authorizations = scope.ServiceProvider.GetRequiredService<IOpenIddictAuthorizationManager>();
        var authorization = await authorizations.CreateAsync(new OpenIddictAuthorizationDescriptor
        {
            Subject = user.Id,
            Status = OpenIddictConstants.Statuses.Valid,
            Type = OpenIddictConstants.AuthorizationTypes.Permanent
        }, cancellationToken);
        var tokens = scope.ServiceProvider.GetRequiredService<IOpenIddictTokenManager>();
        await tokens.CreateAsync(new OpenIddictTokenDescriptor
        {
            Subject = user.Id,
            AuthorizationId = await authorizations.GetIdAsync(authorization, cancellationToken),
            Status = OpenIddictConstants.Statuses.Valid,
            Type = OpenIddictConstants.TokenTypeIdentifiers.RefreshToken
        }, cancellationToken);

        // Act: рабочий сервис выполняет все изменения в одной транзакции.
        Assert.True(await scope.ServiceProvider.GetRequiredService<ExternalAccounts>().Unlink(user, "Google", cancellationToken));

        // Assert: новый DbContext читает сохранённые статусы, минуя tracking и кэш managers.
        await using var verification = new AuthDbContext(new DbContextOptionsBuilder<AuthDbContext>()
            .UseNpgsql(fixture.ConnectionString)
            .UseOpenIddict()
            .Options);
        Assert.Equal("Apple", (await verification.UserLogins.SingleAsync(cancellationToken)).LoginProvider);
        Assert.NotEqual(originalStamp, (await verification.Users.SingleAsync(cancellationToken)).SecurityStamp);
        Assert.Equal(OpenIddictConstants.Statuses.Revoked,
            (await verification.Set<OpenIddictEntityFrameworkCoreAuthorization>().SingleAsync(cancellationToken)).Status);
        Assert.Equal(OpenIddictConstants.Statuses.Revoked,
            (await verification.Set<OpenIddictEntityFrameworkCoreToken>().SingleAsync(cancellationToken)).Status);
    }

    /// <summary>Раздельные базы применяют миграции без расхождений модели; гонка загрузок соблюдает квоту.</summary>
    [Fact]
    public async Task RealMigrationsAndConcurrentQuotaRemainConsistentAsync()
    {
        // Arrange: отдельная БД каждого сервиса, существующие миграции и ограниченный срок теста.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var auth = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var backups = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(backups.ConnectionString).Options;
        await using (var database = new BackupDbContext(options))
        {
            await database.Database.MigrateAsync(cancellationToken);
            Assert.False(database.Database.HasPendingModelChanges());
        }
        await using (var database = new Authentication.AuthDbContext(
            new DbContextOptionsBuilder<Authentication.AuthDbContext>().UseNpgsql(auth.ConnectionString).UseOpenIddict().Options))
        {
            await database.Database.MigrateAsync(cancellationToken);
            Assert.False(database.Database.HasPendingModelChanges());
            Assert.Empty(await database.Users.ToListAsync(cancellationToken));
        }
        var owner = Guid.NewGuid().ToString();
        for (var index = 0; index < BackupStorage.MaximumCopies - 1; index++)
            Assert.Equal(201, await UploadAsync(options, owner, Guid.NewGuid(), cancellationToken));

        // Act: четыре независимых DbContext одновременно занимают последний слот.
        var results = await Task.WhenAll(Enumerable.Range(0, 4)
            .Select(_ => UploadAsync(options, owner, Guid.NewGuid(), cancellationToken)));

        // Assert: только одна загрузка создана; квота не превышена и существующие копии не вытеснены.
        Assert.Single(results, value => value == 201);
        Assert.Equal(3, results.Count(value => value == 409));
        await using var verification = new BackupDbContext(options);
        Assert.Equal(BackupStorage.MaximumCopies, await verification.Backups.CountAsync(cancellationToken));
    }

    /// <summary>При любом порядке гонки удаления и PUT данные владельца удалены, чужая копия сохранена.</summary>
    [Fact]
    public async Task AccountDeletionSerializesWithConcurrentUploadAsync()
    {
        // Arrange: пользователь с копией и независимый пользователь, которого нельзя затронуть.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(fixture.ConnectionString).Options;
        await using (var database = new BackupDbContext(options)) await database.Database.MigrateAsync(cancellationToken);
        var owner = Guid.NewGuid().ToString();
        var other = Guid.NewGuid().ToString();
        Assert.Equal(201, await UploadAsync(options, owner, Guid.NewGuid(), cancellationToken));
        Assert.Equal(201, await UploadAsync(options, other, Guid.NewGuid(), cancellationToken));

        // Act: удаление и загрузка используют разные соединения и общий per-user advisory lock.
        var uploading = UploadAsync(options, owner, Guid.NewGuid(), cancellationToken);
        var deleting = DeleteOwnerAsync(options, owner, cancellationToken);
        await Task.WhenAll(uploading, deleting);

        // Assert: PUT либо успел до удаления, либо отклонён; итоговые данные от порядка не зависят.
        Assert.Contains(await uploading, new[] { 201, 403 });
        await using (var verification = new BackupDbContext(options))
        {
            Assert.False(await verification.Backups.AnyAsync(item => item.OwnerId == owner, cancellationToken));
            Assert.Single(await verification.Backups.Where(item => item.OwnerId == other).ToListAsync(cancellationToken));
            Assert.True(await verification.DeletedAccounts.AnyAsync(item => item.Id == owner, cancellationToken));
        }
        await DeleteOwnerAsync(options, owner, cancellationToken);
        Assert.Equal(403, await UploadAsync(options, owner, Guid.NewGuid(), cancellationToken));
    }

    /// <summary>Возвращает ожидаемые бизнес-отказы; инфраструктурные ошибки не скрываются.</summary>
    private static async Task<int> UploadAsync(DbContextOptions<BackupDbContext> options, string owner, Guid id,
        CancellationToken cancellationToken)
    {
        await using var database = new BackupDbContext(options);
        try
        {
            await new BackupStorage(database, new FrozenTimeProvider(BackendFactory.BackupTime)).Put(owner, id,
                """{"format":"com.fitnesstracker.archive","version":4,"exportedAt":1700000000,"workouts":[],"templates":[],"bodyWeights":[]}"""u8.ToArray(),
                cancellationToken);
            return 201;
        }
        catch (BackupException error) { return error.Status; }
    }

    /// <summary>Удаляет данные владельца на отдельном соединении, как независимый запрос сервиса.</summary>
    private static async Task DeleteOwnerAsync(DbContextOptions<BackupDbContext> options, string owner,
        CancellationToken cancellationToken)
    {
        await using var database = new BackupDbContext(options);
        await new BackupStorage(database, TimeProvider.System).DeleteAccount(owner, cancellationToken);
    }

    /// <summary>Создаёт изолированные Identity/OpenIddict services без рабочих конфигов и внешних провайдеров.</summary>
    private static ServiceProvider CreateAuthProvider(string connectionString)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddDbContext<AuthDbContext>(options => options.UseNpgsql(connectionString).UseOpenIddict());
        services.AddIdentityCore<ApplicationUser>().AddEntityFrameworkStores<AuthDbContext>();
        services.AddOpenIddict().AddCore(options => options.UseEntityFrameworkCore().UseDbContext<AuthDbContext>());
        services.AddScoped<ExternalAccounts>();
        return services.BuildServiceProvider();
    }
}
