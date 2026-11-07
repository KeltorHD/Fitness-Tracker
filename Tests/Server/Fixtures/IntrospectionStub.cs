using System.Net;
using System.Net.Http.Json;

namespace FitnessTracker.Server.Tests;

/// <summary>Подменяет только HTTP-ответ Auth; проверка подписи JWT и остальной Backend остаются настоящими.</summary>
internal sealed class IntrospectionStub : HttpMessageHandler
{
    private int _calls;
    /// <summary>Количество реальных обращений Backend к подменённому Auth.</summary>
    internal int Calls => Volatile.Read(ref _calls);
    /// <summary>Меняет статус между запросами для проверки отсутствия положительного кеша.</summary>
    internal bool Active { get; set; } = true;
    /// <summary>Позволяет симулировать транспортные ошибки, неверные ответы и отмену без сети.</summary>
    internal Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>>? Respond { get; set; }

    /// <summary>Возвращает новый ответ для каждого запроса и учитывает переданный cancellation token.</summary>
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Interlocked.Increment(ref _calls);
        return Respond is not null ? Respond(request, cancellationToken) : Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = JsonContent.Create(new { active = Active })
        });
    }
}
