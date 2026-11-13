namespace FitLife.Authentication;

/// <summary>Хранит привязку провайдера здоровья; токены зашифрованы собственным key ring Authentication.</summary>
public sealed class HealthConnection
{
    /// <summary>Владелец FitLife; удаление пользователя каскадно удаляет привязку.</summary>
    public string UserId { get; set; } = "";
    /// <summary>Стабильный идентификатор провайдера, независимый от способа входа в FitLife.</summary>
    public string Provider { get; set; } = "";
    /// <summary>Зашифрованные credentials, никогда не публикуемые в профиле или логах.</summary>
    public string ProtectedTokens { get; set; } = "";
    /// <summary>Последнее изменение подключения или ротация токенов.</summary>
    public DateTimeOffset UpdatedAt { get; set; }
    /// <summary>Одноразовая попытка привязки; отключение аннулирует незавершённый callback.</summary>
    public Guid? AttemptId { get; set; }
}

/// <summary>Публикует состояние подключения без идентификатора Xiaomi и секретов.</summary>
/// <param name="Provider">Идентификатор провайдера.</param>
/// <param name="Available">Настроен ли провайдер на сервере.</param>
/// <param name="Connected">Есть ли сохранённое разрешение пользователя.</param>
/// <param name="Metrics">Выданные категории данных.</param>
public sealed record HealthConnectionStatus(string Provider, bool Available, bool Connected, string[] Metrics);

/// <summary>Передаёт краткоживущий access token только доверенному Backend по внутреннему контракту.</summary>
/// <param name="AccessToken">Токен API Xiaomi, без refresh token.</param>
/// <param name="ClientId">Идентификатор зарегистрированного приложения.</param>
/// <param name="Metrics">Категории, на которые согласился пользователь.</param>
public sealed record HealthProviderGrant(string AccessToken, string ClientId, string[] Metrics)
{
    /// <summary>Исключает токен из случайного строкового логирования.</summary>
    public override string ToString() => nameof(HealthProviderGrant);
}

/// <summary>Содержит только зашифровываемое состояние OAuth; открытый JSON не хранится в БД.</summary>
internal sealed record HealthProviderTokens(string AccessToken, string RefreshToken, DateTimeOffset ExpiresAt, string ClientId, string[] Metrics)
{
    /// <summary>Исключает credentials из строкового представления.</summary>
    public override string ToString() => nameof(HealthProviderTokens);
}

/// <summary>Готовит страницу управления источниками, сохраняя проверенное продолжение входа iOS.</summary>
/// <param name="ReturnUrl">Локальное продолжение.</param>
/// <param name="Connections">Безопасные состояния источников.</param>
public sealed record HealthConnectionsPageData(string ReturnUrl, HealthConnectionStatus[] Connections);
