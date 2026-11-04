using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace FitnessTracker.Authentication;

public sealed class ApplicationUser : IdentityUser
{
    public string DisplayName { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class AuthDbContext(DbContextOptions<AuthDbContext> options)
    : IdentityDbContext<ApplicationUser>(options)
{
    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        builder.Entity<ApplicationUser>().Property(user => user.DisplayName).HasMaxLength(200);
        // Добавляем штатное хранилище passkey, сохраняя прежние размеры Identity-колонок.
        builder.Entity<IdentityUserPasskey<string>>(passkey =>
        {
            passkey.ToTable("AspNetUserPasskeys");
            passkey.HasKey(key => key.CredentialId);
            passkey.Property(key => key.CredentialId).HasMaxLength(1024);
            passkey.OwnsOne(key => key.Data).ToJson();
        });
        builder.Entity<ApplicationUser>()
            .HasMany<IdentityUserPasskey<string>>()
            .WithOne()
            .HasForeignKey(key => key.UserId)
            .IsRequired();
    }
}
