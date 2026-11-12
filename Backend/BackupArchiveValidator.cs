using System.Text.Json;

namespace FitLife.Backend;

/// <summary>
///     Проверяет транспортный формат архива до обращения к хранилищу; доменные правила остаются в Swift Core.
/// </summary>
internal static class BackupArchiveValidator
{
    /// <summary>
    ///     Возвращает версию допустимого архива или безопасную ошибку размера/формата без содержимого файла.
    /// </summary>
    internal static int Validate(ReadOnlyMemory<byte> payload)
    {
        if (payload.Length == 0 || payload.Length > BackupStorage.MaximumBytes)
            throw new BackupException(413, "invalid_size");
        try
        {
            using var document = JsonDocument.Parse(payload, new JsonDocumentOptions { MaxDepth = 64 });
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("format", out var format) ||
                format.ValueKind != JsonValueKind.String || format.GetString() != "com.fitlife.archive" ||
                !root.TryGetProperty("version", out var version) || version.ValueKind != JsonValueKind.Number ||
                !version.TryGetInt32(out var number) || number != 4 ||
                !root.TryGetProperty("exportedAt", out var date) || date.ValueKind != JsonValueKind.Number ||
                !date.TryGetDouble(out var timestamp) || !double.IsFinite(timestamp) ||
                !Array(root, "workouts", 10000) || !Array(root, "templates", 1000) ||
                !Array(root, "bodyWeights", 10000))
                throw new BackupException(400, "invalid_archive");
            return number;
        }
        catch (JsonException) { throw new BackupException(400, "invalid_archive"); }
    }

    /// <summary>Проверяет наличие массива и максимальное количество записей.</summary>
    private static bool Array(JsonElement root, string name, int limit) =>
        root.TryGetProperty(name, out var array) && array.ValueKind == JsonValueKind.Array && array.GetArrayLength() <= limit;
}
