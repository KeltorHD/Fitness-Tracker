using Microsoft.EntityFrameworkCore;

namespace FitLife.Backend;

public sealed class BackupRecord
{
    public Guid Id { get; set; }
    public string OwnerId { get; set; } = "";
    public long CreatedAtMilliseconds { get; set; }
    public int ArchiveVersion { get; set; }
    public int Size { get; set; }
    public string Sha256 { get; set; } = "";
    public byte[] Payload { get; set; } = [];
}

public sealed class DeletedAccount
{
    public string Id { get; set; } = "";
}

public sealed class BackupDbContext(DbContextOptions<BackupDbContext> options) : DbContext(options)
{
    public DbSet<BackupRecord> Backups => Set<BackupRecord>();
    public DbSet<DeletedAccount> DeletedAccounts => Set<DeletedAccount>();
    /// <summary>Владельцы структурированных журналов и их счётчики версий.</summary>
    public DbSet<TrainingOwner> TrainingOwners => Set<TrainingOwner>();
    /// <summary>Версии агрегатов и сохранённые удаления.</summary>
    public DbSet<TrainingRecordMetadata> TrainingRecords => Set<TrainingRecordMetadata>();
    /// <summary>Тренировки со статусами, таймерами и паузами.</summary>
    public DbSet<TrainingWorkout> Workouts => Set<TrainingWorkout>();
    /// <summary>Планы и их вариации.</summary>
    public DbSet<TrainingTemplate> Templates => Set<TrainingTemplate>();
    /// <summary>Исторические снимки упражнений и дочерние подходы.</summary>
    public DbSet<TrainingExercise> Exercises => Set<TrainingExercise>();
    /// <summary>Самостоятельные замеры веса.</summary>
    public DbSet<TrainingBodyWeight> BodyWeights => Set<TrainingBodyWeight>();
    /// <summary>Записи пульса связанных тренировок.</summary>
    public DbSet<TrainingHeartRate> HeartRateRecordings => Set<TrainingHeartRate>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        builder.Entity<BackupRecord>().HasKey(backup => new { backup.OwnerId, backup.Id });
        builder.Entity<BackupRecord>().Property(backup => backup.OwnerId).HasMaxLength(36);
        builder.Entity<BackupRecord>().Property(backup => backup.Sha256).HasMaxLength(64);
        builder.Entity<BackupRecord>().HasIndex(backup => new { backup.OwnerId, backup.CreatedAtMilliseconds });
        builder.Entity<DeletedAccount>().Property(account => account.Id).HasMaxLength(36);
        TrainingModel.Configure(builder);
        NutritionModel.Configure(builder);
        HealthSyncModel.Configure(builder);
    }
}
