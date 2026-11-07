using Microsoft.EntityFrameworkCore;

namespace FitnessTracker.Backend;

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

    protected override void OnModelCreating(ModelBuilder builder)
    {
        builder.Entity<BackupRecord>().HasKey(backup => new { backup.OwnerId, backup.Id });
        builder.Entity<BackupRecord>().Property(backup => backup.OwnerId).HasMaxLength(36);
        builder.Entity<BackupRecord>().Property(backup => backup.Sha256).HasMaxLength(64);
        builder.Entity<BackupRecord>().HasIndex(backup => new { backup.OwnerId, backup.CreatedAtMilliseconds });
        builder.Entity<DeletedAccount>().Property(account => account.Id).HasMaxLength(36);
    }
}
