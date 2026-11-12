using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace FitLife.Server.Tests;

/// <summary>Имитирует отказ или отмену записи после начала транзакции, не заменяя само хранилище.</summary>
internal sealed class BackupSaveInterceptor : SaveChangesInterceptor
{
    /// <summary>Включает отказ сохранения новых копий и маркеров удалённых аккаунтов.</summary>
    internal bool Fail { get; set; }

    /// <summary>Отменяет переданный storage-вызов непосредственно перед сохранением.</summary>
    internal CancellationTokenSource? CancelBeforeSave { get; set; }

    /// <summary>Передаёт отмену или создаёт контролируемую ошибку только при записи данных бэкапа.</summary>
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        if (eventData.Context?.ChangeTracker.Entries().Any(entry =>
            entry.State == EntityState.Added && entry.Entity is BackupRecord or DeletedAccount) == true)
        {
            CancelBeforeSave?.Cancel();
            cancellationToken.ThrowIfCancellationRequested();
            if (Fail) throw new IOException("Simulated backup persistence failure.");
        }
        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }
}
