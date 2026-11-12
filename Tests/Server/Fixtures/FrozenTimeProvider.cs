namespace FitLife.Server.Tests;

/// <summary>Предоставляет постоянное время для проверки серверных метаданных без ожиданий.</summary>
internal sealed class FrozenTimeProvider(DateTimeOffset now) : TimeProvider
{
    /// <summary>Возвращает фиксированное UTC-время тестового сценария.</summary>
    public override DateTimeOffset GetUtcNow() => now;
}
