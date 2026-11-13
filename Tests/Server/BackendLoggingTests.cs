using System.Net;
using System.Text;
using FitLife.Backend;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.Routing.Patterns;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет видимость штатной диагностики Backend и отсутствие приватных данных в логах.</summary>
[Trait("Category", "HTTP")]
public sealed class BackendLoggingTests
{
    /// <summary>Реальная shipped конфигурация показывает запуск/готовность и не засоряет журнал health probes.</summary>
    [Fact]
    public async Task StartupAndReadyAreVisibleWithShippedFiltersAsync()
    {
        using var logs = new TestBackendLogs();
        using var factory = new BackendFactory(configureLogging: logs.Configure);
        using var client = factory.Client();
        using var response = await client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains(logs.Entries, item => item.EventId == 4100 && item.Level == LogLevel.Information && item.Fields["Mode"]?.ToString() == "http");
        Assert.Contains(logs.Entries, item => item.EventId == 4105 && item.Level == LogLevel.Information);
        Assert.DoesNotContain(logs.Entries, item => item.EventId == 4107);
    }

    /// <summary>HTTP log содержит шаблон/статус/длительность, но не UUID, query, headers, токен и недоверенный JSON.</summary>
    [Fact]
    public async Task RequestsLogTemplatesWithoutSecretsOrHealthPayloadAsync()
    {
        // Arrange: приватные маркеры присутствуют во всех недоверенных частях запросов.
        using var logs = new TestBackendLogs();
        using var factory = new BackendFactory(configureLogging: logs.Configure);
        var owner = Guid.NewGuid().ToString();
        using var client = factory.Client(owner);
        var id = Guid.NewGuid();
        client.DefaultRequestHeaders.Add("X-Service-Key", "private-header-marker");
        using var body = new StringContent("[{\"private-health-payload\":\"private-body-marker\"}]", Encoding.UTF8, "application/json");

        // Act: корректный GET, отсутствующая копия, malformed POST и неизвестный путь.
        using var valid = await client.GetAsync("/v1/training/changes?private=private-query-marker");
        using var missing = await client.GetAsync($"/v1/backups/{id}?private=private-query-marker");
        using var invalid = await client.PostAsync("/v1/training/changes?private=private-query-marker", body);
        using var unmatched = await client.GetAsync("/private-path-marker");

        // Assert: статус и шаблон полезны для диагностики, исходные данные не попали даже в structured values.
        Assert.Equal(HttpStatusCode.OK, valid.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, invalid.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, unmatched.StatusCode);
        var entries = logs.Entries.Where(item => item.EventId == 4107).ToArray();
        Assert.Equal(4, entries.Length);
        Assert.Contains(entries, item => item.Fields["Route"]?.ToString() == "/v1/backups/{id:guid}" && (int)item.Fields["StatusCode"]! == 404);
        Assert.Contains(entries, item => item.Fields["Route"]?.ToString() == "unmatched");
        Assert.All(entries, item => Assert.True((double)item.Fields["ElapsedMilliseconds"]! >= 0));
        var text = string.Join('\n', logs.Entries.Select(item => item.Message + string.Join('|', item.Fields.Values)));
        foreach (var secret in new[] { owner, id.ToString(), "private-header-marker", "private-body-marker", "private-query-marker", "private-path-marker", client.DefaultRequestHeaders.Authorization!.Parameter! })
            Assert.DoesNotContain(secret, text);
        Assert.All(logs.Entries, item => Assert.Null(item.Exception));
    }

    /// <summary>JWT-отказ также виден, хотя запрос не дошёл до обработчика и introspection.</summary>
    [Fact]
    public async Task UnauthorizedRequestIsLoggedBeforeEndpointExecutionAsync()
    {
        using var logs = new TestBackendLogs();
        using var factory = new BackendFactory(configureLogging: logs.Configure);
        using var client = factory.Client();
        using var response = await client.GetAsync("/v1/training/changes");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal(0, factory.Introspection.Calls);
        Assert.Contains(logs.Entries, item => item.EventId == 4107 && (int)item.Fields["StatusCode"]! == 401);
    }

    /// <summary>Неожиданный отказ и отмена различаются, но текст исключения не раскрывается.</summary>
    [Theory]
    [InlineData(false, 500, LogLevel.Error)]
    [InlineData(true, 499, LogLevel.Information)]
    public async Task FailureAndCancellationDoNotLogExceptionPayloadAsync(bool cancelled, int status, LogLevel level)
    {
        using var logs = new TestBackendLogs();
        using var loggers = logs.Factory();
        using var cancellation = new CancellationTokenSource();
        var context = new DefaultHttpContext();
        context.Request.Method = "POST";
        context.SetEndpoint(new RouteEndpoint(_ => Task.CompletedTask, RoutePatternFactory.Parse("/v1/training/changes"), 0, EndpointMetadataCollection.Empty, "test"));
        if (cancelled) { cancellation.Cancel(); context.RequestAborted = cancellation.Token; }
        var middleware = new BackendRequestLoggingMiddleware(_ => cancelled
            ? Task.FromException(new OperationCanceledException("private-exception-marker", cancellation.Token))
            : Task.FromException(new IOException("private-exception-marker")), loggers.CreateLogger<BackendRequestLoggingMiddleware>());
        if (cancelled) await Assert.ThrowsAnyAsync<OperationCanceledException>(() => middleware.InvokeAsync(context));
        else await Assert.ThrowsAsync<IOException>(() => middleware.InvokeAsync(context));
        var entry = Assert.Single(logs.Entries);
        Assert.Equal(status, entry.Fields["StatusCode"]);
        Assert.Equal(level, entry.Level);
        Assert.Null(entry.Exception);
        Assert.DoesNotContain("private-exception-marker", entry.Message);
    }

    /// <summary>Начало и агрегированный итог реального импорта видны без owner IDs и содержимого архива.</summary>
    [Fact]
    public async Task TrainingImportReportsCompletionAndIdempotentSkipWithoutPrivateDataAsync()
    {
        using var logs = new TestBackendLogs();
        using var loggers = logs.Factory();
        using var factory = new BackendFactory();
        using var client = factory.Client();
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<BackupDbContext>();
        var owner = Guid.NewGuid().ToString();
        var payload = TrainingFixture.Archive(TrainingFixture.Mutations());
        await scope.ServiceProvider.GetRequiredService<BackupStorage>().Put(owner, Guid.NewGuid(), payload, CancellationToken.None);
        var storage = new TrainingStorage(database, loggers.CreateLogger<TrainingStorage>());

        await storage.ImportLatestBackupsAsync(CancellationToken.None);
        await storage.ImportLatestBackupsAsync(CancellationToken.None);

        Assert.Equal(2, logs.Entries.Count(item => item.EventId == 4110));
        var completed = logs.Entries.Where(item => item.EventId == 4111).ToArray();
        Assert.Equal(2, completed.Length);
        Assert.Equal(1, completed[0].Fields["ImportedOwners"]);
        Assert.Equal(0, completed[0].Fields["SkippedOwners"]);
        Assert.Equal(0, completed[1].Fields["ImportedOwners"]);
        Assert.Equal(1, completed[1].Fields["SkippedOwners"]);
        Assert.DoesNotContain(owner, string.Join('\n', logs.Entries.Select(item => item.Message)));
    }
}
