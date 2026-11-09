using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FitnessTracker.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using static FitnessTracker.Server.Tests.CredentialsTests;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет фиксированный срок регистрации, очистку и повтор без реальных писем или ожидания часов.</summary>
[Trait("Category", "HTTP")]
public sealed class PendingRegistrationTests
{
    /// <summary>До границы подтверждение разрешено, с двух часов запрещено независимо от свежести токена Identity.</summary>
    [Theory]
    [InlineData(119, true)]
    [InlineData(120, false)]
    [InlineData(121, false)]
    public async Task ConfirmationEnforcesRegistrationDeadlineAsync(int minutes, bool expected)
    {
        var clock = new RegistrationClock();
        using var factory = new AuthFactory(clock: clock);
        using var client = await AnonymousClientAsync(factory);
        using var registered = await RegisterAsync(client);
        var mail = Assert.Single(factory.EmailSender.Messages);
        clock.Advance(TimeSpan.FromMinutes(minutes));
        using var confirmed = await ConfirmAsync(client, mail.Link);
        var html = WebUtility.HtmlDecode(await confirmed.Content.ReadAsStringAsync());
        Assert.Contains(expected ? "Адрес подтверждён" : "Ссылка недействительна", html);
        using var scope = factory.Services.CreateScope();
        var user = await scope.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync();
        Assert.Equal(expected, user.EmailConfirmed);
        clock.Advance(TimeSpan.FromDays(1));
        Assert.Equal(expected ? 0 : 1, await scope.ServiceProvider.GetRequiredService<PendingRegistrationCleanup>().DeleteBatchAsync(default));
    }

    /// <summary>Повтор за минуту до конца не продлевает регистрацию; после границы SMTP не вызывается.</summary>
    [Fact]
    public async Task ResendDoesNotExtendRegistrationOrSendAfterExpiryAsync()
    {
        var clock = new RegistrationClock();
        using var logs = new TestEmailLogs();
        using var factory = new AuthFactory(clock: clock, providerSettings: logs.Settings);
        using var client = await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using var registered = await RegisterAsync(client);
        clock.Advance(TimeSpan.FromMinutes(119));
        using var resent = await PostAsync(client, "/email/verify", "/email/resend", new() { ["email"] = "new@example.com" });
        Assert.Equal(2, factory.EmailSender.Messages.Count);
        clock.Advance(TimeSpan.FromMinutes(1));
        using var expired = await PostAsync(client, "/email/verify", "/email/resend", new() { ["email"] = "new@example.com" });
        Assert.Equal(2, factory.EmailSender.Messages.Count);
        Assert.Equal("registration_expired", logs.Entries.Last(entry => entry.EventId == 4101).Fields["Reason"]);
        using var confirmed = await ConfirmAsync(client, factory.EmailSender.Messages.Last().Link);
        Assert.Contains("Ссылка недействительна", WebUtility.HtmlDecode(await confirmed.Content.ReadAsStringAsync()));
    }

