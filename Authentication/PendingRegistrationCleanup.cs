using Microsoft.EntityFrameworkCore;

namespace FitLife.Authentication;

/// <summary>Удаляет только локальные неподтверждённые регистрации старше двух часов, освобождая имя/email.</summary>
public sealed class PendingRegistrationCleanup(AuthDbContext database, TimeProvider clock,
    ILogger<PendingRegistrationCleanup> logger)
{
    private const int BATCH_SIZE = 200;

    /// <summary>Общий фиксированный срок от создания аккаунта; повтор письма не меняет CreatedAt.</summary>
    public static TimeSpan Lifetime => TimeSpan.FromHours(2);

    /// <summary>Проверяет границу срока до подтверждения, даже если фоновая очистка ещё не запускалась.</summary>
    public bool IsExpired(ApplicationUser user) => user.EmailConfirmationRequired && !user.EmailConfirmed &&
        user.CreatedAt <= clock.GetUtcNow() - Lifetime;

    /// <summary>Очищает одно нормализованное имя перед новой регистрацией; подтверждённая строка защищена SQL-предикатом.</summary>
    public Task<int> DeleteForRegistrationAsync(string normalizedUserName, CancellationToken cancellationToken) =>
        DeleteAsync(Expired().Where(user => user.NormalizedUserName == normalizedUserName), "registration", cancellationToken);

    /// <summary>Ограничивает размер фоновой операции; повторная проверка предиката защищает уже подтверждённые строки.</summary>
    public async Task<int> DeleteBatchAsync(CancellationToken cancellationToken)
    {
        var query = Expired();
        var ids = await query
            .OrderBy(user => user.CreatedAt)
            .ThenBy(user => user.Id)
            .Select(user => user.Id)
            .Take(BATCH_SIZE)
            .ToArrayAsync(cancellationToken);
        if (ids.Length == 0) return 0;
        return await DeleteAsync(query.Where(user => ids.Contains(user.Id)), "scheduled", cancellationToken);
    }

    /// <summary>Выполняет атомарный условный DELETE; связанные Identity/passkey записи удаляются FK cascade.</summary>
    private async Task<int> DeleteAsync(IQueryable<ApplicationUser> query, string operation, CancellationToken cancellationToken)
    {
        var deleted = await query.ExecuteDeleteAsync(cancellationToken);
        if (deleted > 0)
            logger.LogInformation(new EventId(4400, "PendingRegistrationsDeleted"),
                "Expired email registrations deleted: {DeletedCount}; operation {Operation}.", deleted, operation);
        return deleted;
    }

    /// <summary>Прежние и внешние аккаунты не требуют подтверждения; EmailConfirmed исключает завершённые регистрации.</summary>
    private IQueryable<ApplicationUser> Expired()
    {
        var cutoff = clock.GetUtcNow() - Lifetime;
        return database.Users.Where(user => user.EmailConfirmationRequired && !user.EmailConfirmed && user.CreatedAt <= cutoff);
    }
}

/// <summary>Запускает ограниченную очистку при старте и раз в минуту, используя новый scope на каждую попытку.</summary>
public sealed class PendingRegistrationCleanupWorker(IServiceScopeFactory scopes, TimeProvider clock,
    ILogger<PendingRegistrationCleanupWorker> logger) : BackgroundService
{
    /// <summary>Продолжает работу после временной ошибки БД и завершает ожидание/запрос по остановке приложения.</summary>
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await using var scope = scopes.CreateAsyncScope();
                var cleanup = scope.ServiceProvider.GetRequiredService<PendingRegistrationCleanup>();
                while (await cleanup.DeleteBatchAsync(stoppingToken) > 0)
                    stoppingToken.ThrowIfCancellationRequested();
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception error)
            {
                logger.LogError(new EventId(4401, "PendingRegistrationCleanupFailed"),
                    "Expired email registration cleanup failed: {ExceptionType}; retry on next interval.", error.GetType().Name);
            }
            try { await Task.Delay(TimeSpan.FromMinutes(1), clock, stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
        }
    }
}
