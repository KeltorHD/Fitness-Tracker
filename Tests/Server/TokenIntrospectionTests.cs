using System.Net;
using System.Net.Http.Json;
using FitnessTracker.Backend;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет RFC 7662 HTTP-клиент без сети, реальных credentials и ожидания тайм-аутов.</summary>
[Trait("Category", "Unit")]
public sealed class TokenIntrospectionTests
{
    private const string TOKEN = "synthetic-token+/?&=private";

    /// <summary>Отправляет POST form без секретов в URL и возвращает только настоящий boolean active.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task SendsServerCredentialsAndTokenOnlyInFormAsync(bool active)
    {
        using var handler = new IntrospectionStub
        {
            Respond = async (request, cancellationToken) =>
            {
                Assert.Equal(HttpMethod.Post, request.Method);
                Assert.Equal("https://auth.test/connect/introspect", request.RequestUri?.AbsoluteUri);
                Assert.Equal("application/x-www-form-urlencoded", request.Content?.Headers.ContentType?.MediaType);
                var form = QueryHelpers.ParseQuery(await request.Content!.ReadAsStringAsync(cancellationToken));
                Assert.Equal(IntrospectionOptions.ClientId, form["client_id"].ToString());
                Assert.Equal(AuthFactory.IntrospectionSecret, form["client_secret"].ToString());
                Assert.Equal(TOKEN, form["token"].ToString());
                Assert.Equal("access_token", form["token_type_hint"].ToString());
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new { active }) };
            }
        };
        using var client = new HttpClient(handler);

        Assert.Equal(active, await Create(client).IsActiveAsync(TOKEN, default));
        Assert.Equal(1, handler.Calls);
    }

    /// <summary>Ошибки сервиса/credentials/лимита и redirect не превращаются в inactive или автоматический повтор.</summary>
    [Theory]
    [InlineData(HttpStatusCode.Unauthorized)]
    [InlineData(HttpStatusCode.Forbidden)]
    [InlineData(HttpStatusCode.TooManyRequests)]
    [InlineData(HttpStatusCode.InternalServerError)]
    [InlineData(HttpStatusCode.ServiceUnavailable)]
    [InlineData(HttpStatusCode.Redirect)]
    public async Task RejectsServiceErrorsWithoutLeakingResponseAsync(HttpStatusCode status)
    {
        using var handler = new IntrospectionStub
        {
            Respond = (_, _) => Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent("private-response-marker") })
        };
        using var client = new HttpClient(handler);

        var error = await Assert.ThrowsAsync<AuthenticationUnavailableException>(() => Create(client).IsActiveAsync(TOKEN, default));

        Assert.DoesNotContain("private-response-marker", error.ToString());
        Assert.DoesNotContain(TOKEN, error.ToString());
        Assert.DoesNotContain(AuthFactory.IntrospectionSecret, error.ToString());
        Assert.Equal(1, handler.Calls);
    }

    /// <summary>Повреждённый или неоднозначный ответ Auth закрывает доступ, а не подтверждает сессию.</summary>
    [Theory]
    [InlineData("not-json")]
    [InlineData("null")]
    [InlineData("[]")]
    [InlineData("{}")]
    [InlineData("{\"active\":\"true\"}")]
    [InlineData("{\"active\":1}")]
    [InlineData("{\"active\":true,\"error\":\"invalid_client\"}")]
    [InlineData("{\"active\":false,\"active\":true}")]
    public async Task RejectsMalformedProtocolResponsesAsync(string response)
    {
        using var handler = new IntrospectionStub
        {
            Respond = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            { Content = new StringContent(response, System.Text.Encoding.UTF8, "application/json") })
        };
        using var client = new HttpClient(handler);

        await Assert.ThrowsAsync<AuthenticationUnavailableException>(() => Create(client).IsActiveAsync(TOKEN, default));
        Assert.Equal(1, handler.Calls);
    }

    /// <summary>Ограничивает объём ответа Auth независимо от Content-Length.</summary>
    [Fact]
    public async Task RejectsOversizedResponseAsync()
    {
        using var handler = new IntrospectionStub
        {
            Respond = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("{\"active\":true,\"extra\":\"" + new string('x', 20 * 1024) + "\"}",
                    System.Text.Encoding.UTF8, "application/json")
            })
        };
        using var client = new HttpClient(handler);

        await Assert.ThrowsAsync<AuthenticationUnavailableException>(() => Create(client).IsActiveAsync(TOKEN, default));
    }

    /// <summary>Отличает сетевой отказ и внутренний тайм-аут от отозванного токена.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task RejectsTransportFailureAndTimeoutAsync(bool timeout)
    {
        using var handler = new IntrospectionStub
        {
            Respond = (_, _) => throw (timeout ? new OperationCanceledException() : new HttpRequestException("private-transport-marker"))
        };
        using var client = new HttpClient(handler);

        var error = await Assert.ThrowsAsync<AuthenticationUnavailableException>(() => Create(client).IsActiveAsync(TOKEN, default));
        Assert.DoesNotContain("private-transport-marker", error.ToString());
    }

    /// <summary>Страница прокси или ошибочно настроенного сервиса не подтверждает active даже при похожем body.</summary>
    [Fact]
    public async Task RejectsNonJsonContentTypeAsync()
    {
        using var handler = new IntrospectionStub
        {
            Respond = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            { Content = new StringContent("{\"active\":true}") })
        };
        using var client = new HttpClient(handler);

        await Assert.ThrowsAsync<AuthenticationUnavailableException>(() => Create(client).IsActiveAsync(TOKEN, default));
    }

    /// <summary>Неверный charset в ответе Auth не становится успешным ответом или внутренней ошибкой API.</summary>
    [Fact]
    public async Task RejectsUnsupportedResponseEncodingAsync()
    {
        using var handler = new IntrospectionStub
        {
            Respond = (_, _) =>
            {
                var content = new StringContent("{\"active\":true}");
                content.Headers.ContentType = System.Net.Http.Headers.MediaTypeHeaderValue.Parse("application/json; charset=unknown-encoding");
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = content });
            }
        };
        using var client = new HttpClient(handler);

        await Assert.ThrowsAsync<AuthenticationUnavailableException>(() => Create(client).IsActiveAsync(TOKEN, default));
    }

    /// <summary>Передаёт отмену вызывающего кода в незавершённый запрос, не заменяя её ошибкой Auth.</summary>
    [Fact]
    public async Task PropagatesCancellationToInFlightRequestAsync()
    {
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var response = new TaskCompletionSource<HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var cancellation = new CancellationTokenSource();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var handler = new IntrospectionStub
        {
            Respond = async (_, token) =>
            {
                using var registration = token.Register(() => response.TrySetCanceled(token));
                started.TrySetResult();
                return await response.Task;
            }
        };
        using var client = new HttpClient(handler);
        var pending = Create(client).IsActiveAsync(TOKEN, cancellation.Token);
        await started.Task.WaitAsync(deadline.Token);

        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending.WaitAsync(deadline.Token));
        Assert.True(response.Task.IsCanceled);
    }

    /// <summary>Не читает env и пользовательские конфиги, использует только синтетическую конфигурацию.</summary>
    private static TokenIntrospection Create(HttpClient client) => new(client, Options.Create(new IntrospectionOptions
    {
        Issuer = "https://auth.test/",
        IntrospectionClientSecret = AuthFactory.IntrospectionSecret
    }));
}
