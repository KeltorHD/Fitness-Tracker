using FitLife.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Xunit;
using static FitLife.Server.Tests.CredentialsTests;

namespace FitLife.Server.Tests;

/// <summary>Проверяет видимость результата отправки и причин пропуска без утечки email/токенов в console logs.</summary>
[Trait("Category", "HTTP")]
public sealed class EmailDiagnosticsTests
{
    /// <summary>Новая регистрация показывает запрос и принятие SMTP; причины resend видны только оператору.</summary>
    [Fact]
    public async Task RegistrationAndResendExposeSafeConsoleOutcomesAsync()
    {
        using var logs = new TestEmailLogs();
        using var factory = new AuthFactory(providerSettings: logs.Settings);
        using var client = await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using var created = await PostAsync(client, "/register", "/register", new()
        { ["email"] = "new@example.com", ["password"] = "private-password-123", ["confirmPassword"] = "private-password-123" });
        var first = logs.Entries.ToArray();
        Assert.Equal(new[] { 4100, 4102, 4103 }, first.Select(item => item.EventId));
        Assert.Single(first.Select(item => item.Fields["AttemptId"]).Distinct());
        Assert.True(Guid.TryParseExact(first[0].Fields["AttemptId"], "N", out _));
        Assert.All(first, item => Assert.Equal(LogLevel.Information, item.Level));
        using var throttled = await PostAsync(client, "/email/verify", "/email/resend", new() { ["email"] = "new@example.com" });
        using var unknown = await PostAsync(client, "/email/verify", "/email/resend", new() { ["email"] = "unknown@example.com" });
        using var invalid = await PostAsync(client, "/email/verify", "/email/resend", new() { ["email"] = "invalid" });
        using (var scope = factory.Services.CreateScope())
        {
            var accounts = scope.ServiceProvider.GetRequiredService<EmailAccounts>();
            var manager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            foreach (var legacy in new[] { false, true })
            {
                var address = legacy ? "legacy@example.com" : "confirmed@example.com";
                var user = accounts.NewUser(address);
                user.EmailConfirmationRequired = !legacy;
                user.EmailConfirmed = !legacy;
                Assert.True((await manager.CreateAsync(user)).Succeeded);
                using var response = await PostAsync(client, "/email/verify", "/email/resend", new() { ["email"] = address });
            }
        }
        var reasons = logs.Entries.Where(item => item.EventId == 4101).Select(item => item.Fields["Reason"]).ToArray();
        Assert.Equal(new[] { "throttled", "account_not_found", "invalid_address", "already_confirmed", "confirmation_not_required" }, reasons);
        var mail = Assert.Single(factory.EmailSender.Messages);
        Assert.Equal(first[0].Fields["AttemptId"], mail.AttemptId);
        AssertNoSecrets(logs, mail.Link);
    }

    /// <summary>SMTP failure показывает безопасный код с общим attempt ID и не создаёт ложного accepted.</summary>
    [Fact]
    public async Task FailedSubmissionLogsFailureWithoutAcceptanceAsync()
    {
        using var logs = new TestEmailLogs();
        using var factory = new AuthFactory(providerSettings: logs.Settings);
        factory.EmailSender.Fails = true;
        using var client = await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using var created = await PostAsync(client, "/register", "/register", new()
        { ["email"] = "new@example.com", ["password"] = "private-password-123", ["confirmPassword"] = "private-password-123" });
        Assert.Equal(new[] { 4100, 4102, 4104 }, logs.Entries.Select(item => item.EventId));
        var error = Assert.Single(logs.Entries, item => item.Level == LogLevel.Error);
        Assert.Equal("smtp_unavailable", error.Fields["DeliveryCode"]);
        Assert.Equal("submit", error.Fields["SmtpStage"]);
        Assert.Single(logs.Entries.Select(item => item.Fields["AttemptId"]).Distinct());
        AssertNoSecrets(logs);
    }

    /// <summary>Отключённый SMTP также оставляет явную причину в console, сохраняя общий browser ответ.</summary>
    [Fact]
    public async Task DisabledSmtpLogsSkippedSubmissionAsync()
    {
        using var logs = new TestEmailLogs();
        var settings = logs.Settings.ToDictionary(item => item.Key, item => item.Value);
        settings["Smtp:Enabled"] = "false";
        using var factory = new AuthFactory(providerSettings: settings);
        using var client = await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using var response = await PostAsync(client, "/login", "/email/resend", new() { ["email"] = "new@example.com" });
        Assert.Equal(new[] { 4100, 4101 }, logs.Entries.Select(item => item.EventId));
        Assert.Equal("smtp_disabled", logs.Entries.Last().Fields["Reason"]);
        Assert.Empty(factory.EmailSender.Messages);
        AssertNoSecrets(logs);
    }

    /// <summary>Проверяет raw structured fields, которые мог бы получить любой ILogger provider.</summary>
    private static void AssertNoSecrets(TestEmailLogs logs, string? confirmationLink = null)
    {
        foreach (var item in logs.Entries)
        {
            var text = item.Message + " " + string.Join(" ", item.Fields.Values);
            foreach (var secret in new[] { "new@example.com", "unknown@example.com", "confirmed@example.com", "legacy@example.com", "private-password-123", "userId=", "code=" })
                Assert.DoesNotContain(secret, text);
            if (confirmationLink is not null)
            {
                Assert.DoesNotContain(confirmationLink, text);
                foreach (var value in QueryHelpers.ParseQuery(new Uri(confirmationLink).Query).Values)
                    Assert.DoesNotContain(value.ToString(), text);
            }
            Assert.Null(item.Exception);
        }
    }
}
