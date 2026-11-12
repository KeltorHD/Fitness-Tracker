using System.Net;
using MimeKit;

namespace FitnessTracker.Authentication;

/// <summary>Собирает HTML и plain text подтверждения из одного проверенного HTTPS-адреса без внешних ресурсов.</summary>
internal static class ConfirmationEmailTemplate
{
    private const string LINK_PLACEHOLDER = "{{CONFIRMATION_URL}}";
    private static readonly Lazy<string> _html = new(LoadHtml);

    /// <summary>Кнопка, видимая ссылка и plain text ведут на один URL с неизменёнными параметрами токена.</summary>
    internal static MimeEntity CreateBody(string confirmationLink)
    {
        if (confirmationLink.Any(char.IsControl) || !Uri.TryCreate(confirmationLink, UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps || uri.Host.Length == 0 || uri.UserInfo.Length > 0 || uri.Fragment.Length > 0)
            throw new FormatException("Email confirmation requires an absolute HTTPS URL without credentials or fragment.");
        var link = uri.AbsoluteUri;
        return new BodyBuilder
        {
            TextBody = $"""
                FitnessTracker

                Подтвердите электронную почту

                Вы создали аккаунт FitnessTracker. Чтобы завершить регистрацию, откройте ссылку:

                {link}

                Подтвердите почту в течение 2 часов после регистрации. Повторное письмо не продлевает срок. На открывшейся странице нажмите «Подтвердить адрес», затем вернитесь в приложение и продолжите вход.

                Если ссылка не нажимается, скопируйте её целиком в адресную строку браузера.
                Если вы не создавали аккаунт, просто проигнорируйте письмо.

                Твой ритм. Твой прогресс.
                """,
            HtmlBody = _html.Value.Replace(LINK_PLACEHOLDER, WebUtility.HtmlEncode(link), StringComparison.Ordinal)
        }.ToMessageBody();
    }

    /// <summary>Читает встроенный шаблон один раз; письмо не зависит от текущего каталога или HTTP-загрузки.</summary>
    private static string LoadHtml()
    {
        using var stream = typeof(ConfirmationEmailTemplate).Assembly.GetManifestResourceStream(
            "FitnessTracker.Authentication.EmailTemplates.Confirmation.html")
            ?? throw new InvalidOperationException("The confirmation email template is missing.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
