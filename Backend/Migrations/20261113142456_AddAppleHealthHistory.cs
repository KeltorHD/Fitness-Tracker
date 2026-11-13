using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FitLife.Backend.Migrations
{
    /// <inheritdoc />
    public partial class AddAppleHealthHistory : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "HealthSyncOwner",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Revision = table.Column<long>(type: "bigint", nullable: false),
                    UpdatedAtMilliseconds = table.Column<long>(type: "bigint", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_HealthSyncOwner", x => x.OwnerId);
                });

            migrationBuilder.CreateTable(
                name: "HealthSyncBucket",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Metric = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    TimeZoneId = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    StartMilliseconds = table.Column<long>(type: "bigint", nullable: false),
                    EndMilliseconds = table.Column<long>(type: "bigint", nullable: false),
                    Revision = table.Column<long>(type: "bigint", nullable: false),
                    Dirty = table.Column<bool>(type: "boolean", nullable: false),
                    Value = table.Column<double>(type: "double precision", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_HealthSyncBucket", x => new { x.OwnerId, x.Metric, x.TimeZoneId, x.StartMilliseconds });
                    table.ForeignKey(
                        name: "FK_HealthSyncBucket_HealthSyncOwner_OwnerId",
                        column: x => x.OwnerId,
                        principalTable: "HealthSyncOwner",
                        principalColumn: "OwnerId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "HealthSyncDevice",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Sequence = table.Column<long>(type: "bigint", nullable: false),
                    BatchId = table.Column<Guid>(type: "uuid", nullable: false),
                    Hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    Acknowledgement = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_HealthSyncDevice", x => new { x.OwnerId, x.Id });
                    table.ForeignKey(
                        name: "FK_HealthSyncDevice_HealthSyncOwner_OwnerId",
                        column: x => x.OwnerId,
                        principalTable: "HealthSyncOwner",
                        principalColumn: "OwnerId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "HealthSyncSample",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Metric = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    StartMilliseconds = table.Column<long>(type: "bigint", nullable: false),
                    EndMilliseconds = table.Column<long>(type: "bigint", nullable: false),
                    Value = table.Column<double>(type: "double precision", nullable: true),
                    SourceId = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: false),
                    SourceName = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Stage = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    Deleted = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_HealthSyncSample", x => new { x.OwnerId, x.Id });
                    table.ForeignKey(
                        name: "FK_HealthSyncSample_HealthSyncOwner_OwnerId",
                        column: x => x.OwnerId,
                        principalTable: "HealthSyncOwner",
                        principalColumn: "OwnerId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_HealthSyncSample_OwnerId_Metric_StartMilliseconds",
                table: "HealthSyncSample",
                columns: new[] { "OwnerId", "Metric", "StartMilliseconds" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "HealthSyncBucket");

            migrationBuilder.DropTable(
                name: "HealthSyncDevice");

            migrationBuilder.DropTable(
                name: "HealthSyncSample");

            migrationBuilder.DropTable(
                name: "HealthSyncOwner");
        }
    }
}
