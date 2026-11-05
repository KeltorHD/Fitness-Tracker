using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.RegularExpressions;
using Microsoft.IdentityModel.Tokens;
using OpenIddict.Abstractions;
using static OpenIddict.Abstractions.OpenIddictConstants;

namespace FitnessTracker.Authentication;

public static class AuthConfiguration
{
    public const string ClientId = "fitnesstracker-ios";
    /// <summary>Отдельный public client для Personal Team без Associated Domains.</summary>
    public const string PersonalClientId = "fitnesstracker-ios-personal";
    public const string Audience = "fitnesstracker-api";
    public const string Callback = "https://auth.example.com/ios/oauth/callback";

    public static X509Certificate2 Certificate(IConfiguration config, string name) =>
        X509CertificateLoader.LoadPkcs12FromFile(
            config[$"Certificates:{name}:Path"] ?? throw new InvalidOperationException($"Missing {name} certificate."),
            config[$"Certificates:{name}:Password"]);

    public static void AddProviders(OpenIddictClientBuilder options, IConfiguration config)
    {
        var providers = options.UseWebProviders();
        if (Enabled(config, "Google"))
            providers.AddGoogle(provider => provider
                .SetClientId(Required(config, "Google", "ClientId"))
                .SetClientSecret(Required(config, "Google", "ClientSecret"))
                .SetRedirectUri("callback/login/google")
                .AddScopes("email", "profile"));
        if (Enabled(config, "Yandex"))
            providers.AddYandex(provider => provider
                .SetClientId(Required(config, "Yandex", "ClientId"))
                .SetClientSecret(Required(config, "Yandex", "ClientSecret"))
                .SetRedirectUri("callback/login/yandex")
                .AddScopes("login:info", "login:email"));
        if (Enabled(config, "Apple"))
        {
            var key = ECDsa.Create();
            key.ImportFromPem(File.ReadAllText(Required(config, "Apple", "PrivateKeyPath")));
            providers.AddApple(provider => provider
                .SetClientId(Required(config, "Apple", "ClientId"))
                .SetTeamId(Required(config, "Apple", "TeamId"))
                .SetSigningKey(new ECDsaSecurityKey(key) { KeyId = Required(config, "Apple", "KeyId") })
                .SetRedirectUri("callback/login/apple")
                .AddScopes("email", "name"));
        }
    }

    /// <summary>Разрешает внешний вход только при включённом провайдере и полном наборе его настроек.</summary>
    public static bool Enabled(IConfiguration config, string provider)
    {
        string[] required = provider switch
        {
            "Google" or "Yandex" => ["ClientId", "ClientSecret"],
            "Apple" => ["ClientId", "TeamId", "KeyId", "PrivateKeyPath"],
            _ => []
        };
        return required.Length > 0 && config.GetValue<bool>($"Providers:{provider}:Enabled") &&
            required.All(key => !string.IsNullOrWhiteSpace(config[$"Providers:{provider}:{key}"])) &&
            (provider != "Apple" || File.Exists(config["Providers:Apple:PrivateKeyPath"]));
    }

    private static string Required(IConfiguration config, string provider, string key) =>
        config[$"Providers:{provider}:{key}"] is { Length: > 0 } value ? value :
            throw new InvalidOperationException($"Missing configuration for {provider}: {key}.");

    /// <summary>Создаёт или обновляет public iOS и confidential Backend clients с поддержкой отмены.</summary>
    public static async Task RegisterClient(IServiceProvider services, IConfiguration config,
        CancellationToken cancellationToken = default)
    {
        var manager = services.GetRequiredService<IOpenIddictApplicationManager>();
        var redirect = new Uri(config["Auth:RedirectUri"] ?? Callback);
        if (redirect.Scheme != Uri.UriSchemeHttps || !string.IsNullOrEmpty(redirect.UserInfo) ||
            !string.IsNullOrEmpty(redirect.Query) || !string.IsNullOrEmpty(redirect.Fragment) ||
            redirect.AbsolutePath != "/ios/oauth/callback")
            throw new InvalidOperationException("The iOS callback must use HTTPS and /ios/oauth/callback.");
        await RegisterPublicClientAsync(manager, ClientId, redirect, "FitnessTracker для iOS", cancellationToken);
        await RegisterPersonalClientAsync(manager, config, cancellationToken);
        await RegisterIntrospectionClientAsync(manager, config, cancellationToken);
    }

