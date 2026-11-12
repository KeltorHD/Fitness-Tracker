using System.Diagnostics;
using MailKit;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;

namespace FitnessTracker.Authentication;

/// <summary>Граница отправки писем, не зависящая от Stalwart или другого SMTP-сервиса.</summary>
public interface IAccountEmailSender
{
    /// <summary>Отправляет ссылку подтверждения; не пишет адрес или токен в логи.</summary>
    Task SendConfirmationAsync(string email, string confirmationLink, string attemptId, CancellationToken cancellationToken);
}

/// <summary>Явный режим SMTP без автоматического downgrade STARTTLS.</summary>
public enum SmtpSecurity
{
    /// <summary>Обязательное STARTTLS, обычно порт 587.</summary>
    StartTls,
    /// <summary>TLS сразу при соединении, обычно порт 465.</summary>
    SslOnConnect,
    /// <summary>Явно выбранный plaintext только для доверенной внутренней сети.</summary>
    None
}

/// <summary>Обычные SMTP-настройки через Smtp__* environment keys.</summary>
public sealed class SmtpOptions
{
    /// <summary>Отключённая отправка запрещает новые локальные регистрации, сохраняя прежние аккаунты.</summary>
    public bool Enabled { get; set; }
    /// <summary>DNS-имя/IP SMTP без схемы или порта.</summary>
    public string Host { get; set; } = "";
    /// <summary>Порт SMTP submission.</summary>
    public int Port { get; set; } = 587;
    /// <summary>STARTTLS по умолчанию, без отключения проверки сертификата.</summary>
    public SmtpSecurity Security { get; set; } = SmtpSecurity.StartTls;
    /// <summary>Необязательное имя SMTP пользователя для authenticated submission.</summary>
    public string Username { get; set; } = "";
    /// <summary>Пароль SMTP, передаваемый только почтовому серверу.</summary>
    public string Password { get; set; } = "";
    /// <summary>Mailbox отправителя, разрешённый почтовым сервером.</summary>
    public string FromAddress { get; set; } = "";
    /// <summary>Отображаемое имя отправителя.</summary>
    public string FromName { get; set; } = "FitnessTracker";
    /// <summary>Общий предел времени подключения, аутентификации и отправки.</summary>
    public int TimeoutSeconds { get; set; } = 10;

    /// <summary>Не требует SMTP при выключенной отправке; не включает ошибочные значения в exception.</summary>
    public bool Validate()
    {
        if (!Enabled) return true;
        if (Uri.CheckHostName(Host) == UriHostNameType.Unknown || Host.Any(char.IsWhiteSpace))
            throw new InvalidOperationException("Smtp:Host must be a hostname or IP without a URL scheme.");
        if (Port is < 1 or > 65535 || !Enum.IsDefined(Security) || TimeoutSeconds is < 1 or > 60)
            throw new InvalidOperationException("SMTP port, security mode or timeout is invalid.");
        if (!MailboxAddress.TryParse(FromAddress, out var from) || !from.Address.Contains('@') ||
            from.Address != FromAddress || FromAddress.Any(char.IsControl) ||
            FromName.Length > 100 || FromName.Any(char.IsControl))
            throw new InvalidOperationException("SMTP sender must be a valid mailbox with a single-line display name.");
        if (Username.Length == 0 && Password.Length > 0)
            throw new InvalidOperationException("Smtp:Username is required when a password is provided.");
        return true;
    }
}

