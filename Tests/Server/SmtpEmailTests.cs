using System.Net;
using System.Text;
using FitnessTracker.Authentication;
using MailKit;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет SMTP TLS, MIME, таймауты и безопасные ошибки без сети и реального почтового сервиса.</summary>
[Trait("Category", "Unit")]
public sealed class SmtpEmailTests
{
    /// <summary>Каждый явный режим передаётся MailKit без downgrade; письмо содержит текст и HTML-ссылку.</summary>
    [Theory]
    [InlineData(SmtpSecurity.StartTls, SecureSocketOptions.StartTls)]
    [InlineData(SmtpSecurity.SslOnConnect, SecureSocketOptions.SslOnConnect)]
    [InlineData(SmtpSecurity.None, SecureSocketOptions.None)]
    public async Task SendsMimeUsingConfiguredTransportAsync(SmtpSecurity security, SecureSocketOptions expected)
    {
        using var client = new SmtpCapture();
        var options = Configured();
        options.Security = security;
        var sender = new SmtpEmailSender(client, Options.Create(options));
        const string link = "https://auth.example.com/email/confirm?userId=synthetic&code=synthetic_token";
        await sender.SendConfirmationAsync("recipient@example.com", link, CancellationToken.None);
        Assert.Equal(("smtp.example.com", 587, expected), client.Connection);
        Assert.Equal(("smtp-user", "smtp-private-password"), client.Credentials);
        Assert.Equal("fitness@example.com", client.From);
        Assert.Equal("recipient@example.com", client.To);
        Assert.Contains(link, client.Text);
        Assert.Contains("&amp;code=", client.Html);
        Assert.DoesNotContain(options.Password, client.Text);
        Assert.DoesNotContain(options.Password, client.Html);
        Assert.True(client.QuitSent);
        Assert.Null(client.ServerCertificateValidationCallback);
    }

    /// <summary>Ни ответ SMTP с адресом, ни исходное exception не выходят за транспортную границу.</summary>
    [Theory]
    [InlineData("io", "smtp_unavailable")]
    [InlineData("auth", "smtp_auth_failed")]
    [InlineData("reject", "smtp_rejected")]
    [InlineData("timeout", "smtp_timeout")]
    public async Task TransportFailuresHaveOnlySafeCodeAsync(string failure, string code)
    {
        using var client = new SmtpCapture { Failure = failure };
        var sender = new SmtpEmailSender(client, Options.Create(Configured()));
        var error = await Assert.ThrowsAsync<EmailDeliveryException>(() => sender.SendConfirmationAsync(
            "recipient@example.com", "https://auth.example.com/email/confirm?code=private", CancellationToken.None));
        Assert.Equal(code, error.Message);
        Assert.Null(error.InnerException);
        Assert.DoesNotContain("recipient", error.ToString());
    }

