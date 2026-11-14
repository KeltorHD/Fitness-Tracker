using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FitLife.Backend.Migrations
{
    /// <inheritdoc />
    public partial class AddExerciseLinks : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "TrainingExerciseLink",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    CatalogID = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TrainingExerciseLink", x => new { x.OwnerId, x.Id });
                    table.ForeignKey(
                        name: "FK_TrainingExerciseLink_TrainingRecords_OwnerId_Kind_Id",
                        columns: x => new { x.OwnerId, x.Kind, x.Id },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_TrainingExerciseLink_OwnerId_Kind_Id",
                table: "TrainingExerciseLink",
                columns: new[] { "OwnerId", "Kind", "Id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "TrainingExerciseLink");
        }
    }
}