    /// <summary>Регистрация сразу освобождает просроченный email; старые пароль/passkey и ссылка не переходят новому ID.</summary>
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task RegistrationReplacesExpiredAccountWithNewIdentityAsync(bool passkey)
    {
        var clock = new RegistrationClock();
        using var factory = new AuthFactory(clock: clock);
        using var client = await AnonymousClientAsync(factory);
        using var key = new SoftwarePasskey();
        if (passkey)
        {
            using var options = await PostAsync(client, "/register", "/passkeys/register/options", new() { ["email"] = "new@example.com" });
            using var registered = await PostAsync(client, "/register", "/passkeys/register", new()
            { ["credential"] = key.Create(await options.Content.ReadFromJsonAsync<JsonElement>()) });
            Assert.Equal(HttpStatusCode.OK, registered.StatusCode);
        }
        else { using var registered = await RegisterAsync(client); }
        var oldMail = Assert.Single(factory.EmailSender.Messages);
        string oldId;
        using (var scope = factory.Services.CreateScope())
        {
            var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            oldId = (await database.Users.SingleAsync()).Id;
            database.UserClaims.Add(new IdentityUserClaim<string> { UserId = oldId, ClaimType = "fixture", ClaimValue = "private" });
            await database.SaveChangesAsync();
        }
        clock.Advance(TimeSpan.FromHours(2));
        using var replacement = await RegisterAsync(client, "NEW@example.com", "private-replacement-password");
        Assert.Equal(HttpStatusCode.Redirect, replacement.StatusCode);
        Assert.Equal(2, factory.EmailSender.Messages.Count);
        using (var scope = factory.Services.CreateScope())
        {
            var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            var user = await database.Users.SingleAsync();
            Assert.NotEqual(oldId, user.Id);
            Assert.Equal(clock.GetUtcNow(), user.CreatedAt);
            Assert.False(user.EmailConfirmed);
            Assert.Empty(await database.UserPasskeys.ToListAsync());
            Assert.Empty(await database.UserClaims.ToListAsync());
            var manager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
            Assert.True(await manager.CheckPasswordAsync(user, "private-replacement-password"));
            Assert.False(await manager.CheckPasswordAsync(user, "private-original-password"));
        }
        using var stale = await ConfirmAsync(client, oldMail.Link);
        Assert.Contains("Ссылка недействительна", WebUtility.HtmlDecode(await stale.Content.ReadAsStringAsync()));
        using var verification = factory.Services.CreateScope();
        Assert.False((await verification.ServiceProvider.GetRequiredService<AuthDbContext>().Users.SingleAsync()).EmailConfirmed);
    }

    /// <summary>Очистка сохраняет свежие, подтверждённые, legacy и внешние аккаунты.</summary>
    [Fact]
    public async Task CleanupOnlyDeletesExpiredRequiredUnconfirmedAccountsAsync()
    {
        var clock = new RegistrationClock();
        using var factory = new AuthFactory(clock: clock);
        using var client = await AnonymousClientAsync(factory);
        using var scope = factory.Services.CreateScope();
        var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        database.Users.AddRange(
            User("expired", clock.GetUtcNow().AddHours(-2)),
            User("fresh", clock.GetUtcNow().AddMinutes(-119)),
            User("confirmed", clock.GetUtcNow().AddYears(-1), confirmed: true),
            User("legacy", clock.GetUtcNow().AddYears(-1), required: false),
            User("external", clock.GetUtcNow().AddYears(-1), required: false));
        await database.SaveChangesAsync();
        database.UserLogins.Add(new IdentityUserLogin<string> { UserId = "external", LoginProvider = "Google", ProviderKey = "fixture" });
        await database.SaveChangesAsync();
        var cleanup = scope.ServiceProvider.GetRequiredService<PendingRegistrationCleanup>();
        Assert.Equal(1, await cleanup.DeleteBatchAsync(default));
        Assert.Equal(0, await cleanup.DeleteBatchAsync(default));
        Assert.Equal(new[] { "confirmed", "external", "fresh", "legacy" }, await database.Users.OrderBy(user => user.Id).Select(user => user.Id).ToArrayAsync());
        Assert.Single(await database.UserLogins.ToListAsync());
    }

