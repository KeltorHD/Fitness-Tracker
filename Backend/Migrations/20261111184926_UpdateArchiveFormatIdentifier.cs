using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FitLife.Backend.Migrations
{
    /// <summary>Однократно обновляет идентификаторы сохранённых архивов и их контрольные метаданные.</summary>
    public partial class UpdateArchiveFormatIdentifier : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                DO $migration$
                DECLARE
                    backup record;
                    archive json;
                    migrated_payload bytea;
                    format_count bigint;
                BEGIN
                    LOCK TABLE "Backups" IN SHARE ROW EXCLUSIVE MODE;
                    FOR backup IN
                        SELECT "OwnerId", "Id", "Payload", "Size", "Sha256"
                        FROM "Backups"
                        ORDER BY "OwnerId", "Id"
                    LOOP
                        BEGIN
                            archive := convert_from(backup."Payload", 'UTF8')::json;
                            IF json_typeof(archive) IS DISTINCT FROM 'object'
                                OR coalesce(archive->>'format', '') NOT IN
                                    ('com.fitnesstracker.archive', 'com.fitsession.archive') THEN
                                CONTINUE;
                            END IF;

                            IF backup."Size" <> octet_length(backup."Payload")
                                OR backup."Sha256" <> encode(sha256(backup."Payload"), 'hex') THEN
                                RAISE data_exception;
                            END IF;

                            -- json сохраняет исходные строки, числа и вложенные JSON-значения.
                            -- Меняем только format верхнего уровня; jsonb не используется.
                            SELECT count(*) FILTER (WHERE key = 'format'),
                                convert_to('{' || string_agg(
                                    to_json(key)::text || ':' ||
                                    CASE WHEN key = 'format' THEN '"com.fitlife.archive"'
                                        ELSE value::text END,
                                    ',' ORDER BY ordinal) || '}', 'UTF8')
                            INTO format_count, migrated_payload
                            FROM json_each(archive) WITH ORDINALITY AS fields(key, value, ordinal);

                            IF format_count <> 1 OR octet_length(migrated_payload) > 31457280 THEN
                                RAISE data_exception;
                            END IF;

                            UPDATE "Backups"
                            SET "Payload" = migrated_payload,
                                "Size" = octet_length(migrated_payload),
                                "Sha256" = encode(sha256(migrated_payload), 'hex')
                            WHERE "OwnerId" = backup."OwnerId" AND "Id" = backup."Id";
                        EXCEPTION WHEN data_exception THEN
                            RAISE EXCEPTION USING ERRCODE = '22000',
                                MESSAGE = 'Stored archive identifier migration failed: invalid payload or integrity metadata.';
                        END;
                    END LOOP;
                END;
                $migration$;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Несколько прежних идентификаторов преобразуются в один; обратная замена неоднозначна.
            throw new NotSupportedException(
                "Archive identifiers cannot be downgraded. Restore a database backup to roll back this migration.");
        }
    }
}
