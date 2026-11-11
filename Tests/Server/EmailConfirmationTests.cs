using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using FitLife.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Xunit;
using static FitLife.Server.Tests.CredentialsTests;

namespace FitLife.Server.Tests;

/// <summary>Проверяет подтверждение email через реальные MVC/Identity и изолированный почтовый outbox.</summary>
[Trait("Category", "HTTP")]
public sealed class EmailConfirmationTests
{
    /// <summary>Новый пароль не даёт cookie/OAuth; GET не подтверждает, POST подтверждает без автоматического входа.</summary>
    [Fact]
    public async Task NewPasswordAccountWaitsForExplicitConfirmationAndLoginAsync()
    {
        using var factory = new AuthFactory();
        using var client = await AnonymousClientAsync(factory);
        using var registration = await RegisterAsync(client);
        Assert.StartsWith("/email/verify?", registration.Headers.Location?.OriginalString);
        if (registration.Headers.TryGetValues("Set-Cookie", out var cookies))
            Assert.DoesNotContain(cookies, value => value.StartsWith("__Host-FitnessTrackerAuth="));
        using var accountBefore = await client.GetAsync("/account");
        Assert.Equal(HttpStatusCode.Redirect, accountBefore.StatusCode);
        using var deniedLogin = await LoginAsync(client);
        Assert.StartsWith("/email/verify?", deniedLogin.Headers.Location?.OriginalString);

        var mail = Assert.Single(factory.EmailSender.Messages);
        Assert.Equal("new@example.com", mail.Email);
        Assert.StartsWith("https://localhost/email/confirm?", mail.Link);
        Assert.DoesNotContain("returnUrl", mail.Link);
        using var scanner = await client.GetAsync(mail.Link);
        Assert.Equal(HttpStatusCode.OK, scanner.StatusCode);
        using (var scope = factory.Services.CreateScope())
        {
            var user = await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
            Assert.True(user.EmailConfirmationRequired);
            Assert.False(user.EmailConfirmed);
            Assert.False(await scope.ServiceProvider.GetRequiredService<SignInManager<ApplicationUser>>().CanSignInAsync(user));
        }
        var query = QueryHelpers.ParseQuery(new Uri(mail.Link).Query);
        using var noCsrf = await client.PostAsync("/email/confirm", new FormUrlEncodedContent(new Dictionary<string, string>
        { ["userId"] = query["userId"].ToString(), ["code"] = query["code"].ToString() }));
        Assert.Equal(HttpStatusCode.BadRequest, noCsrf.StatusCode);
        await ConfirmMailAsync(factory, client);
        using var afterConfirmation = await client.GetAsync("/account");
        Assert.Equal(HttpStatusCode.Redirect, afterConfirmation.StatusCode);
        using var login = await LoginAsync(client);
        Assert.Equal("/account", login.Headers.Location?.OriginalString);
        using var account = await client.GetAsync("/account");
        Assert.Equal(HttpStatusCode.OK, account.StatusCode);
    }

    /// <summary>Подтверждение привязано к пользователю, stamp и сроку; испорченная ссылка не меняет аккаунт.</summary>
    [Theory]
    [InlineData("wrong-user")]
    [InlineData("expired")]
    [InlineData("stamp")]
    [InlineData("corrupt")]
    public async Task InvalidConfirmationDoesNotVerifyAccountAsync(string change)
    {
        using var factory = new AuthFactory();
        using var client = await AnonymousClientAsync(factory);
        using var registration = await RegisterAsync(client);
        var mail = Assert.Single(factory.EmailSender.Messages);
        var fields = QueryHelpers.ParseQuery(new Uri(mail.Link).Query).ToDictionary(p => p.Key, p => p.Value.ToString());
        using (var scope = factory.Services.CreateScope())
        {
            var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            var user = await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
            if (change == "wrong-user")
            {
                var other = scope.ServiceProvider.GetRequiredService<EmailAccounts>().NewUser("other@example.com");
                Assert.True((await users.CreateAsync(other)).Succeeded);
                fields["userId"] = other.Id;
            }
            if (change == "expired") scope.ServiceProvider.GetRequiredService<IOptions<DataProtectionTokenProviderOptions>>().Value.TokenLifespan = TimeSpan.FromTicks(-1);
            if (change == "stamp") Assert.True((await users.UpdateSecurityStampAsync(user)).Succeeded);
            if (change == "corrupt") fields["code"] = "invalid_token";
        }
        using var response = await PostAsync(client, mail.Link, "/email/confirm", fields);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("Ссылка недействительна", WebUtility.HtmlDecode(await response.Content.ReadAsStringAsync()));
        using var verification = factory.Services.CreateScope();
        Assert.All(await verification.ServiceProvider.GetRequiredService<AuthDbContext>().Users.ToListAsync(), u => Assert.False(u.EmailConfirmed));
    }

