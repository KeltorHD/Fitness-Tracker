using System.Data.Common;
using FitnessTracker.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет expiry, каскад и гонку подтверждения на настоящем одноразовом PostgreSQL.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class PendingRegistrationPostgresTests
{
    /// <summary>Обновление прежней схемы добавляет индекс; очистка удаляет только просроченный профиль и его passkey/claims/token.</summary>
    [Fact]
    public async Task MigrationAndCleanupPreserveOtherAccountsAndCascadeExpiredCredentialsAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        var now = new DateTimeOffset(2026, 11, 8, 12, 0, 0, TimeSpan.Zero);
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton<TimeProvider>(new FrozenTimeProvider(now));
        services.AddDbContext<AuthDbContext>(options => options.UseNpgsql(fixture.ConnectionString).UseOpenIddict());
        services.AddIdentityCore<ApplicationUser>().AddEntityFrameworkStores<AuthDbContext>();
        services.AddOpenIddict().AddCore(options => options.UseEntityFrameworkCore().UseDbContext<AuthDbContext>());
        services.AddScoped<EmailAccounts>();
        services.AddScoped<PendingRegistrationCleanup>();
        await using var provider = services.BuildServiceProvider();
        await using var scope = provider.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        await database.GetService<IMigrator>().MigrateAsync("20261107150655_RequireConfirmationForNewEmailAccounts", cancellationToken);
        var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
        var accounts = scope.ServiceProvider.GetRequiredService<EmailAccounts>();
        var expired = accounts.NewUser("expired@example.com");
        expired.CreatedAt = now.AddHours(-2);
        var fresh = accounts.NewUser("fresh@example.com");
        fresh.CreatedAt = now.AddMinutes(-119);
        var confirmed = accounts.NewUser("confirmed@example.com");
        confirmed.CreatedAt = now.AddYears(-1);
        confirmed.EmailConfirmed = true;
        var legacy = accounts.NewUser("legacy@example.com");
        legacy.CreatedAt = now.AddYears(-1);
        legacy.EmailConfirmationRequired = false;
        var external = new ApplicationUser { UserName = Guid.NewGuid().ToString("N"), CreatedAt = now.AddYears(-1) };
        foreach (var user in new[] { expired, fresh, confirmed, legacy, external })
            Assert.True((await users.CreateAsync(user)).Succeeded);
        Assert.True((await users.AddPasswordAsync(legacy, "Legacy-password-123!")).Succeeded);
        var oldHash = legacy.PasswordHash;
        Assert.True((await users.AddLoginAsync(external, new UserLoginInfo("Google", "fixture-subject", "Google"))).Succeeded);
        Assert.True((await users.AddOrUpdatePasskeyAsync(expired, new UserPasskeyInfo([1, 2, 3], [4, 5, 6], expired.CreatedAt, 0,
            ["internal"], true, true, true, [7], [8]))).Succeeded);
        database.UserClaims.Add(new IdentityUserClaim<string> { UserId = expired.Id, ClaimType = "fixture", ClaimValue = "private" });
        database.UserTokens.Add(new IdentityUserToken<string> { UserId = expired.Id, LoginProvider = "fixture", Name = "fixture", Value = "private" });
        await database.SaveChangesAsync(cancellationToken);
        await database.Database.MigrateAsync(cancellationToken);
        Assert.False(database.Database.HasPendingModelChanges());
        Assert.Equal(1, await scope.ServiceProvider.GetRequiredService<PendingRegistrationCleanup>().DeleteBatchAsync(cancellationToken));
        database.ChangeTracker.Clear();
        Assert.Equal(4, await database.Users.CountAsync(cancellationToken));
        Assert.Null(await users.FindByIdAsync(expired.Id));
        Assert.Empty(await database.UserPasskeys.ToArrayAsync(cancellationToken));
        Assert.Empty(await database.UserClaims.ToArrayAsync(cancellationToken));
        Assert.Empty(await database.UserTokens.ToArrayAsync(cancellationToken));
        Assert.Single(await users.GetLoginsAsync(external));
        var preserved = Assert.IsType<ApplicationUser>(await users.FindByIdAsync(legacy.Id));
        Assert.Equal(oldHash, preserved.PasswordHash);
        Assert.True(await users.CheckPasswordAsync(preserved, "Legacy-password-123!"));
        Assert.True((await users.FindByIdAsync(confirmed.Id))?.EmailConfirmed);
        Assert.NotNull(await users.FindByIdAsync(fresh.Id));
    }

    /// <summary>Если подтверждение сохранено после выборки batch, DELETE повторно проверяет EmailConfirmed и сохраняет строку.</summary>
    [Fact]
    public async Task ConditionalDeletePreservesAConcurrentlyConfirmedAccountAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        var now = DateTimeOffset.UtcNow;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var options = new DbContextOptionsBuilder<AuthDbContext>().UseNpgsql(fixture.ConnectionString).UseOpenIddict().Options;
        var id = Guid.NewGuid().ToString();
        await using (var seed = new AuthDbContext(options))
        {
            await seed.Database.MigrateAsync(cancellationToken);
            seed.Users.Add(new ApplicationUser { Id = id, UserName = id, EmailConfirmationRequired = true, CreatedAt = now.AddHours(-2) });
            await seed.SaveChangesAsync(cancellationToken);
        }
        var gate = new DeleteGate();
        await using var database = new AuthDbContext(new DbContextOptionsBuilder<AuthDbContext>()
            .UseNpgsql(fixture.ConnectionString)
            .UseOpenIddict()
            .AddInterceptors(gate).Options);
        var cleanup = new PendingRegistrationCleanup(database, new FrozenTimeProvider(now), NullLogger<PendingRegistrationCleanup>.Instance);
        var deleting = cleanup.DeleteBatchAsync(cancellationToken);
        try
        {
            await gate.Started.Task.WaitAsync(TimeSpan.FromSeconds(15), cancellationToken);
            await using var confirming = new AuthDbContext(options);
            Assert.Equal(1, await confirming.Users.Where(user => user.Id == id)
                .ExecuteUpdateAsync(setters => setters.SetProperty(user => user.EmailConfirmed, true), cancellationToken));
        }
        finally
        {
            gate.Release.TrySetResult();
            await deleting;
        }
        Assert.Equal(0, await deleting);
        await using var verification = new AuthDbContext(options);
        Assert.True((await verification.Users.SingleAsync(cancellationToken)).EmailConfirmed);
    }

    /// <summary>Останавливает только DELETE после выборки кандидатов, без задержек и блокировок рабочего сервера.</summary>
    private sealed class DeleteGate : DbCommandInterceptor
    {
        /// <summary>Сигнал готовности условного DELETE.</summary>
        internal TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        /// <summary>Разрешает выполнение после конкурентного подтверждения.</summary>
        internal TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        /// <summary>Не меняет SQL и его результат; управляет только порядком выполнения теста.</summary>
        public override async ValueTask<InterceptionResult<int>> NonQueryExecutingAsync(DbCommand command,
            CommandEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            if (command.CommandText.Contains("DELETE FROM \"AspNetUsers\"", StringComparison.Ordinal))
            {
                Started.TrySetResult();
                await Release.Task.WaitAsync(cancellationToken);
            }
            return result;
        }
    }
}
