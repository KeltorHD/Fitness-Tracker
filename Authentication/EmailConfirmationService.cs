using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;

namespace FitnessTracker.Authentication;

/// <summary>Применяет подтверждение только к новым локальным аккаунтам, сохраняя прежний доступ.</summary>
public sealed class EmailAccountConfirmation : IUserConfirmation<ApplicationUser>
{
    /// <summary>Legacy/внешние аккаунты не требуют проверки; новые email-аккаунты ждут EmailConfirmed.</summary>
    public Task<bool> IsConfirmedAsync(UserManager<ApplicationUser> manager, ApplicationUser user) =>
        Task.FromResult(!user.EmailConfirmationRequired || user.EmailConfirmed);
}

/// <summary>Ограничивает повторную отправку раз в минуту на хеш адреса, также для неизвестных аккаунтов.</summary>
public sealed class EmailConfirmationThrottle(TimeProvider clock) : IDisposable
{
    private readonly MemoryCache _cache = new(new MemoryCacheOptions { SizeLimit = 10_000 });
    private readonly object _gate = new();

    /// <summary>Не хранит email; при переполнении cache не разрешает неограниченную отправку.</summary>
    public bool TryAcquire(string opaqueKey)
    {
        lock (_gate)
        {
            var now = clock.GetUtcNow();
            if (_cache.TryGetValue<DateTimeOffset>(opaqueKey, out var next) && next > now) return false;
            var deadline = now.AddMinutes(1);
            _cache.Set(opaqueKey, deadline, new MemoryCacheEntryOptions
            { AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1), Size = 1 });
            return _cache.TryGetValue<DateTimeOffset>(opaqueKey, out var saved) && saved == deadline;
        }
    }

    /// <summary>Освобождает ограниченное хранилище при остановке приложения.</summary>
    public void Dispose() => _cache.Dispose();
}

/// <summary>Ведёт выдачу/проверку штатных Identity email tokens, не выполняя автоматический вход по ссылке.</summary>
public sealed class EmailConfirmationService(UserManager<ApplicationUser> users, EmailAccounts accounts,
    IAccountEmailSender sender, IOptions<SmtpOptions> smtp, IConfiguration config,
    EmailConfirmationThrottle throttle, BrowserNavigation navigation, ILogger<EmailConfirmationService> logger)
{
    /// <summary>Новая email-регистрация доступна только при настроенной доставке.</summary>
    public bool IsAvailable => smtp.Value.Enabled;

    /// <summary>Возвращает локальное продолжение без email, user ID или токена в URL страницы ожидания.</summary>
    public string PendingUrl(string? returnUrl) => "/email/verify" + QueryString.Create("returnUrl", navigation.LocalReturn(returnUrl));

    /// <summary>Готовит страницу повтора без раскрытия существования указанного email.</summary>
    public EmailPendingPageData GetPending(NavigationInput input, bool submitted = false) =>
        new(navigation.LocalReturn(input.ReturnUrl), IsAvailable, submitted);

    /// <summary>Отправляет первое письмо после создания аккаунта; ошибка не удаляет пользователя и допускает повтор.</summary>
    public async Task SendForNewUserAsync(ApplicationUser user, CancellationToken cancellationToken)
    {
        if (user.Email is not { } email || !IsAvailable || !throttle.TryAcquire(accounts.UserName(email))) return;
        await SendAsync(user, email, cancellationToken);
    }

    /// <summary>Даёт одинаковый ответ для неизвестных, подтверждённых, legacy и ожидающих аккаунтов.</summary>
    public async Task<EmailPendingPageData> ResendAsync(EmailResendInput input, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var result = GetPending(new(input.ReturnUrl), submitted: true);
        var address = EmailAccounts.ValidateEmail(input.Email);
        if (!IsAvailable || address is null || !throttle.TryAcquire(accounts.UserName(address))) return result;
        var user = await users.FindByNameAsync(accounts.UserName(address));
        if (user is { EmailConfirmationRequired: true, EmailConfirmed: false })
            await SendAsync(user, user.Email!, cancellationToken);
        return result;
    }

    /// <summary>GET только показывает форму: почтовый сканер не может подтвердить адрес переходом по ссылке.</summary>
    public EmailConfirmPageData GetConfirmationPage(EmailConfirmationInput input) => ValidShape(input)
        ? new(input.UserId!, input.Code!, true) : new("", "", false);

    /// <summary>Проверяет токен/срок/пользователя штатным Identity после явного CSRF-защищённого POST.</summary>
    public async Task<EmailConfirmationOutcome> ConfirmAsync(EmailConfirmationInput input, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!ValidShape(input)) return new(false);
        string token;
        try { token = new UTF8Encoding(false, true).GetString(WebEncoders.Base64UrlDecode(input.Code!)); }
        catch (Exception error) when (error is FormatException or DecoderFallbackException) { return new(false); }
        var user = await users.FindByIdAsync(input.UserId!);
        if (user is null) return new(false);
        var confirmed = await users.ConfirmEmailAsync(user, token);
        return new(confirmed.Succeeded);
    }

    /// <summary>Строит ссылку только от настроенного issuer, а не из входного Host или returnUrl.</summary>
    private async Task SendAsync(ApplicationUser user, string email, CancellationToken cancellationToken)
    {
        var issuer = new Uri(config["Auth:Issuer"] ?? throw new InvalidOperationException("Auth:Issuer is required."));
        var token = await users.GenerateEmailConfirmationTokenAsync(user);
        var code = WebEncoders.Base64UrlEncode(Encoding.UTF8.GetBytes(token));
        var link = QueryHelpers.AddQueryString(new Uri(issuer, "email/confirm").AbsoluteUri,
            new Dictionary<string, string?> { ["userId"] = user.Id, ["code"] = code });
        try { await sender.SendConfirmationAsync(email, link, cancellationToken); }
        catch (EmailDeliveryException error)
        {
            // Только безопасный код, без exception/recipient/link, которые могут содержать секреты.
            logger.LogError("Email confirmation delivery failed: {DeliveryCode}", error.Message);
        }
    }

    /// <summary>Ограничивает размеры до декодирования и DB-запроса.</summary>
    private static bool ValidShape(EmailConfirmationInput input) => Guid.TryParse(input.UserId, out _) &&
        input.Code is { Length: > 0 and <= 4096 } && input.Code.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_');
}
