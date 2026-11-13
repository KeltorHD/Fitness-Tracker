using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FitLife.Backend.Migrations
{
    /// <inheritdoc />
    public partial class CreateTrainingModel : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "TrainingOwners",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Revision = table.Column<long>(type: "bigint", nullable: false),
                    ImportedBackupId = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TrainingOwners", x => x.OwnerId);
                });

            migrationBuilder.CreateTable(
                name: "TrainingRecords",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Revision = table.Column<long>(type: "bigint", nullable: false),
                    Deleted = table.Column<bool>(type: "boolean", nullable: false),
                    Hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TrainingRecords", x => new { x.OwnerId, x.Kind, x.Id });
                    table.ForeignKey(
                        name: "FK_TrainingRecords_TrainingOwners_OwnerId",
                        column: x => x.OwnerId,
                        principalTable: "TrainingOwners",
                        principalColumn: "OwnerId",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "BodyWeights",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    MeasuredAt = table.Column<double>(type: "double precision", nullable: false),
                    WeightKG = table.Column<double>(type: "double precision", nullable: false),
                    WorkoutID = table.Column<Guid>(type: "uuid", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_BodyWeights", x => new { x.OwnerId, x.Id });
                    table.ForeignKey(
                        name: "FK_BodyWeights_TrainingRecords_OwnerId_Kind_Id",
                        columns: x => new { x.OwnerId, x.Kind, x.Id },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "Exercises",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    AggregateId = table.Column<Guid>(type: "uuid", nullable: false),
                    VariationIndex = table.Column<int>(type: "integer", nullable: false),
                    Position = table.Column<int>(type: "integer", nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ExerciseId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    Muscle = table.Column<string>(type: "text", nullable: false),
                    Instructions = table.Column<string>(type: "text", nullable: false),
                    SupersetID = table.Column<Guid>(type: "uuid", nullable: true),
                    SetCount = table.Column<int>(type: "integer", nullable: true),
                    Repetitions = table.Column<int>(type: "integer", nullable: true),
                    WeightKG = table.Column<double>(type: "double precision", nullable: true),
                    LoadMultiplier = table.Column<int>(type: "integer", nullable: true),
                    HasPlannedSets = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Exercises", x => new { x.OwnerId, x.Kind, x.AggregateId, x.VariationIndex, x.Position });
                    table.ForeignKey(
                        name: "FK_Exercises_TrainingRecords_OwnerId_Kind_AggregateId",
                        columns: x => new { x.OwnerId, x.Kind, x.AggregateId },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "Templates",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    RestSeconds = table.Column<int>(type: "integer", nullable: false),
                    BaseVariationName = table.Column<string>(type: "text", nullable: true),
                    MuscleGroupsJson = table.Column<string>(type: "text", nullable: false),
                    MusclesJson = table.Column<string>(type: "text", nullable: false),
                    MuscleRegionsJson = table.Column<string>(type: "text", nullable: false),
                    PreferredWeekdaysJson = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Templates", x => new { x.OwnerId, x.Id });
                    table.ForeignKey(
                        name: "FK_Templates_TrainingRecords_OwnerId_Kind_Id",
                        columns: x => new { x.OwnerId, x.Kind, x.Id },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "Workouts",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false),
                    StartedAt = table.Column<double>(type: "double precision", nullable: false),
                    EndedAt = table.Column<double>(type: "double precision", nullable: true),
                    Status = table.Column<string>(type: "text", nullable: false),
                    RestSeconds = table.Column<int>(type: "integer", nullable: false),
                    RestEndsAt = table.Column<double>(type: "double precision", nullable: true),
                    PausedAt = table.Column<double>(type: "double precision", nullable: true),
                    PausedSeconds = table.Column<double>(type: "double precision", nullable: false),
                    Notes = table.Column<string>(type: "text", nullable: false),
                    BodyWeightKG = table.Column<double>(type: "double precision", nullable: true),
                    DurationIsKnown = table.Column<bool>(type: "boolean", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Workouts", x => new { x.OwnerId, x.Id });
                    table.ForeignKey(
                        name: "FK_Workouts_TrainingRecords_OwnerId_Kind_Id",
                        columns: x => new { x.OwnerId, x.Kind, x.Id },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "TrainingSet",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    AggregateId = table.Column<Guid>(type: "uuid", nullable: false),
                    VariationIndex = table.Column<int>(type: "integer", nullable: false),
                    ExercisePosition = table.Column<int>(type: "integer", nullable: false),
                    Position = table.Column<int>(type: "integer", nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Repetitions = table.Column<int>(type: "integer", nullable: false),
                    WeightKG = table.Column<double>(type: "double precision", nullable: false),
                    IsWarmup = table.Column<bool>(type: "boolean", nullable: false),
                    CompletedAt = table.Column<double>(type: "double precision", nullable: true),
                    LoadMultiplier = table.Column<int>(type: "integer", nullable: true),
                    Note = table.Column<string>(type: "text", nullable: true),
                    HasDropStages = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TrainingSet", x => new { x.OwnerId, x.Kind, x.AggregateId, x.VariationIndex, x.ExercisePosition, x.Position });
                    table.ForeignKey(
                        name: "FK_TrainingSet_Exercises_OwnerId_Kind_AggregateId_VariationInd~",
                        columns: x => new { x.OwnerId, x.Kind, x.AggregateId, x.VariationIndex, x.ExercisePosition },
                        principalTable: "Exercises",
                        principalColumns: new[] { "OwnerId", "Kind", "AggregateId", "VariationIndex", "Position" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "TrainingVariation",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    TemplateId = table.Column<Guid>(type: "uuid", nullable: false),
                    Position = table.Column<int>(type: "integer", nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TrainingVariation", x => new { x.OwnerId, x.TemplateId, x.Position });
                    table.ForeignKey(
                        name: "FK_TrainingVariation_Templates_OwnerId_TemplateId",
                        columns: x => new { x.OwnerId, x.TemplateId },
                        principalTable: "Templates",
                        principalColumns: new[] { "OwnerId", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "HeartRateRecordings",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    SchemaVersion = table.Column<int>(type: "integer", nullable: false),
                    Mode = table.Column<string>(type: "text", nullable: false),
                    Origin = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_HeartRateRecordings", x => new { x.OwnerId, x.Id });
                    table.ForeignKey(
                        name: "FK_HeartRateRecordings_TrainingRecords_OwnerId_Kind_Id",
                        columns: x => new { x.OwnerId, x.Kind, x.Id },
                        principalTable: "TrainingRecords",
                        principalColumns: new[] { "OwnerId", "Kind", "Id" },
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_HeartRateRecordings_Workouts_OwnerId_Id",
                        columns: x => new { x.OwnerId, x.Id },
                        principalTable: "Workouts",
                        principalColumns: new[] { "OwnerId", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "TrainingPause",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    WorkoutId = table.Column<Guid>(type: "uuid", nullable: false),
                    Position = table.Column<int>(type: "integer", nullable: false),
                    StartedAt = table.Column<double>(type: "double precision", nullable: false),
                    EndedAt = table.Column<double>(type: "double precision", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TrainingPause", x => new { x.OwnerId, x.WorkoutId, x.Position });
                    table.ForeignKey(
                        name: "FK_TrainingPause_Workouts_OwnerId_WorkoutId",
                        columns: x => new { x.OwnerId, x.WorkoutId },
                        principalTable: "Workouts",
                        principalColumns: new[] { "OwnerId", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "TrainingDropStage",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    Kind = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    AggregateId = table.Column<Guid>(type: "uuid", nullable: false),
                    VariationIndex = table.Column<int>(type: "integer", nullable: false),
                    ExercisePosition = table.Column<int>(type: "integer", nullable: false),
                    SetPosition = table.Column<int>(type: "integer", nullable: false),
                    Position = table.Column<int>(type: "integer", nullable: false),
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Repetitions = table.Column<int>(type: "integer", nullable: false),
                    WeightKG = table.Column<double>(type: "double precision", nullable: false),
                    CompletedAt = table.Column<double>(type: "double precision", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TrainingDropStage", x => new { x.OwnerId, x.Kind, x.AggregateId, x.VariationIndex, x.ExercisePosition, x.SetPosition, x.Position });
                    table.ForeignKey(
                        name: "FK_TrainingDropStage_TrainingSet_OwnerId_Kind_AggregateId_Vari~",
                        columns: x => new { x.OwnerId, x.Kind, x.AggregateId, x.VariationIndex, x.ExercisePosition, x.SetPosition },
                        principalTable: "TrainingSet",
                        principalColumns: new[] { "OwnerId", "Kind", "AggregateId", "VariationIndex", "ExercisePosition", "Position" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "TrainingHeartRateReading",
                columns: table => new
                {
                    OwnerId = table.Column<string>(type: "character varying(36)", maxLength: 36, nullable: false),
                    WorkoutId = table.Column<Guid>(type: "uuid", nullable: false),
                    Position = table.Column<int>(type: "integer", nullable: false),
                    Date = table.Column<double>(type: "double precision", nullable: false),
                    BeatsPerMinute = table.Column<double>(type: "double precision", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TrainingHeartRateReading", x => new { x.OwnerId, x.WorkoutId, x.Position });
                    table.ForeignKey(
                        name: "FK_TrainingHeartRateReading_HeartRateRecordings_OwnerId_Workou~",
                        columns: x => new { x.OwnerId, x.WorkoutId },
                        principalTable: "HeartRateRecordings",
                        principalColumns: new[] { "OwnerId", "Id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_BodyWeights_OwnerId_Kind_Id",
                table: "BodyWeights",
                columns: new[] { "OwnerId", "Kind", "Id" });

            migrationBuilder.CreateIndex(
                name: "IX_Exercises_OwnerId_ExerciseId",
                table: "Exercises",
                columns: new[] { "OwnerId", "ExerciseId" });

            migrationBuilder.CreateIndex(
                name: "IX_HeartRateRecordings_OwnerId_Kind_Id",
                table: "HeartRateRecordings",
                columns: new[] { "OwnerId", "Kind", "Id" });

            migrationBuilder.CreateIndex(
                name: "IX_Templates_OwnerId_Kind_Id",
                table: "Templates",
                columns: new[] { "OwnerId", "Kind", "Id" });

            migrationBuilder.CreateIndex(
                name: "IX_TrainingRecords_OwnerId_Revision",
                table: "TrainingRecords",
                columns: new[] { "OwnerId", "Revision" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Workouts_OwnerId_Kind_Id",
                table: "Workouts",
                columns: new[] { "OwnerId", "Kind", "Id" });

            migrationBuilder.CreateIndex(
                name: "IX_Workouts_OwnerId_StartedAt",
                table: "Workouts",
                columns: new[] { "OwnerId", "StartedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "BodyWeights");

            migrationBuilder.DropTable(
                name: "TrainingDropStage");

            migrationBuilder.DropTable(
                name: "TrainingHeartRateReading");

            migrationBuilder.DropTable(
                name: "TrainingPause");

            migrationBuilder.DropTable(
                name: "TrainingVariation");

            migrationBuilder.DropTable(
                name: "TrainingSet");

            migrationBuilder.DropTable(
                name: "HeartRateRecordings");

            migrationBuilder.DropTable(
                name: "Templates");

            migrationBuilder.DropTable(
                name: "Exercises");

            migrationBuilder.DropTable(
                name: "Workouts");

            migrationBuilder.DropTable(
                name: "TrainingRecords");

            migrationBuilder.DropTable(
                name: "TrainingOwners");
        }
    }
}
