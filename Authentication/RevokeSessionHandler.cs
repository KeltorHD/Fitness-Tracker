using OpenIddict.Abstractions;
using OpenIddict.Server;
using static OpenIddict.Abstractions.OpenIddictConstants;
using static OpenIddict.Server.OpenIddictServerEvents;

namespace FitnessTracker.Authentication;

/// <summary>Расширяет стандартный revoke OpenIddict до атомарного отзыва одной сессии и всех её токенов.</summary>
public sealed class RevokeSessionHandler(AuthDbContext database, IOpenIddictTokenManager tokens,
    IOpenIddictAuthorizationManager authorizations) : IOpenIddictServerHandler<HandleRevocationRequestContext>
{
    /// <summary>Работает после штатной проверки token/client; не затрагивает другие сессии пользователя.</summary>
    public async ValueTask HandleAsync(HandleRevocationRequestContext context)
    {
        var cancellationToken = context.CancellationToken;
        var tokenId = context.GenericTokenPrincipal?.GetTokenId();
        var token = tokenId is null ? null : await tokens.FindByIdAsync(tokenId, cancellationToken);
        if (token is null)
        {
            context.Reject(Errors.InvalidToken);
            return;
        }
        await using var transaction = await database.Database.BeginTransactionAsync(cancellationToken);
        var authorizationId = await tokens.GetAuthorizationIdAsync(token, cancellationToken);
        if (authorizationId is not null)
        {
            var authorization = await authorizations.FindByIdAsync(authorizationId, cancellationToken);
            if (authorization is null || !await authorizations.TryRevokeAsync(authorization, cancellationToken))
            {
                context.Reject(Errors.ServerError);
                return;
            }
            await tokens.RevokeByAuthorizationIdAsync(authorizationId, cancellationToken);
        }
        else if (!await tokens.TryRevokeAsync(token, cancellationToken))
        {
            context.Reject(Errors.ServerError);
            return;
        }
        await transaction.CommitAsync(cancellationToken);
    }
}
