namespace FitLife.Backend;

/// <summary>Описывает одну величину в единицах общего контракта, сохраняя источник и постоянный UUID.</summary>
/// <param name="Id">Стабильный идентификатор записи.</param>
/// <param name="Metric">Категория показателя.</param>
/// <param name="Start">Начало измерения или дневного интервала.</param>
/// <param name="End">Конец интервала.</param>
/// <param name="Value">Кг, проценты, уд/мин, ккал, метры либо число шагов.</param>
/// <param name="SourceId">Идентификатор источника.</param>
/// <param name="SourceName">Название источника.</param>
public sealed record HealthQuantity(Guid Id, string Metric, DateTimeOffset Start, DateTimeOffset End,
    double Value, string SourceId, string SourceName);

/// <summary>Передаёт только реально предоставленный интервал фазы сна.</summary>
/// <param name="Id">Стабильный идентификатор интервала.</param>
/// <param name="Start">Начало фазы.</param>
/// <param name="End">Конец фазы.</param>
/// <param name="Stage">Общая категория сна.</param>
public sealed record HealthSleepSegment(Guid Id, DateTimeOffset Start, DateTimeOffset End, string Stage);

/// <summary>Сохраняет отчётную длительность отдельно от необязательного подробного графика сна.</summary>
/// <param name="Id">Стабильный идентификатор отчёта.</param>
/// <param name="Start">Начало сна.</param>
/// <param name="End">Окончание сна.</param>
/// <param name="AsleepSeconds">Фактическая длительность из отчёта; null при отсутствии.</param>
/// <param name="SourceId">Источник отчёта.</param>
/// <param name="SourceName">Название источника.</param>
/// <param name="Segments">Доступные фазы, без искусственного заполнения пробелов.</param>
public sealed record HealthSleepRecord(Guid Id, DateTimeOffset Start, DateTimeOffset End, double? AsleepSeconds,
    string SourceId, string SourceName, IReadOnlyList<HealthSleepSegment> Segments);

/// <summary>Возвращает снимок одного провайдера; данные разных провайдеров не складываются.</summary>
/// <param name="Provider">Провайдер.</param>
/// <param name="Start">Начало запрошенного окна.</param>
/// <param name="End">Конец запрошенного окна.</param>
/// <param name="FetchedAt">Время получения.</param>
/// <param name="Metrics">Категории, доступные по фактически выданным разрешениям.</param>
/// <param name="Quantities">Нормализованные измерения.</param>
/// <param name="Sleep">Отчёты сна.</param>
public sealed record HealthDataSnapshot(string Provider, DateTimeOffset Start, DateTimeOffset End,
    DateTimeOffset FetchedAt, string[] Metrics, IReadOnlyList<HealthQuantity> Quantities, IReadOnlyList<HealthSleepRecord> Sleep);

/// <summary>Изолирует внешний облачный источник от публичного HTTP-контракта Backend.</summary>
public interface IHealthDataProvider
{
    /// <summary>Стабильное имя провайдера.</summary>
    string Id { get; }
    /// <summary>Читает только данные владельца, подтверждённого JWT и introspection.</summary>
    Task<HealthDataSnapshot> ReadAsync(string owner, DateTimeOffset start, DateTimeOffset end,
        string[] metrics, TimeZoneInfo timeZone, CancellationToken cancellationToken);
}

/// <summary>Передаёт безопасную причину отказа без внешнего payload, credentials или health data.</summary>
public sealed class HealthDataException(int status, string code) : Exception("Health provider request failed.")
{
    /// <summary>HTTP-категория отказа.</summary>
    public int Status { get; } = status;
    /// <summary>Стабильный код для повторного подключения или повтора операции.</summary>
    public string Code { get; } = code;
}

/// <summary>Внутренний ответ Authentication не предназначен для публикации клиенту.</summary>
internal sealed record HealthProviderGrant(string AccessToken, string ClientId, string[] Metrics)
{
    /// <summary>Не раскрывает токен при случайном логировании.</summary>
    public override string ToString() => nameof(HealthProviderGrant);
}
