using System.Globalization;
using System.Security.Cryptography;
using System.Security.Claims;
using System.Text.Json;
using System.Text;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using OpenIddict.Abstractions;
using OpenIddict.Client;
using OpenIddict.Client.AspNetCore;

namespace FitLife.Authentication;

/// <summary>Владеет явными OAuth-привязками здоровья, их шифрованием, отзывом и сериализованной ротацией.</summary>
public sealed class HealthConnectionService(AuthDbContext database, UserManager<ApplicationUser> users,
    SignInManager<ApplicationUser> signIn, IConfiguration configuration, IDataProtectionProvider protection,
    IHealthConnectionLocks locks, OpenIddictClientService client, IHttpContextAccessor contexts,
    BrowserNavigation navigation, TimeProvider clock, IHttpClientFactory http)
{
    private readonly IDataProtector _protector = protection.CreateProtector("FitLife.HealthConnections.v1");

    /// <summary>Готовит страницу текущего cookie-владельца и проверенное продолжение браузерного входа.</summary>
    public async Task<HealthConnectionsPageData> GetPageAsync(ClaimsPrincipal principal, NavigationInput input, CancellationToken cancellationToken)
    {
        var user = await CurrentAsync(principal, cancellationToken);
        return new(navigation.LocalReturn(input.ReturnUrl), await StatusAsync(user.Id, cancellationToken));
    }

    /// <summary>Проверяет браузерного владельца, отзывает разрешение и возвращает безопасное продолжение.</summary>
    public async Task<string> DisconnectBrowserAsync(ClaimsPrincipal principal, NavigationInput input, CancellationToken cancellationToken)
    {
        var user = await CurrentAsync(principal, cancellationToken);
        await DisconnectAsync(user.Id, cancellationToken);
        return "/account/health" + QueryString.Create("returnUrl", navigation.LocalReturn(input.ReturnUrl));
    }

    /// <summary>Выдаёт grant только доверенному Backend после constant-time проверки существующего service key.</summary>
    public Task<HealthProviderGrant> GrantForBackendAsync(Guid owner, string supplied, CancellationToken cancellationToken)
    {
        var expected = configuration["Backend:ServiceKey"];
        if (string.IsNullOrWhiteSpace(expected) || expected.Length < 32 || supplied.Length > 512 ||
            !CryptographicOperations.FixedTimeEquals(SHA256.HashData(Encoding.UTF8.GetBytes(expected)), SHA256.HashData(Encoding.UTF8.GetBytes(supplied))))
            throw new AuthenticationOperationException(AuthenticationFailure.Unauthorized);
        return GrantAsync(owner.ToString(), cancellationToken);
    }

    /// <summary>Возвращает только разрешённые сведения, не обновляя токены при простом открытии страницы.</summary>
    public async Task<HealthConnectionStatus[]> StatusAsync(string userId, CancellationToken cancellationToken)
    {
        var row = await database.HealthConnections.AsNoTracking().SingleOrDefaultAsync(
            item => item.UserId == userId && item.Provider == XiaomiHealthOAuth.Provider, cancellationToken);
        var available = XiaomiHealthOAuth.Enabled(configuration);
        var tokens = row is { ProtectedTokens.Length: > 0 } ? Read(row) : null;
        var connected = available && tokens?.ClientId == configuration["HealthProviders:MiFitness:ClientId"];
        return [new(XiaomiHealthOAuth.Provider, available, connected, connected ? tokens!.Metrics : [])];
    }

    /// <summary>Проверяет текущего cookie-владельца и передаёт state/одноразовость штатному OpenIddict.</summary>
    public async Task<AuthenticationProperties> StartAsync(ClaimsPrincipal principal, NavigationInput input,
        CancellationToken cancellationToken)
    {
        if (!XiaomiHealthOAuth.Enabled(configuration)) throw new AuthenticationOperationException(AuthenticationFailure.Unavailable);
        var user = await CurrentAsync(principal, cancellationToken);
        await using var lease = await locks.AcquireAsync(user.Id, cancellationToken);
        var row = await database.HealthConnections.FindAsync([user.Id, XiaomiHealthOAuth.Provider], cancellationToken);
        if (row is null)
        {
            row = new HealthConnection { UserId = user.Id, Provider = XiaomiHealthOAuth.Provider };
            database.HealthConnections.Add(row);
        }
        row.AttemptId = Guid.NewGuid();
        row.UpdatedAt = clock.GetUtcNow();
        await database.SaveChangesAsync(cancellationToken);
        var properties = new AuthenticationProperties { RedirectUri = "/account/health" + QueryString.Create("returnUrl", navigation.LocalReturn(input.ReturnUrl)) };
        properties.Items[OpenIddictClientAspNetCoreConstants.Properties.RegistrationId] = XiaomiHealthOAuth.Provider;
        properties.Items["health_user"] = user.Id;
        properties.Items["health_stamp"] = await users.GetSecurityStampAsync(user);
        properties.Items["health_attempt"] = row.AttemptId.Value.ToString();
        return properties;
    }

    /// <summary>Принимает callback только для того же пользователя и актуальной попытки; не создаёт способ входа.</summary>
    public async Task<string> CompleteAsync(ClaimsPrincipal principal, CancellationToken cancellationToken)
    {
        var user = await CurrentAsync(principal, cancellationToken);
        var context = contexts.HttpContext ?? throw new InvalidOperationException("A health callback context is required.");
        var result = await context.AuthenticateAsync(OpenIddictClientAspNetCoreDefaults.AuthenticationScheme);
        if (!result.Succeeded || result.Properties is null ||
            result.Principal?.GetClaim(OpenIddictConstants.Claims.Private.ProviderName) != XiaomiHealthOAuth.Provider ||
            Property(result.Properties, "health_user") != user.Id ||
            Property(result.Properties, "health_stamp") != await users.GetSecurityStampAsync(user) ||
            !Guid.TryParse(Property(result.Properties, "health_attempt"), out var attempt))
            throw new AuthenticationOperationException(AuthenticationFailure.InvalidInput);
        var access = result.Properties.GetTokenValue(OpenIddictClientAspNetCoreConstants.Tokens.BackchannelAccessToken);
        var refresh = result.Properties.GetTokenValue(OpenIddictClientAspNetCoreConstants.Tokens.RefreshToken);
        var expiry = result.Properties.GetTokenValue(OpenIddictClientAspNetCoreConstants.Tokens.BackchannelAccessTokenExpirationDate);
        var metrics = JsonSerializer.Deserialize<string[]>(Property(result.Properties, "health_metrics") ?? "[]") ?? [];
        if (string.IsNullOrEmpty(access) || string.IsNullOrEmpty(refresh) ||
            !DateTimeOffset.TryParse(expiry, CultureInfo.InvariantCulture, DateTimeStyles.None, out var expiresAt) ||
            expiresAt <= clock.GetUtcNow() || metrics.Length == 0)
            throw new AuthenticationOperationException(AuthenticationFailure.InvalidInput);
        await using var lease = await locks.AcquireAsync(user.Id, cancellationToken);
        var row = await database.HealthConnections.FindAsync([user.Id, XiaomiHealthOAuth.Provider], cancellationToken);
        if (row?.AttemptId != attempt) throw new AuthenticationOperationException(AuthenticationFailure.Conflict);
        Save(row, new(access, refresh, expiresAt, configuration["HealthProviders:MiFitness:ClientId"]!, metrics));
        row.AttemptId = null;
        await database.SaveChangesAsync(cancellationToken);
        return navigation.LocalReturn(result.Properties.RedirectUri);
    }

    /// <summary>Выдаёт только Backend access token; повторная ротация и отключение используют общую блокировку.</summary>
    public async Task<HealthProviderGrant> GrantAsync(string userId, CancellationToken cancellationToken)
    {
        if (!XiaomiHealthOAuth.Enabled(configuration)) throw new AuthenticationOperationException(AuthenticationFailure.Unavailable);
        await using var lease = await locks.AcquireAsync(userId, cancellationToken);
        var user = await users.FindByIdAsync(userId);
        if (user is null || !await signIn.CanSignInAsync(user) || await users.IsLockedOutAsync(user))
            throw new AuthenticationOperationException(AuthenticationFailure.NotFound);
        var row = await database.HealthConnections.FindAsync([userId, XiaomiHealthOAuth.Provider], cancellationToken);
        if (row is null || row.ProtectedTokens.Length == 0) throw new AuthenticationOperationException(AuthenticationFailure.NotFound);
        var tokens = Read(row);
        if (tokens.ClientId != configuration["HealthProviders:MiFitness:ClientId"])
            throw new AuthenticationOperationException(AuthenticationFailure.NotFound);
        tokens = await RefreshAsync(row, tokens, cancellationToken)
            ?? throw new AuthenticationOperationException(AuthenticationFailure.NotFound);
        return new(tokens.AccessToken, tokens.ClientId, tokens.Metrics);
    }

    /// <summary>Явно отзывает Xiaomi-разрешение; отказ облака сохраняет возможность безопасного повтора.</summary>
    public async Task DisconnectAsync(string userId, CancellationToken cancellationToken)
    {
        await using var lease = await locks.AcquireAsync(userId, cancellationToken);
        var row = await database.HealthConnections.FindAsync([userId, XiaomiHealthOAuth.Provider], cancellationToken);
        if (row is null) return;
        if (row.ProtectedTokens.Length > 0 && XiaomiHealthOAuth.Enabled(configuration))
        {
            var tokens = Read(row);
            if (tokens.ClientId == configuration["HealthProviders:MiFitness:ClientId"] &&
                await RefreshAsync(row, tokens, cancellationToken) is { } current)
            {
                tokens = current;
                using var body = new FormUrlEncodedContent(new Dictionary<string, string>
                {
                    ["access_token"] = tokens.AccessToken,
                    ["client_id"] = tokens.ClientId,
                    ["client_secret"] = configuration["HealthProviders:MiFitness:ClientSecret"]!
                });
                using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                deadline.CancelAfter(TimeSpan.FromSeconds(15));
                try
                {
                    using var request = new HttpRequestMessage(HttpMethod.Post, "https://open.account.xiaomi.com/user/unbindOAuth2Grained") { Content = body };
                    using var response = await http.CreateClient("xiaomi-health-revoke").SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                    if (!response.IsSuccessStatusCode || response.Content.Headers.ContentLength > 65_536)
                        throw new AuthenticationOperationException(AuthenticationFailure.Unavailable);
                    await using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
                    using var memory = new MemoryStream();
                    var buffer = new byte[8192];
                    while (true)
                    {
                        var count = await stream.ReadAsync(buffer, deadline.Token);
                        if (count == 0) break;
                        if (memory.Length + count > 65_536) throw new AuthenticationOperationException(AuthenticationFailure.Unavailable);
                        await memory.WriteAsync(buffer.AsMemory(0, count), deadline.Token);
                    }
                    using var json = JsonDocument.Parse(memory.ToArray());
                    if (json.RootElement.ValueKind != JsonValueKind.Object || !json.RootElement.TryGetProperty("code", out var code) ||
                        code.ValueKind != JsonValueKind.Number || !code.TryGetInt32(out var number) || number != 0)
                        throw new AuthenticationOperationException(AuthenticationFailure.Unavailable);
                }
                catch (HttpRequestException) { throw new AuthenticationOperationException(AuthenticationFailure.Unavailable); }
                catch (JsonException) { throw new AuthenticationOperationException(AuthenticationFailure.Unavailable); }
                catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) { throw new AuthenticationOperationException(AuthenticationFailure.Unavailable); }
            }
        }
        row.ProtectedTokens = "";
        row.AttemptId = null;
        row.UpdatedAt = clock.GetUtcNow();
        await database.SaveChangesAsync(cancellationToken);
    }

    /// <summary>Обновляет истёкшее разрешение перед чтением или отзывом; сохраняет ротацию с ограниченным сроком.</summary>
    private async Task<HealthProviderTokens?> RefreshAsync(HealthConnection row, HealthProviderTokens tokens, CancellationToken cancellationToken)
    {
        if (tokens.ExpiresAt <= clock.GetUtcNow().AddMinutes(1))
        {
            try
            {
                var rotated = await client.AuthenticateWithRefreshTokenAsync(new()
                {
                    RegistrationId = XiaomiHealthOAuth.Provider,
                    RefreshToken = tokens.RefreshToken,
                    DisableUserInfo = true,
                    CancellationToken = cancellationToken
                });
                var metrics = rotated.TokenResponse.Scope is { } scope ? XiaomiHealthOAuth.Metrics(scope) : tokens.Metrics;
                if (rotated.AccessTokenExpirationDate is not { } expiresAt || expiresAt <= clock.GetUtcNow() ||
                    string.IsNullOrEmpty(rotated.AccessToken))
                    throw new AuthenticationOperationException(AuthenticationFailure.Unavailable);
                tokens = new(rotated.AccessToken, rotated.RefreshToken ?? tokens.RefreshToken, expiresAt, tokens.ClientId, metrics);
                Save(row, tokens);
                // Ротация должна быть сохранена даже если экран отменил ожидание после выдачи нового refresh token.
                using var saveDeadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
                await database.SaveChangesAsync(saveDeadline.Token);
            }
            catch (OpenIddictExceptions.ProtocolException error) when (error.Error == OpenIddictConstants.Errors.InvalidGrant)
            {
                row.ProtectedTokens = "";
                using var saveDeadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
                await database.SaveChangesAsync(saveDeadline.Token);
                return null;
            }
            catch (OpenIddictExceptions.ProtocolException) { throw new AuthenticationOperationException(AuthenticationFailure.Unavailable); }
        }
        return tokens;
    }

    /// <summary>Сверяет текущего Identity-пользователя без доверия к идентификатору из формы.</summary>
    internal async Task<ApplicationUser> CurrentAsync(ClaimsPrincipal principal, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var user = await users.GetUserAsync(principal);
        if (user is null || !await signIn.CanSignInAsync(user) || await users.IsLockedOutAsync(user))
            throw new AuthenticationOperationException(AuthenticationFailure.Unauthorized);
        return user;
    }

    /// <summary>Шифрует весь набор credentials до передачи EF Core.</summary>
    private void Save(HealthConnection row, HealthProviderTokens tokens)
    {
        row.ProtectedTokens = _protector.Protect(JsonSerializer.Serialize(tokens));
        row.UpdatedAt = clock.GetUtcNow();
    }

    /// <summary>Повреждённые credentials не удаляются и не превращаются в ложное «подключено».</summary>
    private HealthProviderTokens Read(HealthConnection row)
    {
        try
        {
            var tokens = JsonSerializer.Deserialize<HealthProviderTokens>(_protector.Unprotect(row.ProtectedTokens));
            if (tokens is null || string.IsNullOrEmpty(tokens.AccessToken) || string.IsNullOrEmpty(tokens.RefreshToken) || tokens.Metrics is null)
                throw new AuthenticationOperationException(AuthenticationFailure.Unavailable);
            return tokens;
        }
        catch (CryptographicException) { throw new AuthenticationOperationException(AuthenticationFailure.Unavailable); }
        catch (JsonException) { throw new AuthenticationOperationException(AuthenticationFailure.Unavailable); }
    }

    /// <summary>Читает необязательные свойства проверенного OpenIddict state.</summary>
    private static string? Property(AuthenticationProperties properties, string key) =>
        properties.Items.TryGetValue(key, out var value) ? value : null;
}
