using System.Text.Json;
using OpenIddict.Abstractions;
using OpenIddict.Client;
using OpenIddict.Client.SystemNetHttp;
using static OpenIddict.Abstractions.OpenIddictConstants;
using static OpenIddict.Client.OpenIddictClientEvents;

namespace FitLife.Authentication;

/// <summary>Подключает официальный Xiaomi Health OAuth к существующему OpenIddict client.</summary>
public static class XiaomiHealthOAuth
{
    /// <summary>Постоянное имя регистрации и публичного контракта.</summary>
    public const string Provider = "miFitness";
    /// <summary>Отдельный callback исключает смешение авторизаций разных внешних провайдеров.</summary>
    public const string CallbackPath = "callback/health/mi-fitness";
    /// <summary>Разрешения Xiaomi: категории здоровья и доступ к последнему месяцу истории.</summary>
    internal static readonly Dictionary<string, string[]> ScopeMetrics = new()
    {
        ["200016"] = ["steps"],
        ["200001"] = ["totalEnergy"],
        ["200007"] = ["heartRate", "restingHeartRate"],
        ["200008"] = ["bloodOxygen"],
        ["200009"] = ["sleep"],
        ["200010"] = ["bodyWeight", "bodyFatPercentage"]
    };

    /// <summary>Проверяет явное включение и полный набор серверных credentials.</summary>
    public static bool Enabled(IConfiguration configuration) => configuration.GetValue<bool>("HealthProviders:MiFitness:Enabled") &&
        long.TryParse(configuration["HealthProviders:MiFitness:ClientId"], out var id) && id > 0 &&
        !string.IsNullOrWhiteSpace(configuration["HealthProviders:MiFitness:ClientSecret"]);

    /// <summary>Регистрирует статические официальные endpoints и адаптирует документированные особенности Xiaomi.</summary>
    public static void Configure(OpenIddictClientBuilder builder, IConfiguration configuration)
    {
        if (!Enabled(configuration)) return;
        builder.UseSystemNetHttp()
            .ConfigureHttpClient(Provider, client => client.Timeout = TimeSpan.FromSeconds(15))
            .ConfigureHttpClientHandler(Provider, handler => { handler.AllowAutoRedirect = false; handler.UseCookies = false; });
        builder.AllowRefreshTokenFlow();
        builder.AddRegistration(new OpenIddictClientRegistration
        {
            ProviderName = Provider,
            RegistrationId = Provider,
            Issuer = new Uri("https://account.xiaomi.com/"),
            ClientId = configuration["HealthProviders:MiFitness:ClientId"],
            ClientSecret = configuration["HealthProviders:MiFitness:ClientSecret"],
            RedirectUri = new Uri(CallbackPath, UriKind.Relative),
            Scopes = { "200016", "200001", "200007", "200008", "200009", "200010", "200013" },
            Configuration = new OpenIddictConfiguration
            {
                AuthorizationEndpoint = new Uri("https://account.xiaomi.com/oauth2/authorize"),
                TokenEndpoint = new Uri("https://account.xiaomi.com/oauth2/token"),
                GrantTypesSupported = { GrantTypes.AuthorizationCode, GrantTypes.RefreshToken },
                ResponseTypesSupported = { ResponseTypes.Code },
                TokenEndpointAuthMethodsSupported = { ClientAuthenticationMethods.ClientSecretPost }
            }
        });
        builder.AddEventHandler<ProcessChallengeContext>(handler => handler
            .SetOrder(OpenIddictClientHandlers.AttachChallengeParameters.Descriptor.Order - 500)
            .UseInlineHandler(context =>
            {
                if (context.Registration.ProviderName == Provider)
                {
                    context.Parameters["scope_provider"] = "healthkit";
                    context.Parameters["skip_confirm"] = "false";
                }
                return default;
            }));
        builder.AddEventHandler<ProcessAuthenticationContext>(handler => handler
            .SetOrder(OpenIddictClientHandlers.ResolveTokenEndpoint.Descriptor.Order + 500)
            .UseInlineHandler(context =>
            {
                if (context.Registration.ProviderName == Provider && context.GrantType == GrantTypes.RefreshToken)
                    context.TokenEndpoint = new Uri("https://account.xiaomi.com/oauth2/refresh/token");
                return default;
            }));
        builder.AddEventHandler<ProcessAuthenticationContext>(handler => handler
            .SetOrder(OpenIddictClientHandlers.MapStandardWebServicesFederationClaims.Descriptor.Order + 500)
            .UseInlineHandler(context =>
            {
                if (context.Registration.ProviderName == Provider)
                    context.Properties["health_metrics"] = JsonSerializer.Serialize(Metrics(context.TokenResponse?.Scope));
                return default;
            }));
        builder.AddEventHandler<PrepareTokenRequestContext>(handler => handler
            .SetOrder(OpenIddictClientSystemNetHttpHandlers.AttachHttpParameters<PrepareTokenRequestContext>.Descriptor.Order - 500)
            .UseInlineHandler(context =>
            {
                if (context.Registration.ProviderName == Provider)
                {
                    context.Request["pt"] = "0";
                    if (context.Request.GrantType == GrantTypes.RefreshToken)
                        context.Request.RedirectUri = new Uri(new Uri(configuration["Auth:Issuer"]!), CallbackPath).AbsoluteUri;
                }
                return default;
            }));
        builder.AddEventHandler<ExtractTokenResponseContext>(handler => handler
            .SetOrder(OpenIddictClientSystemNetHttpHandlers.ExtractJsonHttpResponse<ExtractTokenResponseContext>.Descriptor.Order - 500)
            .UseInlineHandler(async context =>
            {
                if (context.Registration.ProviderName != Provider) return;
                var response = context.Transaction.GetHttpResponseMessage();
                if (response?.Content is null) return;
                // Некоторые ответы Xiaomi содержат защитный префикс &&&START&&& вместо чистого JSON.
                await using var stream = await response.Content.ReadAsStreamAsync(context.CancellationToken);
                using var buffer = new MemoryStream();
                var chunk = new byte[8192];
                while (true)
                {
                    var count = await stream.ReadAsync(chunk, context.CancellationToken);
                    if (count == 0) break;
                    if (buffer.Length + count > 65_536) { context.Reject(Errors.ServerError); return; }
                    await buffer.WriteAsync(chunk.AsMemory(0, count), context.CancellationToken);
                }
                var bytes = buffer.ToArray().AsMemory();
                if (bytes.Span.StartsWith("&&&START&&&"u8)) bytes = bytes["&&&START&&&".Length..];
                try
                {
                    using var json = JsonDocument.Parse(bytes);
                    context.Response = new OpenIddictResponse(json.RootElement.Clone());
                    // Resource API Xiaomi документирован как Bearer, даже если legacy token response говорит MAC.
                    if (!string.IsNullOrEmpty(context.Response.AccessToken)) context.Response.TokenType = TokenTypes.Bearer;
                }
                catch (JsonException) { context.Reject(Errors.ServerError); }
            }));
    }

    /// <summary>Преобразует только явно возвращённые scope в разрешённые категории, без повышения прав.</summary>
    internal static string[] Metrics(string? scope) => (scope ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries)
        .Where(ScopeMetrics.ContainsKey).SelectMany(item => ScopeMetrics[item]).Distinct().Order().ToArray();
}
