using System.Text.Json;
using System.Text.Json.Serialization;

namespace FitLife.Backend;

/// <summary>Версия дневной сводки HealthKit; используется для условного обновления после изменений исходных samples.</summary>
/// <param name="Metric">Шаги, активная энергия или расстояние.</param>
/// <param name="Start">Начало календарного дня.</param>
/// <param name="End">Конец календарного дня с учётом DST.</param>
/// <param name="TimeZoneId">Часовой пояс сводки.</param>
/// <param name="ExcludedIds">UUID явно удалённых samples, исключаемых из нативной статистики даже до доставки удаления через iCloud.</param>
/// <param name="Revision">Версия исходных данных на сервере.</param>
public sealed record HealthSyncBucketData(string Metric, DateTimeOffset Start, DateTimeOffset End, string TimeZoneId, long Revision, Guid[] ExcludedIds);

/// <summary>Передаёт фактическую объединённую HealthKit величину; null означает отсутствие доступного результата.</summary>
/// <param name="Bucket">Проверяемая версия сводки.</param>
/// <param name="Value">Значение в общих единицах либо null.</param>
public sealed record HealthSyncAggregate(HealthSyncBucketData Bucket, double? Value = null);

/// <summary>Описывает атомарную доставку изменений с постоянными HealthKit UUID и одноразовой последовательностью устройства.</summary>
/// <param name="DeviceId">Изолированный для аккаунта идентификатор установки.</param>
/// <param name="Sequence">Последовательный номер пакета.</param>
/// <param name="BatchId">Идемпотентный идентификатор запроса.</param>
/// <param name="TimeZoneId">Часовой пояс пересчёта новых сводок.</param>
/// <param name="ObservedAt">Время чтения на устройстве.</param>
/// <param name="Quantities">Нативные измерения, включая исходные samples для сводок.</param>
/// <param name="Sleep">Нативные samples сна, каждый с одной фактической фазой.</param>
/// <param name="DeletedIds">Только явные HKDeletedObject UUID.</param>
/// <param name="Aggregates">Условные обновления сводок.</param>
public sealed record HealthSyncBatch(Guid DeviceId, long Sequence, Guid BatchId, string TimeZoneId, DateTimeOffset ObservedAt,
    HealthQuantity[] Quantities, HealthSleepRecord[] Sleep, Guid[] DeletedIds, HealthSyncAggregate[] Aggregates);

/// <summary>Подтверждает только сохранённый пакет и возвращает сводки, требующие повторного чтения HealthKit.</summary>
/// <param name="BatchId">Подтверждённый UUID пакета.</param>
/// <param name="Sequence">Подтверждённый номер.</param>
/// <param name="Buckets">Сводки после инвалидирования или конфликта версий.</param>
public sealed record HealthSyncAcknowledgement(Guid BatchId, long Sequence, HealthSyncBucketData[] Buckets);

/// <summary>Единые строгие правила JSON для передачи health samples.</summary>
internal static class HealthSyncJson
{
    /// <summary>Отклоняет повторные/неизвестные поля, отсутствующие constructor arguments и небезопасные числа.</summary>
    internal static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false,
        NumberHandling = JsonNumberHandling.Strict,
        AllowDuplicateProperties = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        RespectNullableAnnotations = true,
        RespectRequiredConstructorParameters = true,
        MaxDepth = 24
    };
}