/// <summary>Отправляет MIME-письмо через стандартный SMTP; протокольные логи отключены.</summary>
public sealed class SmtpEmailSender(ISmtpClient client, IOptions<SmtpOptions> configured,
    ILogger<SmtpEmailSender> logger) : IAccountEmailSender
{
    /// <summary>Использует MailKit async/TLS и DI-scoped client; локальный SMTP совместим без vendor API.</summary>
    public async Task SendConfirmationAsync(string email, string confirmationLink, string attemptId, CancellationToken cancellationToken)
    {
        var options = configured.Value;
        if (!options.Enabled)
        {
            logger.LogInformation(new EventId(4200, "SmtpDisabled"), "SMTP submission skipped: smtp_disabled; attempt {AttemptId}.", attemptId);
            throw new EmailDeliveryException("smtp_disabled", "configuration");
        }
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(options.TimeoutSeconds));
        using var message = new MimeMessage();
        var stage = "prepare";
        var stageStarted = Stopwatch.GetTimestamp();
        try
        {
            LogStage(4201, stage, "started", attemptId, stageStarted);
            message.From.Add(new MailboxAddress(options.FromName, options.FromAddress));
            message.To.Add(MailboxAddress.Parse(email));
            message.Subject = "Подтвердите электронную почту — FitnessTracker";
            message.Body = ConfirmationEmailTemplate.CreateBody(confirmationLink);
            LogStage(4202, stage, "completed", attemptId, stageStarted);
            var security = options.Security switch
            {
                SmtpSecurity.StartTls => SecureSocketOptions.StartTls,
                SmtpSecurity.SslOnConnect => SecureSocketOptions.SslOnConnect,
                _ => SecureSocketOptions.None
            };
            stage = "connect";
            stageStarted = Stopwatch.GetTimestamp();
            logger.LogInformation(new EventId(4203, "SmtpConnecting"),
                "SMTP connect/TLS started: host {Host}; port {Port}; security {Security}; timeout {TimeoutSeconds} s; attempt {AttemptId}.",
                options.Host, options.Port, options.Security, options.TimeoutSeconds, attemptId);
            await client.ConnectAsync(options.Host, options.Port, security, timeout.Token);
            logger.LogInformation(new EventId(4204, "SmtpConnected"),
                "SMTP connect/TLS completed: secure {IsSecure}; protocol {TlsProtocol}; elapsed {ElapsedMs} ms; attempt {AttemptId}.",
                client.IsSecure, client.IsSecure ? client.SslProtocol : null, ElapsedMs(stageStarted), attemptId);
            stage = "authenticate";
            stageStarted = Stopwatch.GetTimestamp();
            if (options.Username.Length > 0)
            {
                LogStage(4205, stage, "started", attemptId, stageStarted);
                await client.AuthenticateAsync(options.Username, options.Password, timeout.Token);
                LogStage(4206, stage, "completed", attemptId, stageStarted);
            }
            else LogStage(4207, stage, "skipped_no_credentials", attemptId, stageStarted);
            stage = "submit";
            stageStarted = Stopwatch.GetTimestamp();
            LogStage(4208, stage, "started", attemptId, stageStarted);
            await client.SendAsync(message, timeout.Token);
            LogStage(4209, stage, "accepted_by_smtp", attemptId, stageStarted);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw Failure("smtp_timeout", stage, attemptId, stageStarted);
        }
        catch (OperationCanceledException)
        {
            LogStage(4213, stage, "canceled", attemptId, stageStarted);
            throw;
        }
        catch (SslHandshakeException) { throw Failure("smtp_tls_failed", stage, attemptId, stageStarted); }
        catch (MailKit.Security.AuthenticationException) { throw Failure("smtp_auth_failed", stage, attemptId, stageStarted); }
        catch (SmtpCommandException error)
        {
            // Только стандартный код SMTP, не текст ответа с возможным адресом получателя.
            logger.LogInformation(new EventId(4215, "SmtpReplyRejected"),
                "SMTP reply rejected: status {StatusCode}; error {ErrorCode}; stage {Stage}; attempt {AttemptId}.",
                (int)error.StatusCode, error.ErrorCode, stage, attemptId);
            throw Failure("smtp_rejected", stage, attemptId, stageStarted);
        }
        catch (Exception error) when (error is ServiceNotConnectedException or ServiceNotAuthenticatedException)
        { throw Failure("smtp_not_ready", stage, attemptId, stageStarted); }
        catch (NotSupportedException) { throw Failure("smtp_not_supported", stage, attemptId, stageStarted); }
        catch (FormatException) { throw Failure("smtp_invalid_message", stage, attemptId, stageStarted); }
        catch (Exception error) when (error is IOException or System.Net.Sockets.SocketException or SmtpProtocolException)
        {
            throw Failure("smtp_unavailable", stage, attemptId, stageStarted);
        }
        // Сервер уже принял письмо. Ошибка QUIT не должна превращать успешную доставку в повтор.
        stageStarted = Stopwatch.GetTimestamp();
        LogStage(4210, "disconnect", "started", attemptId, stageStarted);
        try
        {
            if (client.IsConnected) await client.DisconnectAsync(true, timeout.Token);
            LogStage(4211, "disconnect", "completed", attemptId, stageStarted);
        }
        catch (Exception error) when (error is IOException or OperationCanceledException or SmtpProtocolException or SmtpCommandException)
        {
            logger.LogInformation(new EventId(4214, "SmtpDisconnectFailed"),
                "SMTP disconnect failed after acceptance: {ErrorType}; elapsed {ElapsedMs} ms; attempt {AttemptId}.",
                error.GetType().Name, ElapsedMs(stageStarted), attemptId);
        }
    }

    /// <summary>Пишет только этап, результат, длительность и серверный ID попытки, без SMTP payload.</summary>
    private void LogStage(int eventId, string stage, string result, string attemptId, long started) =>
        logger.LogInformation(new EventId(eventId, "SmtpStage"),
            "SMTP {Stage}: {Result}; elapsed {ElapsedMs} ms; attempt {AttemptId}.", stage, result, ElapsedMs(started), attemptId);

    /// <summary>Фиксирует безопасный код и этап; исходное exception не передаётся в logger или inner exception.</summary>
    private EmailDeliveryException Failure(string code, string stage, string attemptId, long started)
    {
        logger.LogInformation(new EventId(4212, "SmtpStageFailed"),
            "SMTP {Stage}: failed; code {DeliveryCode}; elapsed {ElapsedMs} ms; attempt {AttemptId}.",
            stage, code, ElapsedMs(started), attemptId);
        return new(code, stage);
    }

    /// <summary>Измеряет этап монотонными часами, независимо от смены системного времени.</summary>
    private static long ElapsedMs(long started) => (long)Stopwatch.GetElapsedTime(started).TotalMilliseconds;
}

/// <summary>Содержит только безопасный код доставки, без адреса, ссылки, SMTP ответа или пароля.</summary>
public sealed class EmailDeliveryException(string code, string stage = "submit") : Exception(code)
{
    /// <summary>Безопасный этап сбоя, заданный транспортом, без данных SMTP-сервера.</summary>
    public string Stage { get; } = stage;
}