    /// <summary>Одинаковый ответ не раскрывает email, throttle нормализует регистр, SMTP отказ сохраняет профиль.</summary>
    [Fact]
    public async Task ResendIsGenericThrottledAndRecoversFromDeliveryFailureAsync()
    {
        var clock = new EmailClock();
        using var factory = new AuthFactory(clock: clock);
        factory.EmailSender.Fails = true;
        using var client = await AnonymousClientAsync(factory);
        using var registration = await RegisterAsync(client);
        Assert.Equal(HttpStatusCode.Redirect, registration.StatusCode);
        Assert.Empty(factory.EmailSender.Messages);
        factory.EmailSender.Fails = false;
        using var immediate = await PostAsync(client, "/email/verify", "/email/resend", new() { ["email"] = "NEW@EXAMPLE.COM" });
        Assert.Empty(factory.EmailSender.Messages);
        clock.Advance(TimeSpan.FromMinutes(1));
        using var sent = await PostAsync(client, "/email/verify", "/email/resend", new() { ["email"] = "NEW@EXAMPLE.COM" });
        Assert.Single(factory.EmailSender.Messages);
        using var unknown = await PostAsync(client, "/email/verify", "/email/resend", new() { ["email"] = "unknown@example.com" });
        var visible = WebUtility.HtmlDecode(await sent.Content.ReadAsStringAsync());
        Assert.Contains("Если аккаунт ожидает подтверждения", visible);
        Assert.DoesNotContain("new@example.com", visible, StringComparison.OrdinalIgnoreCase);
        // Токены CSRF случайны; остальная страница не раскрывает адрес или статус аккаунта.
        Assert.Equal(WithoutAntiforgery(await sent.Content.ReadAsStringAsync()), WithoutAntiforgery(await unknown.Content.ReadAsStringAsync()));
        await ConfirmMailAsync(factory, client);
        clock.Advance(TimeSpan.FromMinutes(1));
        using var confirmed = await PostAsync(client, "/email/verify", "/email/resend", new() { ["email"] = "new@example.com" });
        Assert.Single(factory.EmailSender.Messages);
        using var scope = factory.Services.CreateScope();
        Assert.True((await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync()).EmailConfirmed);
    }

    /// <summary>SMTP off закрывает новую регистрацию, но не вход старого неподтверждённого локального аккаунта.</summary>
    [Fact]
    public async Task DisabledSmtpPreservesLegacyAccessAndHidesNewRegistrationAsync()
    {
        using var factory = new AuthFactory(providerSettings: new Dictionary<string, string?> { ["Smtp:Enabled"] = "false" });
        using var client = await AnonymousClientAsync(factory);
        using (var scope = factory.Services.CreateScope())
        {
            var user = scope.ServiceProvider.GetRequiredService<EmailAccounts>().NewUser("new@example.com");
            user.EmailConfirmationRequired = false; // Реальное состояние прежних строк после миграции.
            Assert.True((await scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>().CreateAsync(user, "correct-long-password")).Succeeded);
        }
        using var page = await client.GetAsync("/register");
        Assert.DoesNotContain("data-registration", await page.Content.ReadAsStringAsync());
        using var refused = await PostAsync(client, "/login", "/register", new()
        { ["email"] = "blocked@example.com", ["password"] = "correct-long-password", ["confirmPassword"] = "correct-long-password" });
        Assert.Equal(HttpStatusCode.BadRequest, refused.StatusCode);
        using var passkey = await PostAsync(client, "/login", "/passkeys/register/options", new() { ["email"] = "blocked@example.com" });
        Assert.Equal(HttpStatusCode.ServiceUnavailable, passkey.StatusCode);
        using var login = await LoginAsync(client);
        Assert.Equal("/account", login.Headers.Location?.OriginalString);
        using var account = await client.GetAsync("/account");
        Assert.Equal(HttpStatusCode.OK, account.StatusCode);
        Assert.Empty(factory.EmailSender.Messages);
    }

