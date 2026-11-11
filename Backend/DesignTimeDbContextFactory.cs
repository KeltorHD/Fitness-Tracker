using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace FitLife.Backend;

public sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<BackupDbContext>
{
    public BackupDbContext CreateDbContext(string[] args) => new(new DbContextOptionsBuilder<BackupDbContext>()
        .UseNpgsql(Environment.GetEnvironmentVariable("ConnectionStrings__Database") ??
            "Host=localhost;Database=backend;Username=backend").Options);
}
