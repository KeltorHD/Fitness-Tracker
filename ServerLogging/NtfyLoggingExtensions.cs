using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;

namespace FitnessTracker.ServerLogging;

/// <summary>Подключает одинаковый ILogger sink к двум независимым серверным приложениям.</summary>
public static class NtfyLoggingExtensions
{
    /// <summary>Регистрирует необязательный провайдер с собственным порогом, очередью и безопасным HTTP transport.</summary>
    public static ILoggingBuilder AddNtfy(this ILoggingBuilder logging, string serviceName)
    {
        logging.Services.TryAddSingleton(TimeProvider.System);
        logging.Services.AddSingleton(services => NtfyOptions.Read(services.GetRequiredService<IConfiguration>()));
        logging.Services.AddSingleton(services => new NtfyLogRedactor(services.GetRequiredService<IConfiguration>()));
        logging.Services.AddHttpClient("FitnessTracker.Ntfy", (services, client) =>
            client.Timeout = TimeSpan.FromSeconds(services.GetRequiredService<NtfyOptions>().TimeoutSeconds))
            .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
            {
                AllowAutoRedirect = false,
                UseCookies = false,
                PooledConnectionLifetime = TimeSpan.FromMinutes(5)
            })
            .RemoveAllLoggers();
        logging.Services.AddSingleton(services => new NtfyLoggerProvider(
            services.GetRequiredService<NtfyOptions>(), services.GetRequiredService<NtfyLogRedactor>(),
            services.GetRequiredService<TimeProvider>(), serviceName,
            () => (services.GetRequiredService<IHttpClientFactory>().CreateClient("FitnessTracker.Ntfy"),
                services.GetRequiredService<ILoggerFactory>().CreateLogger("FitnessTracker.ServerLogging.Ntfy"))));
        logging.Services.AddSingleton<ILoggerProvider>(services => services.GetRequiredService<NtfyLoggerProvider>());
        logging.Services.AddSingleton<IHostedService>(services => services.GetRequiredService<NtfyLoggerProvider>());
        // Собственный порог не зависит от console LogLevel и category filters другого провайдера.
        logging.AddFilter<NtfyLoggerProvider>((_, level) => level != LogLevel.None);
        return logging;
    }

    /// <summary>Запускает доставку до миграций; async scope сбрасывает очередь также при ошибке startup.</summary>
    public static IAsyncDisposable StartNtfyLogging(this IServiceProvider services)
    {
        var provider = services.GetRequiredService<NtfyLoggerProvider>();
        provider.Start();
        return provider;
    }
}
