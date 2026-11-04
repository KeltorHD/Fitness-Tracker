using MapsterMapper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace FitnessTracker.Authentication.Controllers;

/// <summary>Преобразует ожидаемые отказы сервисов на единой HTTP-границе через Mapster.</summary>
public sealed class AuthenticationExceptionFilter(IMapper mapper) : IExceptionFilter
{
    /// <summary>Оставляет инфраструктурные исключения и cancellation штатному ASP.NET Core pipeline.</summary>
    public void OnException(ExceptionContext context)
    {
        if (context.Exception is not AuthenticationOperationException failure) return;
        context.Result = mapper.Map<AuthenticationOperationException, IActionResult>(failure);
        context.ExceptionHandled = true;
    }
}
