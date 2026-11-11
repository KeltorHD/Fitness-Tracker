using System.Net;
using FitLife.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Npgsql;
using Xunit;
using static FitLife.Server.Tests.CredentialsTests;

namespace FitLife.Server.Tests;

/// <summary>Проверяет понятные ошибки регистрации, безопасные console logs и продолжение прежнего входа.</summary>
[Trait("Category", "HTTP")]
public sealed class RegistrationDiagnosticsTests
{
    /// <summary>Повтор не меняет аккаунт/пароль; оператор видит конфликт, пользователь может войти и запросить письмо.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task ExistingAccountHasSafeDiagnosticsAndWorkingRecoveryAsync(bool confirmed)
    {
        using var logs = new TestEmailLogs(typeof(PasswordService).FullName);
        using var factory = new AuthFactory(providerSettings: logs.Settings);
        using var client = await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        string userName;
        using (var scope = factory.Services.CreateScope())
        {
            var accounts = scope.ServiceProvider.GetRequiredService<EmailAccounts>();
            var user = accounts.NewUser("registered@example.com");
            user.EmailConfirmed = confirmed;
            userName = user.UserName!;
            Assert.True((await scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>()
                .CreateAsync(user, "private-original-password")).Succeeded);
        }
        using var response = await PostAsync(client, "/register", "/register", new()
        {
            ["email"] = "REGISTERED@example.com",
            ["password"] = "private-new-password",
            ["confirmPassword"] = "private-new-password",
            ["returnUrl"] = "https://untrusted.example.com/private"
        });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var html = WebUtility.HtmlDecode(await response.Content.ReadAsStringAsync());
        Assert.Contains("Если вы уже регистрировались, войдите или запросите новое письмо подтверждения.", html);
        Assert.Contains("href=\"/login?returnUrl=%2Faccount\"", html);
        Assert.Contains("href=\"/email/verify?returnUrl=%2Faccount\"", html);
        Assert.DoesNotContain("private-new-password", html);
        Assert.DoesNotContain("untrusted.example.com", html);
        var rejected = AssertAttempt(logs, 4301);
        Assert.Equal("account_conflict", rejected.Fields["Reason"]);
        Assert.Equal("DuplicateUserName", rejected.Fields["IdentityCodes"]);
        Assert.Empty(factory.EmailSender.Messages);
        AssertNoSecrets(logs, "registered@example.com", "REGISTERED@example.com", "private-original-password", "private-new-password", userName);
        using (var scope = factory.Services.CreateScope())
        {
            var user = await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
            var manager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            Assert.True(await manager.CheckPasswordAsync(user, "private-original-password"));
            Assert.False(await manager.CheckPasswordAsync(user, "private-new-password"));
        }
        using var login = await PostAsync(client, "/login", "/login/password", new()
        { ["email"] = "registered@example.com", ["password"] = "private-original-password" });
        Assert.Equal(HttpStatusCode.Redirect, login.StatusCode);
        if (confirmed) Assert.Equal("/account", login.Headers.Location?.OriginalString);
        else
        {
            Assert.StartsWith("/email/verify?", login.Headers.Location?.OriginalString);
            using var resend = await PostAsync(client, "/email/verify", "/email/resend", new()
            { ["email"] = "registered@example.com" });
            Assert.Equal(HttpStatusCode.OK, resend.StatusCode);
            Assert.Single(factory.EmailSender.Messages);
        }
    }

