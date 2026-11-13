using Microsoft.EntityFrameworkCore;

namespace FitLife.Backend;

/// <summary>Структурированное состояние синхронизации Apple Health: HealthSyncOwner.</summary>
public sealed class HealthSyncOwner
{
    /// <summary>Владелец из проверенного JWT.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Монотонная версия исходных samples.</summary>
    public long Revision { get; set; }
    /// <summary>Время последней подтверждённой доставки.</summary>
    public long UpdatedAtMilliseconds { get; set; }
}

/// <summary>Структурированное состояние синхронизации Apple Health: HealthSyncDevice.</summary>
public sealed class HealthSyncDevice
{
    /// <summary>Владелец установки.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Изолированный UUID установки.</summary>
    public Guid Id { get; set; }
    /// <summary>Последний подтверждённый номер.</summary>
    public long Sequence { get; set; }
    /// <summary>Последний идемпотентный запрос.</summary>
    public Guid BatchId { get; set; }
    /// <summary>SHA-256 канонического пакета.</summary>
    public string Hash { get; set; } = "";
    /// <summary>Сохранённое подтверждение для точного повтора запроса.</summary>
    public string Acknowledgement { get; set; } = "";
}

/// <summary>Структурированное состояние синхронизации Apple Health: HealthSyncSample.</summary>
public sealed class HealthSyncSample
{
    /// <summary>Владелец измерения.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Постоянный UUID HealthKit.</summary>
    public Guid Id { get; set; }
    /// <summary>Категория величины либо sleep.</summary>
    public string Metric { get; set; } = "";
    /// <summary>Начало измерения в UTC.</summary>
    public long StartMilliseconds { get; set; }
    /// <summary>Конец измерения в UTC.</summary>
    public long EndMilliseconds { get; set; }
    /// <summary>Фактическое значение; null у сна или tombstone.</summary>
    public double? Value { get; set; }
    /// <summary>Исходное приложение/устройство.</summary>
    public string SourceId { get; set; } = "";
    /// <summary>Отображаемое название источника.</summary>
    public string SourceName { get; set; } = "";
    /// <summary>Фактическая фаза сна.</summary>
    public string? Stage { get; set; }
    /// <summary>Удалённые UUID не воскрешаются запоздалым устройством.</summary>
    public bool Deleted { get; set; }
}

/// <summary>Структурированное состояние синхронизации Apple Health: HealthSyncBucket.</summary>
public sealed class HealthSyncBucket
{
    /// <summary>Владелец сводки.</summary>
    public string OwnerId { get; set; } = "";
    /// <summary>Аддитивный показатель.</summary>
    public string Metric { get; set; } = "";
    /// <summary>Часовой пояс календарного дня.</summary>
    public string TimeZoneId { get; set; } = "";
    /// <summary>Начало календарного дня.</summary>
    public long StartMilliseconds { get; set; }
    /// <summary>Конец календарного дня.</summary>
    public long EndMilliseconds { get; set; }
    /// <summary>Версия исходных данных для CAS.</summary>
    public long Revision { get; set; }
    /// <summary>Требуется новое чтение объединённой статистики HealthKit.</summary>
    public bool Dirty { get; set; } = true;
    /// <summary>Объединённый итог HealthKit; отсутствующий не заменяется нулём.</summary>
    public double? Value { get; set; }
}

/// <summary>Настраивает изолированные health-таблицы и каскад удаления аккаунта.</summary>
internal static class HealthSyncModel
{
    /// <summary>Связывает установки, samples и сводки только с их собственным владельцем.</summary>
    internal static void Configure(ModelBuilder builder)
    {
        builder.Entity<HealthSyncOwner>().HasKey(x => x.OwnerId);
        builder.Entity<HealthSyncOwner>().Property(x => x.OwnerId).HasMaxLength(36);
        builder.Entity<HealthSyncDevice>().Property(x => x.OwnerId).HasMaxLength(36);
        builder.Entity<HealthSyncSample>().Property(x => x.OwnerId).HasMaxLength(36);
        builder.Entity<HealthSyncBucket>().Property(x => x.OwnerId).HasMaxLength(36);
        builder.Entity<HealthSyncDevice>().HasKey(x => new { x.OwnerId, x.Id });
        builder.Entity<HealthSyncDevice>().HasOne<HealthSyncOwner>().WithMany().HasForeignKey(x => x.OwnerId).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<HealthSyncSample>().HasKey(x => new { x.OwnerId, x.Id });
        builder.Entity<HealthSyncSample>().HasOne<HealthSyncOwner>().WithMany().HasForeignKey(x => x.OwnerId).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<HealthSyncBucket>().HasKey(x => new { x.OwnerId, x.Metric, x.TimeZoneId, x.StartMilliseconds });
        builder.Entity<HealthSyncBucket>().HasOne<HealthSyncOwner>().WithMany().HasForeignKey(x => x.OwnerId).OnDelete(DeleteBehavior.Cascade);
        builder.Entity<HealthSyncSample>().HasIndex(x => new { x.OwnerId, x.Metric, x.StartMilliseconds });
        builder.Entity<HealthSyncSample>().Property(x => x.Metric).HasMaxLength(32);
        builder.Entity<HealthSyncSample>().Property(x => x.SourceId).HasMaxLength(1024);
        builder.Entity<HealthSyncSample>().Property(x => x.SourceName).HasMaxLength(200);
        builder.Entity<HealthSyncSample>().Property(x => x.Stage).HasMaxLength(20);
        builder.Entity<HealthSyncBucket>().Property(x => x.Metric).HasMaxLength(32);
        builder.Entity<HealthSyncBucket>().Property(x => x.TimeZoneId).HasMaxLength(80);
        builder.Entity<HealthSyncDevice>().Property(x => x.Hash).HasMaxLength(64);
    }
}
