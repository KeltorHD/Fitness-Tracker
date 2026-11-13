using Microsoft.EntityFrameworkCore.Diagnostics;

namespace FitLife.Server.Tests;

/// <summary>Прерывает выбранный этап настоящего EF-сохранения после уже выполненных SQL внутри транзакции.</summary>
internal sealed class TrainingSaveInterceptor : SaveChangesInterceptor
{
    private int _failAt;
    private int _saves;
    private CancellationTokenSource? _cancellation;

    /// <summary>Включает отказ на указанном сохранении; ноль отключает fault injection после проверки.</summary>
    internal void Arm(int saveNumber, CancellationTokenSource? cancellation = null)
    {
        _failAt = saveNumber;
        _saves = 0;
        _cancellation = cancellation;
    }

    /// <summary>Отменяет переданный токен либо выбрасывает I/O-ошибку; EF и транзакция остаются настоящими.</summary>
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData,
        InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        if (_failAt > 0 && ++_saves == _failAt)
        {
            if (_cancellation is not null)
            {
                _cancellation.Cancel();
                cancellationToken.ThrowIfCancellationRequested();
            }
            throw new IOException("private-storage-sentinel");
        }
        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }
}