    /// <summary>Отмена вызывающего кода сохраняется; ошибка QUIT после принятия письма не приводит к повтору.</summary>
    [Fact]
    public async Task CancellationAndDisconnectHaveDistinctOutcomesAsync()
    {
        using var client = new SmtpCapture();
        var sender = new SmtpEmailSender(client, Options.Create(Configured()));
        using var canceled = new CancellationTokenSource();
        canceled.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => sender.SendConfirmationAsync(
            "recipient@example.com", "https://auth.example.com/", canceled.Token));
        client.Failure = "disconnect";
        await sender.SendConfirmationAsync("recipient@example.com", "https://auth.example.com/", CancellationToken.None);
        Assert.NotNull(client.Text);
    }

    /// <summary>Плохие настройки отвергаются без вывода их значений; отключённый SMTP не требует секретов.</summary>
    [Theory]
    [InlineData("host")]
    [InlineData("port")]
    [InlineData("mode")]
    [InlineData("from")]
    [InlineData("name")]
    [InlineData("timeout")]
    [InlineData("username")]
    public void InvalidConfigurationFailsWithoutSecrets(string field)
    {
        var options = Configured();
        switch (field)
        {
            case "host": options.Host = "https://private-secret.example.com/"; break;
            case "port": options.Port = 0; break;
            case "mode": options.Security = (SmtpSecurity)99; break;
            case "from": options.FromAddress = "secret@example.com\r\nBcc: target@example.com"; break;
            case "name": options.FromName = "private-secret\r\n"; break;
            case "timeout": options.TimeoutSeconds = 0; break;
            case "username": options.Username = ""; break;
        }
        var error = Assert.Throws<InvalidOperationException>(() => options.Validate());
        Assert.DoesNotContain("private-secret", error.Message);
        Assert.DoesNotContain(options.Password, error.Message);
        options.Enabled = false;
        Assert.True(options.Validate());
    }

    /// <summary>Даёт синтетический SMTP submission без связи с пользовательским развёртыванием.</summary>
    private static SmtpOptions Configured() => new()
    {
        Enabled = true,
        Host = "smtp.example.com",
        FromAddress = "fitness@example.com",
        Username = "smtp-user",
        Password = "smtp-private-password"
    };

    /// <summary>Подменяет virtual transport MailKit, сохраняя MIME-сборку и маршрутизацию его overloads.</summary>
    private sealed class SmtpCapture : SmtpClient
    {
        /// <summary>Выбранный вид отказа.</summary>
        internal string? Failure { get; set; }
        /// <summary>Принятые параметры соединения.</summary>
        internal (string, int, SecureSocketOptions) Connection { get; private set; }
        /// <summary>Синтетические SMTP credentials.</summary>
        internal (string?, string?) Credentials { get; private set; }
        /// <summary>Mailbox отправителя из MIME.</summary>
        internal string? From { get; private set; }
        /// <summary>Mailbox получателя из MIME.</summary>
        internal string? To { get; private set; }
        /// <summary>Простая текстовая часть письма.</summary>
        internal string? Text { get; private set; }
        /// <summary>HTML-часть с escaped ссылкой.</summary>
        internal string? Html { get; private set; }
        /// <summary>Признак отправки QUIT.</summary>
        internal bool QuitSent { get; private set; }
        /// <summary>Позволяет sender корректно завершить синтетическое соединение.</summary>
        public override bool IsConnected => Connection.Item1 is not null && !QuitSent;

        /// <summary>Учитывает отмену и фиксирует строгий выбор TLS.</summary>
        public override Task ConnectAsync(string host, int port, SecureSocketOptions options, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (Failure == "io") throw new IOException("recipient@example.com private SMTP response");
            if (Failure == "timeout") throw new OperationCanceledException();
            Connection = (host, port, options);
            return Task.CompletedTask;
        }

        /// <summary>Фиксирует параметры overload стандартной SMTP аутентификации.</summary>
        public override Task AuthenticateAsync(Encoding encoding, ICredentials credentials, CancellationToken cancellationToken = default)
        {
            if (Failure == "auth") throw new MailKit.Security.AuthenticationException("private SMTP password response");
            var credential = credentials.GetCredential(new Uri("smtp://smtp.example.com"), "PLAIN")
                ?? throw new InvalidOperationException("Fixture credentials are required.");
            Credentials = (credential.UserName, credential.Password);
            return Task.CompletedTask;
        }

        /// <summary>Считывает части письма до освобождения MIME-объекта.</summary>
        public override Task<string> SendAsync(FormatOptions options, MimeMessage message, CancellationToken cancellationToken = default, ITransferProgress? progress = null)
        {
            if (Failure == "reject") throw new SmtpCommandException(SmtpErrorCode.MessageNotAccepted, SmtpStatusCode.MailboxUnavailable, "private SMTP response");
            From = message.From.Mailboxes.Single().Address;
            To = message.To.Mailboxes.Single().Address;
            Text = message.TextBody;
            Html = message.HtmlBody;
            return Task.FromResult("accepted");
        }

        /// <summary>Имитирует успешный QUIT либо потерю соединения после принятия письма.</summary>
        public override Task DisconnectAsync(bool quit, CancellationToken cancellationToken = default)
        {
            QuitSent = true;
            if (Failure == "disconnect") throw new IOException("private QUIT response");
            return Task.CompletedTask;
        }
    }
}
