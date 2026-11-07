using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;
using MimeKit;

namespace FitnessTracker.Authentication;

/// <summary>Отделяет локальные email-аккаунты от внешних профилей с тем же неподтверждённым адресом.</summary>
public sealed class EmailAccounts(UserManager<ApplicationUser> users)
{
    /// <summary>Проверяет и обрезает адрес; владение почтой этим не подтверждается.</summary>
    public static string? ValidateEmail(string? email)
    {
        var value = email?.Trim();
        return value is { Length: > 0 and <= 254 } && new EmailAddressAttribute().IsValid(value)
            ? value : null;
    }

    /// <summary>Для новой регистрации требует одиночный SMTP mailbox, сохраняя прежнюю нормализацию входа.</summary>
    public static string? ValidateRegistrationEmail(string? email)
    {
        var value = ValidateEmail(email);
        return value is not null && MailboxAddress.TryParse(value, out var mailbox) && mailbox.Address == value
            ? value : null;
    }

    /// <summary>Строит стабильное уникальное имя локального аккаунта через нормализатор Identity.</summary>
    public string UserName(string email) => "email-" + Convert.ToHexString(
        SHA256.HashData(Encoding.UTF8.GetBytes(users.NormalizeEmail(email))));

    /// <summary>Создаёт ожидающий подтверждения локальный профиль без слияния с внешними аккаунтами.</summary>
    public ApplicationUser NewUser(string email, string? id = null) => new()
    {
        Id = id ?? Guid.NewGuid().ToString(),
        UserName = UserName(email),
        Email = email,
        EmailConfirmed = false,
        EmailConfirmationRequired = true,
        DisplayName = "Пользователь"
    };
}

/// <summary>Выполняет сопоставимый password hash и для отсутствующего email, уменьшая утечку через время ответа.</summary>
public sealed class UnknownPasswordCheck
{
    private readonly PasswordHasher<ApplicationUser> _hasher;
    private readonly ApplicationUser _user = new();
    private readonly string _hash;

    /// <summary>Один раз создаёт случайный фиктивный hash без пользовательских данных.</summary>
    public UnknownPasswordCheck(IOptions<PasswordHasherOptions> options)
    {
        _hasher = new PasswordHasher<ApplicationUser>(options);
        _hash = _hasher.HashPassword(_user, Convert.ToHexString(RandomNumberGenerator.GetBytes(32)));
    }

    /// <summary>Проверяет введённый пароль против фиктивного hash без выдачи результата.</summary>
    public void Verify(string password) => _hasher.VerifyHashedPassword(_user, _hash, password);
}