    /// <summary>Большая очередь удаляется ограниченными порциями; остановка до SQL не удаляет строки.</summary>
    [Fact]
    public async Task CleanupIsBatchedAndHonorsCancellationAsync()
    {
        var clock = new RegistrationClock();
        using var factory = new AuthFactory(clock: clock);
        using var client = await AnonymousClientAsync(factory);
        using var scope = factory.Services.CreateScope();
        var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
        database.Users.AddRange(Enumerable.Range(0, 201).Select(index => User("pending-" + index, clock.GetUtcNow().AddHours(-2))));
        await database.SaveChangesAsync();
        var cleanup = scope.ServiceProvider.GetRequiredService<PendingRegistrationCleanup>();
        using var canceled = new CancellationTokenSource();
        canceled.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => cleanup.DeleteBatchAsync(canceled.Token));
        Assert.Equal(201, await database.Users.CountAsync());
        Assert.Equal(200, await cleanup.DeleteBatchAsync(default));
        Assert.Equal(1, await cleanup.DeleteBatchAsync(default));
        Assert.Empty(await database.Users.ToListAsync());
    }

    /// <summary>Фоновая служба выполняет очистку без HTTP-запроса и корректно останавливается во время ожидания.</summary>
    [Fact]
    public async Task WorkerCleansAtStartupAndStopsWithoutWaitingAMinuteAsync()
    {
        var clock = new RegistrationClock();
        var completed = new TaskCompletionSource<TestEmailLogs.Entry>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var logs = new TestEmailLogs(typeof(PendingRegistrationCleanup).FullName, entry => completed.TrySetResult(entry));
        using var factory = new AuthFactory(clock: clock, providerSettings: logs.Settings);
        using var client = await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using (var scope = factory.Services.CreateScope())
        {
            var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            database.Users.Add(User("private-expired-owner", clock.GetUtcNow().AddHours(-2)));
            await database.SaveChangesAsync();
        }
        using var worker = new PendingRegistrationCleanupWorker(factory.Services.GetRequiredService<IServiceScopeFactory>(),
            clock, NullLogger<PendingRegistrationCleanupWorker>.Instance);
        await worker.StartAsync(default);
        try
        {
            var entry = await completed.Task.WaitAsync(TimeSpan.FromSeconds(15));
            Assert.Equal(4400, entry.EventId);
            Assert.Equal("1", entry.Fields["DeletedCount"]);
            Assert.DoesNotContain("private-expired-owner", entry.Message + string.Join(" ", entry.Fields.Values));
            Assert.Null(entry.Exception);
        }
        finally { await worker.StopAsync(default).WaitAsync(TimeSpan.FromSeconds(15)); }
        using var verification = factory.Services.CreateScope();
        Assert.Empty(await verification.ServiceProvider.GetRequiredService<AuthDbContext>().Users.ToListAsync());
    }

    /// <summary>Временный сбой фоновой задачи логируется без текста исключения и допускает штатную остановку.</summary>
    [Fact]
    public async Task WorkerFailureDoesNotExposeExceptionDetailsAsync()
    {
        var completed = new TaskCompletionSource<TestEmailLogs.Entry>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var logs = new TestEmailLogs(typeof(PendingRegistrationCleanupWorker).FullName, entry => completed.TrySetResult(entry));
        using var loggerFactory = logs.Factory();
        using var worker = new PendingRegistrationCleanupWorker(new FailingScopes(), TimeProvider.System,
            loggerFactory.CreateLogger<PendingRegistrationCleanupWorker>());
        await worker.StartAsync(default);
        try
        {
            var entry = await completed.Task.WaitAsync(TimeSpan.FromSeconds(15));
            Assert.Equal(4401, entry.EventId);
            Assert.Equal("InvalidOperationException", entry.Fields["ExceptionType"]);
            Assert.DoesNotContain("private-value", entry.Message + string.Join(" ", entry.Fields.Values));
            Assert.Null(entry.Exception);
        }
        finally { await worker.StopAsync(default).WaitAsync(TimeSpan.FromSeconds(15)); }
    }

    /// <summary>Новый аккаунт переживает первый проход и удаляется следующим проходом после продвижения часов, без реальных ожиданий.</summary>
    [Fact]
    public async Task WorkerDeletesAfterTheNextScheduledIntervalAsync()
    {
        var clock = new RegistrationClock(manualTimers: true);
        var completed = new TaskCompletionSource<TestEmailLogs.Entry>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var logs = new TestEmailLogs(typeof(PendingRegistrationCleanup).FullName, entry => completed.TrySetResult(entry));
        using var factory = new AuthFactory(clock: clock, providerSettings: logs.Settings);
        using var client = await AnonymousClientAsync(factory);
        factory.Services.GetRequiredService<ILoggerFactory>().AddProvider(logs);
        using (var scope = factory.Services.CreateScope())
        {
            var database = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            database.Users.Add(User("fresh-owner", clock.GetUtcNow()));
            await database.SaveChangesAsync();
        }
        using var worker = new PendingRegistrationCleanupWorker(factory.Services.GetRequiredService<IServiceScopeFactory>(),
            clock, NullLogger<PendingRegistrationCleanupWorker>.Instance);
        await worker.StartAsync(default);
        try
        {
            await clock.TimerReady.WaitAsync(TimeSpan.FromSeconds(15));
            Assert.Equal(TimeSpan.FromMinutes(1), clock.TimerDue);
            Assert.Empty(logs.Entries);
            clock.Advance(TimeSpan.FromHours(2));
            clock.FireTimer();
            Assert.Equal("1", (await completed.Task.WaitAsync(TimeSpan.FromSeconds(15))).Fields["DeletedCount"]);
        }
        finally { await worker.StopAsync(default).WaitAsync(TimeSpan.FromSeconds(15)); }
    }

    /// <summary>Создаёт синтетическую строку Identity для проверки групп, без парольных/почтовых секретов.</summary>
    private static ApplicationUser User(string id, DateTimeOffset created, bool confirmed = false, bool required = true) =>
        new()
        {
            Id = id,
            UserName = id,
            NormalizedUserName = id.ToUpperInvariant(),
            CreatedAt = created,
            EmailConfirmationRequired = required,
            EmailConfirmed = confirmed
        };

    /// <summary>Регистрирует пользователя через настоящую форму, отправляя письмо только в test outbox.</summary>
    private static Task<HttpResponseMessage> RegisterAsync(HttpClient client, string email = "new@example.com", string password = "private-original-password") =>
        PostAsync(client, "/register", "/register", new() { ["email"] = email, ["password"] = password, ["confirmPassword"] = password });

    /// <summary>Выполняет явный CSRF POST исходной ссылки, включая случаи старого user ID.</summary>
    private static Task<HttpResponseMessage> ConfirmAsync(HttpClient client, string link) => PostAsync(client, link, "/email/confirm",
        QueryHelpers.ParseQuery(new Uri(link).Query).ToDictionary(pair => pair.Key, pair => pair.Value.ToString()));

    /// <summary>Продвигает только доменное время; тест не ожидает реальных двух часов.</summary>
    private sealed class RegistrationClock(bool manualTimers = false) : TimeProvider
    {
        private DateTimeOffset _now = new(2026, 11, 8, 12, 0, 0, TimeSpan.Zero);
        private readonly TaskCompletionSource _timerReady = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private ManualTimer? _timer;
        /// <summary>Сигнал перехода фоновой службы к ожиданию.</summary>
        internal Task TimerReady => _timerReady.Task;
        /// <summary>Фактически запрошенная задержка фоновой службы.</summary>
        internal TimeSpan TimerDue { get; private set; }
        /// <summary>Возвращает UTC время текущего изолированного сценария.</summary>
        public override DateTimeOffset GetUtcNow() => _now;
        /// <summary>Меняет время для проверки границ срока.</summary>
        internal void Advance(TimeSpan delta) => _now += delta;

        /// <summary>В одном сценарии заменяет таймер управляемым сигналом, сохраняя обычные таймеры остальных fixtures.</summary>
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            if (!manualTimers) return base.CreateTimer(callback, state, dueTime, period);
            var timer = new ManualTimer(callback, state);
            _timer = timer;
            TimerDue = dueTime;
            _timerReady.TrySetResult();
            return timer;
        }

        /// <summary>Запускает продолжение Task.Delay после продвижения доменных часов.</summary>
        internal void FireTimer() => _timer?.Fire();

        /// <summary>Одноразовый timer для детерминированной проверки интервала и отмены.</summary>
        private sealed class ManualTimer(TimerCallback callback, object? state) : ITimer
        {
            private int _disposed;
            /// <summary>Вызывает зарегистрированное продолжение только до освобождения.</summary>
            internal void Fire() { if (Volatile.Read(ref _disposed) == 0) callback(state); }
            /// <summary>Поддерживает контракт ITimer; время полностью управляется тестом.</summary>
            public bool Change(TimeSpan dueTime, TimeSpan period) => Volatile.Read(ref _disposed) == 0;
            /// <summary>Запрещает последующие сигналы.</summary>
            public void Dispose() => Interlocked.Exchange(ref _disposed, 1);
            /// <summary>Освобождает timer при отмене фоновой службы.</summary>
            public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        }
    }

    /// <summary>Имитирует временную ошибку DI/инфраструктуры до обращения к рабочей БД.</summary>
    private sealed class FailingScopes : IServiceScopeFactory
    {
        /// <summary>Исходное сообщение содержит приватное значение для проверки безопасного логирования.</summary>
        public IServiceScope CreateScope() => throw new InvalidOperationException("private-value");
    }
}
