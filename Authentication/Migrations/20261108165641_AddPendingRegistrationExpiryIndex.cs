using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FitLife.Authentication.Migrations
{
    /// <inheritdoc />
    public partial class AddPendingRegistrationExpiryIndex : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "IX_AspNetUsers_PendingConfirmationCreatedAt",
                table: "AspNetUsers",
                column: "CreatedAt",
                filter: "\"EmailConfirmationRequired\" AND NOT \"EmailConfirmed\"");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_AspNetUsers_PendingConfirmationCreatedAt",
                table: "AspNetUsers");
        }
    }
}
