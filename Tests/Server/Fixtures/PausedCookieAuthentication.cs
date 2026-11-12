using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;

namespace FitLife.Server.Tests;

/// <summary>Детерминированно приостанавливает первый запрос после проверки Identity cookie.</summary>
internal sealed class PausedCookieAuthentication(CancellationToken cancellationToken) : IClaimsTransformation
{
    private readonly TaskCompletionSource _validated = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly TaskCompletionSource _resumed = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int _paused;

    /// <summary>Сигнал о проверке cookie до запуска контроллера и сохранения authorization.</summary>
    internal Task CookieValidated => _validated.Task;

    /// <summary>Разрешает продолжение запроса; повторный вызов безопасен для finally.</summary>
    internal void Resume() => _resumed.TrySetResult();

    /// <summary>Сохраняет настоящий principal, задерживая ровно один запрос без фиксированных пауз.</summary>
    public async Task<ClaimsPrincipal> TransformAsync(ClaimsPrincipal principal)
    {
        if (principal.Identity?.IsAuthenticated == true && Interlocked.Exchange(ref _paused, 1) == 0)
        {
            _validated.TrySetResult();
            await _resumed.Task.WaitAsync(cancellationToken);
        }
        return principal;
    }
}
