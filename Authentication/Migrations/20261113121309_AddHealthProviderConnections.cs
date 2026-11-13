using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FitLife.Authentication.Migrations
{
    /// <inheritdoc />
    public partial class AddHealthProviderConnections : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "HealthConnections",
                columns: table => new
                {
                    UserId = table.Column<string>(type: "text", nullable: false),
                    Provider = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    ProtectedTokens = table.Column<string>(type: "text", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    AttemptId = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_HealthConnections", x => new { x.UserId, x.Provider });
                    table.ForeignKey(
                        name: "FK_HealthConnections_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "HealthConnections");
        }
    }
}
