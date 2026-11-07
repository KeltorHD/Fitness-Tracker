using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;

namespace FitnessTracker.Authentication;

/// <summary>Граница отправки писем, не зависящая от Stalwart или другого SMTP-сервиса.</summary>
public interface IAccountEmailSender
{
    /// <summary>Отправляет ссылку подтверждения; не пишет адрес или токен в логи.</summary>
    Task SendConfirmationAsync(string email, string confirmationLink, CancellationToken cancellationToken);
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
public sealed class SmtpEmailSender(ISmtpClient client, IOptions<SmtpOptions> configured) : IAccountEmailSender
{
    /// <summary>Использует MailKit async/TLS и DI-scoped client; локальный SMTP совместим без vendor API.</summary>
    public async Task SendConfirmationAsync(string email, string confirmationLink, CancellationToken cancellationToken)
    {
        var options = configured.Value;
        if (!options.Enabled) throw new EmailDeliveryException("smtp_disabled");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(options.TimeoutSeconds));
        using var message = new MimeMessage();
        message.From.Add(new MailboxAddress(options.FromName, options.FromAddress));
        message.To.Add(MailboxAddress.Parse(email));
        message.Subject = "Подтвердите электронную почту — FitnessTracker";
        var link = System.Net.WebUtility.HtmlEncode(confirmationLink);
        message.Body = new BodyBuilder
        {
            TextBody = $"Подтвердите адрес электронной почты для FitnessTracker:\n\n{confirmationLink}\n\nСсылка действует 2 часа. Если вы не создавали аккаунт, проигнорируйте письмо.",
            HtmlBody = $"<html lang=\"ru\"><body><h1>Подтвердите электронную почту</h1><p>Вы создали аккаунт FitnessTracker.</p><p><a href=\"{link}\">Подтвердить адрес</a></p><p>Ссылка действует 2 часа. Если вы не создавали аккаунт, проигнорируйте письмо.</p></body></html>"
        }.ToMessageBody();
        try
        {
            var security = options.Security switch
            {
                SmtpSecurity.StartTls => SecureSocketOptions.StartTls,
                SmtpSecurity.SslOnConnect => SecureSocketOptions.SslOnConnect,
                _ => SecureSocketOptions.None
            };
            await client.ConnectAsync(options.Host, options.Port, security, timeout.Token);
            if (options.Username.Length > 0)
                await client.AuthenticateAsync(options.Username, options.Password, timeout.Token);
            await client.SendAsync(message, timeout.Token);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new EmailDeliveryException("smtp_timeout");
        }
        catch (SslHandshakeException) { throw new EmailDeliveryException("smtp_tls_failed"); }
        catch (MailKit.Security.AuthenticationException) { throw new EmailDeliveryException("smtp_auth_failed"); }
        catch (SmtpCommandException) { throw new EmailDeliveryException("smtp_rejected"); }
        catch (Exception error) when (error is IOException or System.Net.Sockets.SocketException or SmtpProtocolException)
        {
            throw new EmailDeliveryException("smtp_unavailable");
        }
        // Сервер уже принял письмо. Ошибка QUIT не должна превращать успешную доставку в повтор.
        try { if (client.IsConnected) await client.DisconnectAsync(true, timeout.Token); }
        catch (Exception error) when (error is IOException or OperationCanceledException or SmtpProtocolException or SmtpCommandException) { return; }
    }
}

/// <summary>Содержит только безопасный код доставки, без адреса, ссылки, SMTP ответа или пароля.</summary>
public sealed class EmailDeliveryException(string code) : Exception(code);
