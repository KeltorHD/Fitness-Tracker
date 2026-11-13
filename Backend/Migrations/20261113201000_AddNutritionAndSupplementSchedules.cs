using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FitLife.Backend.Migrations
{
    /// <inheritdoc />
    public partial class AddNutritionAndSupplementSchedules : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "NutritionDose",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    SchemaVersion = table.Column<int>(type: "integer", nullable: false),
                    Date = table.Column<double>(type: "double precision", nullable: false),
                    SupplementKind = table.Column<string>(type: "text", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Amount = table.Column<double>(type: "double precision", nullable: false),
                    Unit = table.Column<string>(type: "text", nullable: false),
                    IncludesNutrition = table.Column<bool>(type: "boolean", nullable: false),
                    Note = table.Column<string>(type: "text", nullable: false),
                    PlanID = table.Column<Guid>(type: "uuid", nullable: true),
                    ScheduledFor = table.Column<double>(type: "double precision", nullable: true),
                    Calories = table.Column<double>(type: "double precision", nullable: true),
                    Protein = table.Column<double>(type: "double precision", nullable: true),
                    Fat = table.Column<double>(type: "double precision", nullable: true),
                    Carbohydrates = table.Column<double>(type: "double precision", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NutritionDose", x => new { x.OwnerId, x.Kind, x.Id });
                    table.ForeignKey(
                        name: "FK_NutritionDose_TrainingRecords_OwnerId_Kind_Id",
                        columns: x => new { x.OwnerId, x.Kind, x.Id },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "NutritionFood",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Date = table.Column<double>(type: "double precision", nullable: false),
                    Meal = table.Column<string>(type: "text", nullable: false),
                    Title = table.Column<string>(type: "text", nullable: false),
                    Note = table.Column<string>(type: "text", nullable: false),
                    Photo = table.Column<byte[]>(type: "bytea", nullable: true),
                    IsSavedMeal = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NutritionFood", x => new { x.OwnerId, x.Kind, x.Id });
                    table.ForeignKey(
                        name: "FK_NutritionFood_TrainingRecords_OwnerId_Kind_Id",
                        columns: x => new { x.OwnerId, x.Kind, x.Id },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "NutritionPlan",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Recurrence = table.Column<string>(type: "text", nullable: false),
                    IntervalDays = table.Column<int>(type: "integer", nullable: false),
                    StartDate = table.Column<double>(type: "double precision", nullable: false),
                    EndDate = table.Column<double>(type: "double precision", nullable: true),
                    TimeZoneID = table.Column<string>(type: "text", nullable: false),
                    Enabled = table.Column<bool>(type: "boolean", nullable: false),
                    RemindersEnabled = table.Column<bool>(type: "boolean", nullable: false),
                    WeekdaysJson = table.Column<string>(type: "text", nullable: false),
                    TimesJson = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NutritionPlan", x => new { x.OwnerId, x.Kind, x.Id });
                    table.ForeignKey(
                        name: "FK_NutritionPlan_TrainingRecords_OwnerId_Kind_Id",
                        columns: x => new { x.OwnerId, x.Kind, x.Id },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "NutritionProduct",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    AggregateId = table.Column<Guid>(type: "uuid", nullable: false),
                    Position = table.Column<int>(type: "integer", nullable: false),
                    PortionId = table.Column<Guid>(type: "uuid", nullable: true),
                    Amount = table.Column<double>(type: "double precision", nullable: true),
                    ProductId = table.Column<string>(type: "text", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Brand = table.Column<string>(type: "text", nullable: false),
                    Unit = table.Column<string>(type: "text", nullable: false),
                    ImageURL = table.Column<string>(type: "text", nullable: true),
                    SourceURL = table.Column<string>(type: "text", nullable: true),
                    Barcode = table.Column<string>(type: "text", nullable: true),
                    Calories = table.Column<double>(type: "double precision", nullable: false),
                    Protein = table.Column<double>(type: "double precision", nullable: false),
                    Fat = table.Column<double>(type: "double precision", nullable: false),
                    Carbohydrates = table.Column<double>(type: "double precision", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NutritionProduct", x => new { x.OwnerId, x.Kind, x.AggregateId, x.Position });
                    table.ForeignKey(
                        name: "FK_NutritionProduct_TrainingRecords_OwnerId_Kind_AggregateId",
                        columns: x => new { x.OwnerId, x.Kind, x.AggregateId },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "NutritionProfileRow",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Calories = table.Column<double>(type: "double precision", nullable: true),
                    Protein = table.Column<double>(type: "double precision", nullable: true),
                    Fat = table.Column<double>(type: "double precision", nullable: true),
                    Carbohydrates = table.Column<double>(type: "double precision", nullable: true),
                    WaterMilliliters = table.Column<double>(type: "double precision", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NutritionProfileRow", x => new { x.OwnerId, x.Kind, x.Id });
                    table.ForeignKey(
                        name: "FK_NutritionProfileRow_TrainingRecords_OwnerId_Kind_Id",
                        columns: x => new { x.OwnerId, x.Kind, x.Id },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "NutritionWater",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Date = table.Column<double>(type: "double precision", nullable: false),
                    Milliliters = table.Column<double>(type: "double precision", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_NutritionWater", x => new { x.OwnerId, x.Kind, x.Id });
                    table.ForeignKey(
                        name: "FK_NutritionWater_TrainingRecords_OwnerId_Kind_Id",
                        columns: x => new { x.OwnerId, x.Kind, x.Id },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_NutritionDose_OwnerId_Date",
                table: "NutritionDose",
                columns: new[] { "OwnerId", "Date" });

            migrationBuilder.CreateIndex(
                name: "IX_NutritionFood_OwnerId_Date",
                table: "NutritionFood",
                columns: new[] { "OwnerId", "Date" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "NutritionDose");

            migrationBuilder.DropTable(
                name: "NutritionFood");

            migrationBuilder.DropTable(
                name: "NutritionPlan");

            migrationBuilder.DropTable(
                name: "NutritionProduct");

            migrationBuilder.DropTable(
                name: "NutritionProfileRow");

            migrationBuilder.DropTable(
                name: "NutritionWater");
        }
    }
}
