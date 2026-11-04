using FitnessTracker.Authentication;
using FitnessTracker.Backend;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using OpenIddict.Abstractions;
using OpenIddict.EntityFrameworkCore.Models;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет настоящие PostgreSQL-миграции и конкурирующие операции в изолированных базах.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class PostgresTests
{
    /// <summary>Настоящий PostgreSQL сохраняет удаление login и отзыв grants/tokens вместе со сменой SecurityStamp.</summary>
    [Fact]
    public async Task ProviderRemovalPersistsSessionRevocationAsync()
    {
        // Arrange: одноразовая Auth-БД с Identity и OpenIddict; нет внешних OAuth-провайдеров.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddDbContext<AuthDbContext>(options => options.UseNpgsql(fixture.ConnectionString).UseOpenIddict());
        services.AddIdentityCore<ApplicationUser>().AddEntityFrameworkStores<AuthDbContext>();
        services.AddOpenIddict().AddCore(options => options.UseEntityFrameworkCore().UseDbContext<AuthDbContext>());
        services.AddScoped<ExternalAccounts>();
        await using var provider = services.BuildServiceProvider();
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
}
