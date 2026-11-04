using System.Security.Claims;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace FitnessTracker.Authentication;

public sealed class ExternalAccounts(AuthDbContext database, UserManager<ApplicationUser> users)
{
    public async Task<ApplicationUser> SignIn(string provider, string subject, ClaimsPrincipal principal,
        CancellationToken cancellationToken)
    {
        var existing = await users.FindByLoginAsync(provider, subject);
        if (existing is not null) return existing;
        // Email is descriptive data, never proof that two provider identities belong to one person.
        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        var user = new ApplicationUser
        {
            Id = Guid.NewGuid().ToString(),
            UserName = Guid.NewGuid().ToString("N"),
            Email = principal.FindFirstValue(ClaimTypes.Email),
            EmailConfirmed = false,
            DisplayName = (principal.FindFirstValue(ClaimTypes.Name) ?? "Пользователь")[..Math.Min(
                (principal.FindFirstValue(ClaimTypes.Name) ?? "Пользователь").Length, 200)]
        };
        Check(await users.CreateAsync(user));
        Check(await users.AddLoginAsync(user, new UserLoginInfo(provider, subject, provider)));
        await transaction.CommitAsync(cancellationToken);
        return user;
    }

    public async Task<bool> Unlink(ApplicationUser user, string provider, CancellationToken cancellationToken)
    {
        await using var transaction = await database.Database.BeginTransactionAsync(
            System.Data.IsolationLevel.Serializable, cancellationToken);
        var logins = await users.GetLoginsAsync(user);
        var login = logins.SingleOrDefault(item => item.LoginProvider == provider);
        if (login is null || (logins.Count <= 1 && !await users.HasPasswordAsync(user))) return false;
        Check(await users.RemoveLoginAsync(user, login.LoginProvider, login.ProviderKey));
        Check(await users.UpdateSecurityStampAsync(user));
        await transaction.CommitAsync(cancellationToken);
        return true;
    }

    public static void Check(IdentityResult result)
    {
        if (!result.Succeeded) throw new InvalidOperationException("The account operation could not be completed.");
    }
}
