using System.Net;
using System.Text.RegularExpressions;
using FitLife.Authentication;
using Microsoft.AspNetCore.WebUtilities;
using MimeKit;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет реальные MIME части, кликабельные HTTPS-ссылки и fallback без изменения токена.</summary>
[Trait("Category", "Unit")]
public sealed class ConfirmationEmailTests
{
    /// <summary>После SMTP-сериализации кнопка и видимый URL сохраняют точные параметры Identity, plain text тоже содержит адрес.</summary>
    [Theory]
    [InlineData("synthetic_token_-", "plain")]
    [InlineData("synthetic+token/with=padding", "encoded")]
    public void MimeRoundTripPreservesButtonAndFallback(string token, string marker)
    {
        var id = Guid.NewGuid().ToString();
        var link = QueryHelpers.AddQueryString("https://auth.example.com/email/confirm", new Dictionary<string, string?>
        { ["userId"] = id, ["code"] = token, ["marker"] = marker });
        using var message = new MimeMessage();
        message.From.Add(MailboxAddress.Parse("fitness@example.com"));
        message.To.Add(MailboxAddress.Parse("recipient@example.com"));
        message.Subject = "Подтвердите электронную почту — FitLife";
        message.Body = ConfirmationEmailTemplate.CreateBody(link);
        using var stream = new MemoryStream();
        message.WriteTo(FormatOptions.Default, stream);
        stream.Position = 0;
        using var decoded = MimeMessage.Load(stream);
        Assert.IsType<MultipartAlternative>(decoded.Body);
        var text = Assert.IsType<string>(decoded.TextBody);
        var html = Assert.IsType<string>(decoded.HtmlBody);
        Assert.Contains(link, text);
        Assert.Contains("скопируйте", text);
        Assert.Contains("Подтвердить почту", html);
        Assert.Contains("2 часа", html);
        Assert.DoesNotContain("{{CONFIRMATION_URL}}", html);
        var anchors = Regex.Matches(html, "<a\\s+[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>", RegexOptions.Singleline);
        Assert.Equal(2, anchors.Count);
        foreach (Match anchor in anchors)
        {
            var target = WebUtility.HtmlDecode(anchor.Groups[1].Value);
            Assert.Equal(link, target);
            var query = QueryHelpers.ParseQuery(new Uri(target).Query);
            Assert.Equal(token, query["code"].ToString());
            Assert.Equal(id, query["userId"].ToString());
        }
        Assert.Equal(link, WebUtility.HtmlDecode(anchors[1].Groups[2].Value));
    }

    /// <summary>Почтовый клиент может удалить CSS: оба обычных anchor и текстовый URL остаются доступными.</summary>
    [Fact]
    public void LinksSurviveRemovalOfPresentationStyles()
    {
        const string link = "https://auth.example.com/email/confirm?userId=synthetic&code=synthetic_token";
        using var body = ConfirmationEmailTemplate.CreateBody(link);
        var html = Assert.IsType<MultipartAlternative>(body).OfType<TextPart>().Single(part => part.IsHtml).Text;
        var stripped = Regex.Replace(html, "<style\\b[^>]*>.*?</style>|\\sstyle=\"[^\"]*\"", "", RegexOptions.Singleline);
        Assert.Equal(2, Regex.Matches(stripped, "href=\"" + Regex.Escape(WebUtility.HtmlEncode(link)) + "\"").Count);
        Assert.Contains(WebUtility.HtmlEncode(link), stripped);
        Assert.DoesNotContain("<script", html, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("<img", html, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("<form", html, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("url(", html, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Недоверенные схемы, credentials и управляющие символы не становятся ссылкой письма.</summary>
    [Theory]
    [InlineData("javascript:alert(1)")]
    [InlineData("http://auth.example.com/email/confirm")]
    [InlineData("//auth.example.com/email/confirm")]
    [InlineData("https://user:private@example.com/email/confirm")]
    [InlineData("https://auth.example.com/email/confirm#private")]
    [InlineData("https://auth.example.com/email/confirm?code=private\r\nInjected: value")]
    public void RejectsUnsafeLinksWithoutEchoingTheirValues(string link)
    {
        var error = Assert.Throws<FormatException>(() => ConfirmationEmailTemplate.CreateBody(link));
        Assert.DoesNotContain(link, error.Message);
        Assert.DoesNotContain("private", error.Message);
    }
}