    /// <summary>Регистрирует только явно настроенную reverse-DNS URL-схему; отключение удаляет её client и grants.</summary>
    private static async Task RegisterPersonalClientAsync(IOpenIddictApplicationManager manager, IConfiguration config,
        CancellationToken cancellationToken)
    {
        var scheme = config["Auth:PersonalCallbackScheme"];
        if (string.IsNullOrEmpty(scheme))
        {
            var existing = await manager.FindByClientIdAsync(PersonalClientId, cancellationToken);
            if (existing is not null) await manager.DeleteAsync(existing, cancellationToken);
            return;
        }
        if (scheme.Length > 253 || !scheme.Contains('.') || !Uri.CheckSchemeName(scheme) ||
            scheme.Split('.').Any(label => !Regex.IsMatch(label, @"\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z")))
            throw new InvalidOperationException("Auth:PersonalCallbackScheme must be a lowercase reverse-DNS URI scheme.");
        await RegisterPublicClientAsync(manager, PersonalClientId, new Uri(scheme + ":/ios/oauth/callback"),
            "FitnessTracker Personal для iOS", cancellationToken);
    }

    /// <summary>Создаёт либо обновляет public client с единственным callback и обязательным PKCE.</summary>
    private static async Task RegisterPublicClientAsync(IOpenIddictApplicationManager manager, string clientId, Uri redirect,
        string displayName, CancellationToken cancellationToken)
    {
        var descriptor = new OpenIddictApplicationDescriptor
        {
            ClientId = clientId,
            ClientType = ClientTypes.Public,
            ConsentType = ConsentTypes.Implicit,
            DisplayName = displayName,
            RedirectUris = { redirect },
            Permissions =
            {
                Permissions.Endpoints.Authorization, Permissions.Endpoints.Token, Permissions.Endpoints.Revocation,
                Permissions.GrantTypes.AuthorizationCode, Permissions.GrantTypes.RefreshToken,
                Permissions.ResponseTypes.Code, Permissions.Scopes.Profile
            },
            Requirements = { Requirements.Features.ProofKeyForCodeExchange }
        };
        var existing = await manager.FindByClientIdAsync(clientId, cancellationToken);
        if (existing is null) await manager.CreateAsync(descriptor, cancellationToken);
        else await manager.UpdateAsync(existing, descriptor, cancellationToken);
    }

    /// <summary>Регистрирует серверный confidential client с единственным разрешением introspection.</summary>
    private static async Task RegisterIntrospectionClientAsync(IOpenIddictApplicationManager manager, IConfiguration config,
        CancellationToken cancellationToken = default)
    {
        var secret = config["Auth:IntrospectionClientSecret"];
        if (string.IsNullOrWhiteSpace(secret) || secret.Length < 32)
            throw new InvalidOperationException("Auth:IntrospectionClientSecret must have at least 32 characters.");
        var descriptor = new OpenIddictApplicationDescriptor
        {
            ClientId = Audience,
            ClientSecret = secret,
            ClientType = ClientTypes.Confidential,
            DisplayName = "FitnessTracker Backend",
            Permissions = { Permissions.Endpoints.Introspection }
        };
        var existing = await manager.FindByClientIdAsync(Audience, cancellationToken);
        if (existing is null) await manager.CreateAsync(descriptor, cancellationToken);
        else await manager.UpdateAsync(existing, descriptor, cancellationToken);
    }
}
