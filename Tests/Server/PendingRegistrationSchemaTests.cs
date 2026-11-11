using FitLife.Authentication.Migrations;
using Microsoft.EntityFrameworkCore.Migrations.Operations;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет additive миграцию индекса без изменения или пересоздания пользовательских данных.</summary>
[Trait("Category", "Unit")]
public sealed class PendingRegistrationSchemaTests
{
    /// <summary>Миграция добавляет только частичный индекс по уже существующему CreatedAt.</summary>
    [Fact]
    public void MigrationOnlyAddsPendingRegistrationIndex()
    {
        var operation = Assert.IsType<CreateIndexOperation>(Assert.Single(new AddPendingRegistrationExpiryIndex().UpOperations));
        Assert.Equal("AspNetUsers", operation.Table);
        Assert.Equal(new[] { "CreatedAt" }, operation.Columns);
        Assert.Equal("\"EmailConfirmationRequired\" AND NOT \"EmailConfirmed\"", operation.Filter);
        Assert.False(operation.IsUnique);
    }
}
