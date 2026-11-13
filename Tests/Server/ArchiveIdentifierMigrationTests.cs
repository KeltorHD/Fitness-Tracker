using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет обновление сохранённых JSON-архивов на отдельных PostgreSQL-БД.</summary>
[Trait("Category", "PostgreSQL")]
public sealed class ArchiveIdentifierMigrationTests
{
    private const string INITIAL_MIGRATION = "20261103183121_InitialBackups";
    private const string ARCHIVE_MIGRATION = "20261111184926_UpdateArchiveFormatIdentifier";

    /// <summary>Меняет только корневой идентификатор и контрольные метаданные, сохраняя версии и данные владельцев.</summary>
    [Theory]
    [InlineData("com.fitnesstracker.archive", 4)]
    [InlineData("com.fitsession.archive", 4)]
    [InlineData("com.fitnesstracker.archive", 1)]
    public async Task MigratesPreviousIdentifiersWithoutChangingArchiveDataAsync(string format, int version)
    {
        // Arrange: прежняя схема с архивами разных владельцев и уже текущим/посторонним форматом.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var database = new BackupDbContext(new DbContextOptionsBuilder<BackupDbContext>()
            .UseNpgsql(fixture.ConnectionString).Options);
        await database.GetService<IMigrator>().MigrateAsync(INITIAL_MIGRATION, cancellationToken);
        var original = CreateRecord(CreatePayload(format, version), "owner-a", version);
        var current = CreateRecord(CreatePayload("com.fitlife.archive", 4), "owner-b");
        var unrelated = CreateRecord(CreatePayload("com.example.unrelated", 4), "owner-c");
        current.Id = original.Id;
        unrelated.Id = original.Id;
        database.Backups.AddRange(original, current, unrelated);
        database.DeletedAccounts.Add(new DeletedAccount { Id = "deleted-owner" });
        await database.SaveChangesAsync(cancellationToken);

        // Act: штатный migrator выполняет одноразовую data migration в своей транзакции.
        await database.GetService<IMigrator>().MigrateAsync(ARCHIVE_MIGRATION, cancellationToken);
        var migrated = await database.Backups.AsNoTracking().SingleAsync(item => item.OwnerId == original.OwnerId, cancellationToken);

