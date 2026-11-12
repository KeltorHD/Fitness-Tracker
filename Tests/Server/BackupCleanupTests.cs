using System.Net;
using FitLife.Authentication;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет внутренний HTTP-контракт очистки без сети, БД и секретов окружения.</summary>
[Trait("Category", "Unit")]
public sealed class BackupCleanupTests
{
    /// <summary>Передаёт DELETE на внутренний URL с service key и без пользовательского bearer token.</summary>
    [Fact]
    public async Task SendsExactInternalCleanupContractAsync()
    {
        var owner = Guid.NewGuid().ToString();
        using var handler = new RecordingHandler((request, _) =>
        {
            Assert.Equal(HttpMethod.Delete, request.Method);
            Assert.Equal($"https://backend.test/internal/users/{owner}/backups", request.RequestUri?.AbsoluteUri);
            Assert.Equal(BackendFactory.ServiceKey, request.Headers.GetValues("X-Service-Key").Single());
            Assert.Null(request.Headers.Authorization);
            Assert.Null(request.Content);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NoContent));
        });
        using var client = new HttpClient(handler);

        await new BackupCleanup(client, Configuration()).Delete(owner, default);

        Assert.Equal(1, handler.Calls);
    }

    /// <summary>Ошибка Backend сохраняет неуспех операции, а не превращается в успешное удаление.</summary>
    [Theory]
    [InlineData(HttpStatusCode.Unauthorized)]
    [InlineData(HttpStatusCode.InternalServerError)]
    [InlineData(HttpStatusCode.ServiceUnavailable)]
    public async Task PropagatesRejectedCleanupStatusAsync(HttpStatusCode status)
    {
        using var handler = new RecordingHandler((_, _) => Task.FromResult(new HttpResponseMessage(status)));
        using var client = new HttpClient(handler);

        var error = await Assert.ThrowsAsync<HttpRequestException>(() =>
            new BackupCleanup(client, Configuration()).Delete(Guid.NewGuid().ToString(), default));

        Assert.Equal(status, error.StatusCode);
        Assert.Equal(1, handler.Calls);
    }

    /// <summary>Недостающая конфигурация блокирует отправку запроса до обращения к handler.</summary>
    [Theory]
    [InlineData(null, BackendFactory.ServiceKey)]
    [InlineData("https://backend.test/", null)]
    [InlineData("https://backend.test/", "short-key")]
    public async Task RejectsIncompleteConfigurationBeforeSendingAsync(string? address, string? key)
    {
        using var handler = new RecordingHandler((_, _) => throw new InvalidOperationException("Unexpected HTTP request."));
        using var client = new HttpClient(handler);

        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            new BackupCleanup(client, Configuration(address, key)).Delete(Guid.NewGuid().ToString(), default));

        Assert.Equal(0, handler.Calls);
    }

    /// <summary>Отмена после начала запроса передаётся в HTTP handler без ожидания реального тайм-аута.</summary>
    [Fact]
    public async Task PropagatesCallerCancellationToInFlightRequestAsync()
    {
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var completed = new TaskCompletionSource<HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var cancellation = new CancellationTokenSource();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var handler = new RecordingHandler(async (_, token) =>
        {
            using var registration = token.Register(() => completed.TrySetCanceled(token));
            started.SetResult();
            return await completed.Task;
        });
        using var client = new HttpClient(handler);
        var pending = new BackupCleanup(client, Configuration()).Delete(Guid.NewGuid().ToString(), cancellation.Token);

        await started.Task.WaitAsync(deadline.Token);
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending.WaitAsync(deadline.Token));
        Assert.True(completed.Task.IsCanceled);
        Assert.Equal(1, handler.Calls);
    }

    /// <summary>Формирует конфигурацию, независимую от пользовательских env keys.</summary>
    private static IConfiguration Configuration(string? address = "https://backend.test/", string? key = BackendFactory.ServiceKey) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Backend:InternalUrl"] = address,
                ["Backend:ServiceKey"] = key
            })
            .Build();

    /// <summary>Перехватывает исходящие запросы и не создаёт сетевых соединений.</summary>
    private sealed class RecordingHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        /// <summary>Количество фактически отправленных запросов.</summary>
        internal int Calls { get; private set; }

        /// <summary>Передаёт запрос и token в функцию конкретного сценария.</summary>
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            return send(request, cancellationToken);
        }
    }
}
