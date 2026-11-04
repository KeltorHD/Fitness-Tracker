using FitnessTracker.Authentication;
using FitnessTracker.Authentication.Migrations;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Migrations.Operations;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет миграцию PostgreSQL-модели без обращения к рабочей БД.</summary>
[Trait("Category", "Unit")]
public sealed class PasskeySchemaTests
{
    /// <summary>Добавление passkey не меняет существующие Identity-колонки; требуется только таблица и индекс.</summary>
    [Fact]
    public void MigrationAddsOnlyPasskeyStorageAndMatchesModel()
    {
        using var database = new DesignTimeDbContextFactory().CreateDbContext([]);
        var snapshot = database.GetService<IMigrationsAssembly>().ModelSnapshot;
        Assert.NotNull(snapshot);
        var previous = database.GetService<IModelRuntimeInitializer>().Initialize(snapshot.Model, designTime: true);
        var current = database.GetService<IDesignTimeModel>().Model;
        Assert.Empty(database.GetService<IMigrationsModelDiffer>().GetDifferences(
            previous.GetRelationalModel(), current.GetRelationalModel()));
        var operations = new AddPasskeys().UpOperations;
        Assert.NotNull(current.FindEntityType(typeof(IdentityUserPasskey<string>)));
        Assert.Null(current.FindEntityType(typeof(ApplicationUser))?.FindProperty("PhoneNumber")?.GetMaxLength());
        Assert.Null(current.FindEntityType(typeof(IdentityUserLogin<string>))?.FindProperty("ProviderKey")?.GetMaxLength());
        var table = Assert.Single(operations.OfType<CreateTableOperation>());
        Assert.Equal("AspNetUserPasskeys", table.Name);
        Assert.Equal(new[] { "CredentialId", "Data", "UserId" }, table.Columns.Select(column => column.Name).Order().ToArray());
        Assert.Equal("jsonb", Assert.Single(table.Columns, column => column.Name == "Data").ColumnType);
        Assert.Equal("AspNetUsers", Assert.Single(table.ForeignKeys).PrincipalTable);
        Assert.Single(operations.OfType<CreateIndexOperation>());
        Assert.Equal(2, operations.Count);
    }
}