    /// <summary>Passkey подтверждает credential, но не адрес; до подтверждения почты сессия не выдаётся.</summary>
    [Fact]
    public async Task PendingPasskeyAccountCannotSignInAsync()
    {
        using var factory = new AuthFactory();
        using var client = await AnonymousClientAsync(factory);
        using var key = new SoftwarePasskey();
        using var options = await PostAsync(client, "/register", "/passkeys/register/options", new() { ["email"] = "key@example.com" });
        using var registered = await PostAsync(client, "/register", "/passkeys/register", new() { ["credential"] = key.Create(await options.Content.ReadFromJsonAsync<JsonElement>()) });
        Assert.StartsWith("/email/verify?", (await registered.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("redirect").GetString());
        foreach (var corrupt in new[] { true, false })
        {
            using var challenge = await PostAsync(client, "/login", "/passkeys/login/options", new());
            using var result = await PostAsync(client, "/login", "/passkeys/login", new()
            { ["credential"] = key.Assert(await challenge.Content.ReadFromJsonAsync<JsonElement>(), corruptSignature: corrupt) });
            Assert.Equal(corrupt ? HttpStatusCode.BadRequest : HttpStatusCode.OK, result.StatusCode);
            if (!corrupt) Assert.StartsWith("/email/verify?", (await result.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("redirect").GetString());
        }
        using var account = await client.GetAsync("/account");
        Assert.Equal(HttpStatusCode.Redirect, account.StatusCode);
    }

    /// <summary>Отправляет обычную форму регистрации с заведомо синтетическими credentials.</summary>
    private static Task<HttpResponseMessage> RegisterAsync(HttpClient client) => PostAsync(client, "/register", "/register", new()
    { ["email"] = "new@example.com", ["password"] = "correct-long-password", ["confirmPassword"] = "correct-long-password" });

    /// <summary>Выполняет вход того же синтетического пользователя.</summary>
    private static Task<HttpResponseMessage> LoginAsync(HttpClient client) => PostAsync(client, "/login", "/login/password", new()
    { ["email"] = "new@example.com", ["password"] = "correct-long-password" });

    /// <summary>Исключает только случайное значение antiforgery при сравнении публичных ответов.</summary>
    private static string WithoutAntiforgery(string html) => Regex.Replace(html,
        "name=\"__RequestVerificationToken\"[^>]*value=\"[^\"]+\"", "name=\"__RequestVerificationToken\" value=\"[token]\"");

    /// <summary>Подтверждает синтетическое письмо через реальный antiforgery POST, без автоматического входа.</summary>
    internal static async Task ConfirmMailAsync(AuthFactory factory, HttpClient client)
    {
        var mail = Assert.Single(factory.EmailSender.Messages);
        var query = QueryHelpers.ParseQuery(new Uri(mail.Link).Query);
        using var result = await PostAsync(client, mail.Link, "/email/confirm", query.ToDictionary(p => p.Key, p => p.Value.ToString()));
        Assert.Contains("Адрес подтверждён", WebUtility.HtmlDecode(await result.Content.ReadAsStringAsync()));
    }

    /// <summary>Меняет время throttle без ожидания реальной минуты.</summary>
    private sealed class EmailClock : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.UtcNow;
        /// <summary>Возвращает детерминированное время для лимита отправки.</summary>
        public override DateTimeOffset GetUtcNow() => _now;
        /// <summary>Продвигает время только в текущем изолированном тесте.</summary>
        internal void Advance(TimeSpan delta) => _now += delta;
    }
}
