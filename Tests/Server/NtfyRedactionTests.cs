using System.Text.Json;
using FitLife.ServerLogging;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет реальные варианты секретов в текстовых, JSON и callback логах.</summary>
[Trait("Category", "Unit")]
public sealed class NtfyRedactionTests
{
    /// <summary>Динамические секреты скрываются даже без наличия соответствующего значения в IConfiguration.</summary>
    [Theory]
    [InlineData("Authorization: Bearer private-marker")]
    [InlineData("Cookie: __Host-FitLifeAuth=private-marker")]
    [InlineData("Set-Cookie: session=private-marker; Secure; HttpOnly")]
    [InlineData("{\"refresh_token\":\"private-marker\"}")]
    [InlineData("{\"accessToken\":\"private-marker\"}")]
    [InlineData("{\"confirmPassword\":\"private-marker\"}")]
    [InlineData("password='private-marker'")]
    [InlineData("__RequestVerificationToken=private-marker&returnUrl=/account")]
    [InlineData("GET /callback/login/google?code=private-marker&state=private-marker")]
    [InlineData("https://user:private-marker@example.com/callback?code=private-marker#private-marker")]
    [InlineData("person-private-marker@example.com")]
    [InlineData("eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJmaXh0dXJlIn0.private-marker")]
    public void MasksDynamicFields(string text) => Assert.DoesNotContain("private-marker", Redactor().Redact(text));

    /// <summary>Пароль connection string и JSON/URL-encoded варианты маскируются вне контекста имени поля.</summary>
    [Fact]
    public void MasksConnectionPasswordAndEncodedConfigurationValues()
    {
        const string secret = "private-marker/with+quote\"";
        var redactor = Redactor(new()
        {
            ["Smtp:Password"] = secret,
            ["ConnectionStrings:Database"] = "Host=localhost;Password=database-private-marker",
            ["Ntfy:Topic"] = "topic-private-marker",
            ["Email:Enabled"] = "true"
        });
        foreach (var value in new[] { secret, Uri.EscapeDataString(secret), JsonSerializer.Serialize(secret)[1..^1],
            "database-private-marker", "topic-private-marker" })
            Assert.DoesNotContain("private-marker", redactor.Redact("Value: " + value));
        Assert.Contains("status 200; ready=true", redactor.Redact("status 200; ready=true"));
    }

    /// <summary>Неизвестное содержимое HTTP/claims/архивов скрывается целиком, а не угадывается по отдельным полям.</summary>
    [Fact]
    public void SuppressesStructuredResponsesAndRawArchive()
    {
        var redactor = Redactor();
        var fields = new[] { new KeyValuePair<string, object?>("Response", new[] { "private-person", "private-health" }) };
        Assert.DoesNotContain("private-person", redactor.Redact("response private-person", fields));
        Assert.DoesNotContain("private-health", redactor.Redact("{\"workouts\":[{\"notes\":\"private-health\"}]}"));
    }

    /// <summary>Использует только синтетические настройки сценария.</summary>
    private static NtfyLogRedactor Redactor(Dictionary<string, string?>? values = null) =>
        new(new ConfigurationBuilder().AddInMemoryCollection(values ?? []).Build());
}