        // Assert: все вложенные JSON-значения, UUID, даты и версии сохранены без перекодирования.
        Assert.Equal(original.Id, migrated.Id);
        Assert.Equal(original.OwnerId, migrated.OwnerId);
        Assert.Equal(original.CreatedAtMilliseconds, migrated.CreatedAtMilliseconds);
        Assert.Equal(version, migrated.ArchiveVersion);
        using var before = JsonDocument.Parse(original.Payload);
        using var after = JsonDocument.Parse(migrated.Payload);
        Assert.Equal("com.fitlife.archive", after.RootElement.GetProperty("format").GetString());
        foreach (var property in before.RootElement.EnumerateObject().Where(item => item.Name != "format"))
            Assert.Equal(property.Value.GetRawText(), after.RootElement.GetProperty(property.Name).GetRawText());
        Assert.Equal(migrated.Payload.Length, migrated.Size);
        Assert.Equal(Convert.ToHexStringLower(SHA256.HashData(migrated.Payload)), migrated.Sha256);
        Assert.NotEqual(original.Sha256, migrated.Sha256);
        if (version == 4) Assert.Equal(4, BackupArchiveValidator.Validate(migrated.Payload));
        foreach (var untouched in new[] { current, unrelated })
        {
            var actual = await database.Backups.AsNoTracking().SingleAsync(item => item.OwnerId == untouched.OwnerId, cancellationToken);
            Assert.Equal(untouched.Payload, actual.Payload);
            Assert.Equal(untouched.Size, actual.Size);
            Assert.Equal(untouched.Sha256, actual.Sha256);
        }
        Assert.Equal("deleted-owner", (await database.DeletedAccounts.SingleAsync(cancellationToken)).Id);
        Assert.Equal(3, await database.Backups.CountAsync(cancellationToken));
        Assert.False(database.Database.HasPendingModelChanges());
        Assert.Equal(2, (await database.Database.GetAppliedMigrationsAsync(cancellationToken)).Count());
        await database.GetService<IMigrator>().MigrateAsync(ARCHIVE_MIGRATION, cancellationToken);
        var repeated = await database.Backups.AsNoTracking().SingleAsync(item => item.OwnerId == original.OwnerId, cancellationToken);
        Assert.Equal(migrated.Payload, repeated.Payload);
        Assert.Equal(migrated.Sha256, repeated.Sha256);
    }

    /// <summary>Разбирает экранированные ключи и значения JSON, не заменяя похожий текст внутри пользовательских строк.</summary>
    [Fact]
    public async Task HandlesEscapedRootIdentifierAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var database = new BackupDbContext(new DbContextOptionsBuilder<BackupDbContext>()
            .UseNpgsql(fixture.ConnectionString).Options);
        await database.GetService<IMigrator>().MigrateAsync(INITIAL_MIGRATION, cancellationToken);
        var payload = """
            {"metadata":{"format":"com.fitnesstracker.archive"},"\u0066ormat":"com.\u0066itnesstracker.archive",
             "version":4,"exportedAt":1700000000.123456789,"workouts":[],"templates":[],"bodyWeights":[]}
            """;
        database.Backups.Add(CreateRecord(Encoding.UTF8.GetBytes(payload), "owner"));
        await database.SaveChangesAsync(cancellationToken);

        await database.GetService<IMigrator>().MigrateAsync(ARCHIVE_MIGRATION, cancellationToken);

        var migrated = await database.Backups.AsNoTracking().SingleAsync(cancellationToken);
        using var document = JsonDocument.Parse(migrated.Payload);
        Assert.Equal("com.fitlife.archive", document.RootElement.GetProperty("format").GetString());
        Assert.Equal("com.fitnesstracker.archive", document.RootElement.GetProperty("metadata").GetProperty("format").GetString());
        Assert.Equal("1700000000.123456789", document.RootElement.GetProperty("exportedAt").GetRawText());
        Assert.Equal(4, BackupArchiveValidator.Validate(migrated.Payload));
    }

    /// <summary>Ошибка содержимого или исходной целостности откатывает все архивы и history без утечки payload.</summary>
    [Theory]
    [InlineData("json")]
    [InlineData("utf8")]
    [InlineData("unsupported-unicode")]
    [InlineData("checksum")]
    [InlineData("size")]
    [InlineData("duplicate-format")]
    public async Task InvalidArchiveRollsBackTheWholeMigrationAsync(string corruption)
    {
        // Arrange: корректный архив обрабатывается перед повреждённым в порядке первичного ключа.
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        var connection = new NpgsqlConnectionStringBuilder(fixture.ConnectionString) { IncludeErrorDetail = true }.ConnectionString;
        await using var database = new BackupDbContext(new DbContextOptionsBuilder<BackupDbContext>().UseNpgsql(connection).Options);
        await database.GetService<IMigrator>().MigrateAsync(INITIAL_MIGRATION, cancellationToken);
        var original = CreateRecord(CreatePayload("com.fitnesstracker.archive", 4), "owner-a");
        var invalid = CreateRecord(CreatePayload("com.fitnesstracker.archive", 4), "owner-z");
        if (corruption == "json") invalid.Payload = "private-health-marker {unfinished"u8.ToArray();
        if (corruption == "utf8") invalid.Payload = [0xff, 0xfe, 0xfd];
        if (corruption == "unsupported-unicode")
            invalid.Payload = """{"format":"com.fitnesstracker.archive","note":"private-health-marker\u0000"}"""u8.ToArray();
        if (corruption == "duplicate-format")
            invalid.Payload = """{"format":"com.fitnesstracker.archive","format":"com.fitnesstracker.archive"}"""u8.ToArray();
        invalid.Size = invalid.Payload.Length;
        invalid.Sha256 = Convert.ToHexStringLower(SHA256.HashData(invalid.Payload));
        if (corruption == "checksum") invalid.Sha256 = new string('0', 64);
        if (corruption == "size") invalid.Size++;
        database.Backups.AddRange(original, invalid);
        await database.SaveChangesAsync(cancellationToken);

        // Act: новый history row и частично обработанный корректный архив должны откатиться вместе.
        var error = await Assert.ThrowsAsync<PostgresException>(() => database.GetService<IMigrator>().MigrateAsync(ARCHIVE_MIGRATION, cancellationToken));

        // Assert: ошибка безопасна даже с IncludeErrorDetail, прежние байты и метаданные не изменены.
        Assert.Equal("22000", error.SqlState);
        Assert.DoesNotContain("private-health-marker", error.ToString());
        Assert.DoesNotContain("com.fitnesstracker.archive", error.MessageText);
        Assert.Equal(new[] { INITIAL_MIGRATION }, await database.Database.GetAppliedMigrationsAsync(cancellationToken));
        foreach (var expected in new[] { original, invalid })
        {
            var actual = await database.Backups.AsNoTracking().SingleAsync(item => item.OwnerId == expected.OwnerId, cancellationToken);
            Assert.Equal(expected.Payload, actual.Payload);
            Assert.Equal(expected.Size, actual.Size);
            Assert.Equal(expected.Sha256, actual.Sha256);
        }
    }

    /// <summary>Архив на границе 30 MiB обновляется без увеличения вложенного JSON и превышения лимита клиента.</summary>
    [Fact]
    public async Task MigratesMaximumSizeArchiveAsync()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        var cancellationToken = deadline.Token;
        await using var fixture = await PostgresDatabase.CreateAsync(cancellationToken);
        await using var database = new BackupDbContext(new DbContextOptionsBuilder<BackupDbContext>()
            .UseNpgsql(fixture.ConnectionString).Options);
        await database.GetService<IMigrator>().MigrateAsync(INITIAL_MIGRATION, cancellationToken);
        const string prefix = """
            {"format":"com.fitnesstracker.archive","version":4,"exportedAt":1700000000,"workouts":[],"templates":[],"bodyWeights":[],"padding":"
            """;
        const string suffix = "\"}";
        var length = BackupStorage.MaximumBytes - Encoding.UTF8.GetByteCount(prefix + suffix);
        var payload = Encoding.UTF8.GetBytes(prefix + new string('x', length) + suffix);
        database.Backups.Add(CreateRecord(payload, "owner"));
        await database.SaveChangesAsync(cancellationToken);

        await database.GetService<IMigrator>().MigrateAsync(ARCHIVE_MIGRATION, cancellationToken);

        var migrated = await database.Backups.AsNoTracking().SingleAsync(cancellationToken);
        Assert.Equal(BackupStorage.MaximumBytes - 7, migrated.Size);
        Assert.Equal(migrated.Payload.Length, migrated.Size);
        Assert.Equal(Convert.ToHexStringLower(SHA256.HashData(migrated.Payload)), migrated.Sha256);
        using var document = JsonDocument.Parse(migrated.Payload);
        Assert.Equal(length, document.RootElement.GetProperty("padding").GetString()!.Length);
        Assert.Equal(4, BackupArchiveValidator.Validate(migrated.Payload));
    }

    /// <summary>Создаёт исходную копию с настоящим SHA-256 и детерминированной датой.</summary>
    private static BackupRecord CreateRecord(byte[] payload, string owner, int version = 4) => new()
    {
        Id = Guid.NewGuid(),
        OwnerId = owner,
        ArchiveVersion = version,
        CreatedAtMilliseconds = 1700000000123,
        Payload = payload,
        Size = payload.Length,
        Sha256 = Convert.ToHexStringLower(SHA256.HashData(payload))
    };

    /// <summary>Синтетические строки и числа вложенного архива должны сохраниться в исходном JSON-виде.</summary>
    private static byte[] CreatePayload(string format, int version) => Encoding.UTF8.GetBytes($$"""
        {
          "format": "{{format}}",
          "version": {{version}},
          "exportedAt": 1700000000.123456789,
          "workouts": [{"id":"00000000-0000-4000-8000-000000000001","notes":"Привет 👟\n\"format\": \"{{format}}\""}],
          "templates": [],
          "bodyWeights": [{"id":"00000000-0000-4000-8000-000000000002","weightKG":70.25}],
          "metadata": {"format":"{{format}}", "precise":1.000000000000000000000000000000001}
        }
        """);
}
