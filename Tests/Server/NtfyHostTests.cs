using System.Net;
using System.Text.Json;
using FitnessTracker.ServerLogging;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет реальное подключение sink к обоим независимым HTTP host без внешнего ntfy.</summary>
[Trait("Category", "HTTP")]
public sealed class NtfyHostTests
{
    /// <summary>Authentication отправляет application error с собственным именем сервиса.</summary>
    [Fact]
    public async Task AuthenticationUsesConfiguredNtfyAsync()
    {
        using var factory = new AuthFactory();
        await VerifyAsync(factory, "Authentication");
    }

    /// <summary>Backend отправляет application error без влияния на JWT/health pipeline.</summary>
    [Fact]
    public async Task BackendUsesConfiguredNtfyAsync()
    {
        using var factory = new BackendFactory();
        await VerifyAsync(factory, "Backend");
    }

    /// <summary>Подменяет только transport, сохраняя Program, регистрацию DI и стандартный ILoggerFactory.</summary>
    private static async Task VerifyAsync<T>(WebApplicationFactory<T> factory, string name) where T : class
    {
        using var handler = new CaptureHandler();
        using var host = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Ntfy:Enabled"] = "true",
                ["Ntfy:ServerUrl"] = "https://ntfy.example.com/",
                ["Ntfy:Topic"] = "isolated-host-test",
                ["Ntfy:MinimumLevel"] = "Error",
                ["Ntfy:Token"] = "tk_synthetic_private_host_token"
            }));
            builder.ConfigureServices(services => services.AddHttpClient("FitnessTracker.Ntfy")
                .ConfigurePrimaryHttpMessageHandler(() => handler));
        });
        using var client = host.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new("https://localhost") });
        using var health = await client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, health.StatusCode);

        var logger = host.Services.GetRequiredService<ILoggerFactory>().CreateLogger("FitnessTracker.DeliveryTest");
        logger.LogInformation("filtered-host-info");
        logger.LogError("host-delivery-error");
        host.Services.GetRequiredService<ILoggerFactory>().CreateLogger("FitnessTracker.ServerLogging.Ntfy")
            .LogCritical("must-not-recurse");
        await host.Services.GetRequiredService<NtfyLoggerProvider>().DisposeAsync();

        using var body = JsonDocument.Parse(Assert.Single(handler.Bodies));
        Assert.Equal($"FitnessTracker {name}: Error", body.RootElement.GetProperty("title").GetString());
        Assert.Contains("host-delivery-error", body.RootElement.GetProperty("message").GetString());
        Assert.DoesNotContain("tk_synthetic_private_host_token", body.RootElement.GetProperty("message").GetString());
    }

    /// <summary>Считывает только синтетические публикации, без TCP/TLS и секретов окружения.</summary>
    private sealed class CaptureHandler : HttpMessageHandler
    {
        /// <summary>Доступен после завершения очереди провайдера.</summary>
        internal List<string> Bodies { get; } = [];
        /// <summary>Подтверждает одну публикацию без вызова ntfy.</summary>
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Bodies.Add(await request.Content!.ReadAsStringAsync(cancellationToken));
            return new(HttpStatusCode.OK);
        }
    }
}