    /// <summary>Формат email, длина, совпадение и уникальные символы имеют отдельные безопасные ошибки.</summary>
    [Theory]
    [InlineData("invalid-address", "private-valid-password", "private-valid-password", "invalid_email", "Укажите корректный email.")]
    [InlineData("new@example.com", "short", "short", "password_length", "Пароль должен содержать от 12 до 128 символов.")]
    [InlineData("new@example.com", "private-valid-password", "private-other-password", "password_mismatch", "Пароли не совпадают.")]
    [InlineData("new@example.com", "aaaaaaaaaaaa", "aaaaaaaaaaaa", "password_policy", "Пароль должен содержать минимум 4 разных символа.")]
    public async Task ValidationErrorsExplainTheRequiredCorrectionAsync(string email, string password,
        string confirmation, string reason, string message)
    {
        using var logs = new TestEmailLogs(typeof(PasswordService).FullName);
        using var factory = new AuthFactory(providerSettings: logs.Settings);
        using var client = await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using var response = await PostAsync(client, "/register", "/register", new()
        { ["email"] = email, ["password"] = password, ["confirmPassword"] = confirmation });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var html = WebUtility.HtmlDecode(await response.Content.ReadAsStringAsync());
        Assert.Contains(message, html);
        Assert.DoesNotContain(password, html);
        Assert.DoesNotContain(confirmation, html);
        Assert.Equal(reason, AssertAttempt(logs, 4301).Fields["Reason"]);
        AssertNoSecrets(logs, email, password, confirmation);
        Assert.Empty(factory.EmailSender.Messages);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.ToListAsync());
    }

    /// <summary>Сервер отклоняет пароль сверх максимума даже при обходе HTML maxlength.</summary>
    [Fact]
    public async Task OversizedPasswordHasAVisibleLengthErrorAsync()
    {
        using var factory = new AuthFactory();
        using var client = await AnonymousClientAsync(factory);
        var password = new string('x', 129);
        using var response = await PostAsync(client, "/register", "/register", new()
        { ["email"] = "new@example.com", ["password"] = password, ["confirmPassword"] = password });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains("Пароль должен содержать от 12 до 128 символов.", WebUtility.HtmlDecode(await response.Content.ReadAsStringAsync()));
        Assert.Empty(factory.EmailSender.Messages);
    }

    /// <summary>Даже нестандартный validator/DB exception не переносит приватные Code/Description в сообщение или logs.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task PrivateIdentityDetailsAreNotLoggedOrRenderedAsync(bool databaseConflict)
    {
        using var logs = new TestEmailLogs(typeof(PasswordService).FullName);
        using var baseFactory = new AuthFactory(providerSettings: logs.Settings);
        using var factory = baseFactory.WithWebHostBuilder(builder => builder.ConfigureServices(services =>
            services.AddSingleton<IUserValidator<ApplicationUser>>(new PrivateFailureValidator(databaseConflict))));
        using var client = factory.CreateClient(new WebApplicationFactoryClientOptions
        { BaseAddress = new Uri("https://localhost"), AllowAutoRedirect = false });
        using (var scope = factory.Services.CreateScope())
            await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Database.EnsureCreatedAsync();
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using var response = await PostAsync(client, "/register", "/register", new()
        { ["email"] = "new@example.com", ["password"] = "private-valid-password", ["confirmPassword"] = "private-valid-password" });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var html = WebUtility.HtmlDecode(await response.Content.ReadAsStringAsync());
        Assert.DoesNotContain("private-validator-data", html);
        Assert.DoesNotContain("private-valid-password", html);
        var rejected = AssertAttempt(logs, 4301);
        Assert.Equal(databaseConflict ? "account_conflict" : "identity_rejected", rejected.Fields["Reason"]);
        Assert.Equal(databaseConflict ? "none" : "unknown_identity_error", rejected.Fields["IdentityCodes"]);
        Assert.Equal(databaseConflict ? "23505" : "none", rejected.Fields["DatabaseCode"]);
        AssertNoSecrets(logs, "new@example.com", "private-valid-password", "private-validator-data");
    }

    /// <summary>При выключенной доставке ручной POST тоже даёт понятный отказ и не создаёт аккаунт.</summary>
    [Fact]
    public async Task DisabledSmtpExplainsUnavailableRegistrationAsync()
    {
        using var logs = new TestEmailLogs(typeof(PasswordService).FullName);
        var settings = logs.Settings.ToDictionary(item => item.Key, item => item.Value);
        settings["Smtp:Enabled"] = "false";
        using var factory = new AuthFactory(providerSettings: settings);
        using var client = await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using var response = await PostAsync(client, "/login", "/register", new()
        { ["email"] = "new@example.com", ["password"] = "private-valid-password", ["confirmPassword"] = "private-valid-password" });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains("Регистрация по email временно недоступна.", WebUtility.HtmlDecode(await response.Content.ReadAsStringAsync()));
        Assert.Equal("smtp_disabled", AssertAttempt(logs, 4301).Fields["Reason"]);
        Assert.Empty(factory.EmailSender.Messages);
    }

    /// <summary>Успешное создание видно до SMTP и не выдаёт сессию до проверки почты.</summary>
    [Fact]
    public async Task SuccessfulRegistrationLogsCreationAndRequestsConfirmationAsync()
    {
        using var logs = new TestEmailLogs(typeof(PasswordService).FullName);
        using var factory = new AuthFactory(providerSettings: logs.Settings);
        using var client = await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using var response = await PostAsync(client, "/register", "/register", new()
        { ["email"] = "new@example.com", ["password"] = "private-valid-password", ["confirmPassword"] = "private-valid-password" });
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.StartsWith("/email/verify?", response.Headers.Location?.OriginalString);
        AssertAttempt(logs, 4302);
        var mail = Assert.Single(factory.EmailSender.Messages);
        AssertNoSecrets(logs, "new@example.com", "private-valid-password", mail.Link);
        using var account = await client.GetAsync("/account");
        Assert.Equal(HttpStatusCode.Redirect, account.StatusCode);
    }

    /// <summary>Shipped Information filter пропускает начало и один результат с общим случайным ID.</summary>
    private static TestEmailLogs.Entry AssertAttempt(TestEmailLogs logs, int expectedResult)
    {
        var entries = logs.Entries.ToArray();
        Assert.Equal(new[] { 4300, expectedResult }, entries.Select(item => item.EventId));
        Assert.All(entries, item => Assert.Equal(LogLevel.Information, item.Level));
        Assert.True(Guid.TryParseExact(entries[0].Fields["AttemptId"], "N", out _));
        Assert.Single(entries.Select(item => item.Fields["AttemptId"]).Distinct());
        return entries[1];
    }

    /// <summary>Проверяет также raw structured state и отсутствие самого exception с приватными полями.</summary>
    private static void AssertNoSecrets(TestEmailLogs logs, params string[] secrets)
    {
        foreach (var entry in logs.Entries)
        {
            var text = entry.Message + " " + string.Join(" ", entry.Fields.Values);
            foreach (var secret in secrets) Assert.DoesNotContain(secret, text);
            Assert.Null(entry.Exception);
        }
    }

    /// <summary>Имитирует отказ validator и конфликт PostgreSQL с заведомо приватным текстом.</summary>
    private sealed class PrivateFailureValidator(bool databaseConflict) : IUserValidator<ApplicationUser>
    {
        /// <summary>Проверяет allowlist кодов и обработку 23505 без реального SQL-конфликта.</summary>
        public Task<IdentityResult> ValidateAsync(UserManager<ApplicationUser> manager, ApplicationUser user)
        {
            if (databaseConflict)
                throw new DbUpdateException("private-validator-data", new PostgresException("private-validator-data", "ERROR", "ERROR", "23505"));
            return Task.FromResult(IdentityResult.Failed(new IdentityError
            { Code = "private-validator-data", Description = "private-validator-data " + user.Email }));
        }
    }
}
