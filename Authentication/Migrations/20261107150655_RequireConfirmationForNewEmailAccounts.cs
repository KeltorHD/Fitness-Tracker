using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FitLife.Authentication.Migrations
{
    /// <inheritdoc />
    public partial class RequireConfirmationForNewEmailAccounts : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "EmailConfirmationRequired",
                table: "AspNetUsers",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "EmailConfirmationRequired",
                table: "AspNetUsers");
        }
    }
}
