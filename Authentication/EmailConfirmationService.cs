using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;

namespace FitLife.Authentication;

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
    EmailConfirmationThrottle throttle, BrowserNavigation navigation, PendingRegistrationCleanup pendingRegistrations,
    ILogger<EmailConfirmationService> logger)
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
        var attemptId = LogRequested("registration");
        if (!IsAvailable) { LogSkipped(attemptId, "smtp_disabled"); return; }
        if (user.Email is not { Length: > 0 } email) { LogSkipped(attemptId, "invalid_address"); return; }
        if (!throttle.TryAcquire(accounts.UserName(email))) { LogSkipped(attemptId, "throttled"); return; }
        await SendAsync(user, email, attemptId, cancellationToken);
    }

    /// <summary>Даёт одинаковый ответ для неизвестных, подтверждённых, legacy и ожидающих аккаунтов.</summary>
    public async Task<EmailPendingPageData> ResendAsync(EmailResendInput input, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var attemptId = LogRequested("resend");
        var result = GetPending(new(input.ReturnUrl), submitted: true);
        var address = EmailAccounts.ValidateEmail(input.Email);
        if (!IsAvailable) { LogSkipped(attemptId, "smtp_disabled"); return result; }
        if (address is null) { LogSkipped(attemptId, "invalid_address"); return result; }
        if (!throttle.TryAcquire(accounts.UserName(address))) { LogSkipped(attemptId, "throttled"); return result; }
        var user = await users.FindByNameAsync(accounts.UserName(address));
        if (user is null) LogSkipped(attemptId, "account_not_found");
        else if (!user.EmailConfirmationRequired) LogSkipped(attemptId, "confirmation_not_required");
        else if (user.EmailConfirmed) LogSkipped(attemptId, "already_confirmed");
        else if (pendingRegistrations.IsExpired(user)) LogSkipped(attemptId, "registration_expired");
        else await SendAsync(user, user.Email!, attemptId, cancellationToken);
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
        if (user is null || pendingRegistrations.IsExpired(user)) return new(false);
        var confirmed = await users.ConfirmEmailAsync(user, token);
        return new(confirmed.Succeeded);
    }

    /// <summary>Строит ссылку только от настроенного issuer, а не из входного Host или returnUrl.</summary>
    private async Task SendAsync(ApplicationUser user, string email, string attemptId, CancellationToken cancellationToken)
    {
        var issuer = new Uri(config["Auth:Issuer"] ?? throw new InvalidOperationException("Auth:Issuer is required."));
        var token = await users.GenerateEmailConfirmationTokenAsync(user);
        var code = WebEncoders.Base64UrlEncode(Encoding.UTF8.GetBytes(token));
        var link = QueryHelpers.AddQueryString(new Uri(issuer, "email/confirm").AbsoluteUri,
            new Dictionary<string, string?> { ["userId"] = user.Id, ["code"] = code });
        logger.LogInformation(new EventId(4102, "EmailConfirmationSending"),
            "Email confirmation SMTP submission started; attempt {AttemptId}.", attemptId);
        try
        {
            await sender.SendConfirmationAsync(email, link, attemptId, cancellationToken);
            logger.LogInformation(new EventId(4103, "EmailConfirmationAccepted"),
                "Email confirmation accepted by SMTP server; attempt {AttemptId}.", attemptId);
        }
        catch (EmailDeliveryException error)
        {
            // Только безопасный код, без exception/recipient/link, которые могут содержать секреты.
            logger.LogError(new EventId(4104, "EmailConfirmationFailed"),
                "Email confirmation delivery failed: {DeliveryCode}; stage {SmtpStage}; attempt {AttemptId}.", error.Message, error.Stage, attemptId);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            logger.LogInformation(new EventId(4105, "EmailConfirmationCanceled"),
                "Email confirmation SMTP submission canceled; attempt {AttemptId}.", attemptId);
            throw;
        }
    }

    /// <summary>Связывает события одной попытки случайным ID без email, пользователя или секретов.</summary>
    private string LogRequested(string operation)
    {
        var attemptId = Guid.NewGuid().ToString("N");
        logger.LogInformation(new EventId(4100, "EmailConfirmationRequested"),
            "Email confirmation requested: {Operation}; attempt {AttemptId}.", operation, attemptId);
        return attemptId;
    }

    /// <summary>Показывает оператору причину отсутствия SMTP без изменения общего ответа браузеру.</summary>
    private void LogSkipped(string attemptId, string reason) => logger.LogInformation(new EventId(4101, "EmailConfirmationSkipped"),
        "Email confirmation skipped: {Reason}; attempt {AttemptId}.", reason, attemptId);

    /// <summary>Ограничивает размеры до декодирования и DB-запроса.</summary>
    private static bool ValidShape(EmailConfirmationInput input) => Guid.TryParse(input.UserId, out _) &&
        input.Code is { Length: > 0 and <= 4096 } && input.Code.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_');
}
