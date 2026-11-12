using System.Security.Claims;
using FitLife.Authentication;
using FitLife.Authentication.Controllers;
using MapsterMapper;
using Microsoft.AspNetCore.Mvc;
using OpenIddict.Abstractions;
using OpenIddict.Server.AspNetCore;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет границы контроллеров, запрет неявного entity mapping и сохранность OAuth principal.</summary>
[Trait("Category", "Unit")]
public sealed class AuthenticationMappingTests
{
    /// <summary>Контроллеры зависят только от прикладных сервисов и Mapster, без EF/Identity/OpenIddict managers.</summary>
    [Fact]
    public void ControllersOnlyDependOnApplicationServicesAndMapper()
    {
        var controllers = typeof(AccountController).Assembly.GetTypes()
            .Where(type => !type.IsAbstract && typeof(ControllerBase).IsAssignableFrom(type))
            .ToArray();
        Assert.NotEmpty(controllers);
        foreach (var controller in controllers)
        {
            var dependencies = Assert.Single(controller.GetConstructors()).GetParameters();
            Assert.Contains(dependencies, dependency => dependency.ParameterType == typeof(IMapper));
            Assert.All(dependencies, dependency => Assert.True(dependency.ParameterType == typeof(IMapper) ||
                (dependency.ParameterType.Namespace == typeof(AccountService).Namespace && dependency.ParameterType.Name.EndsWith("Service", StringComparison.Ordinal)),
                $"Unexpected controller dependency: {controller.Name} -> {dependency.ParameterType.Name}"));
        }
    }

    /// <summary>Не позволяет сериализовать Identity entity через автоматически выведенный HTTP mapping.</summary>
    [Fact]
    public void UnregisteredIdentityEntityMappingIsRejected()
    {
        var mapper = new Mapper(AuthenticationMapping.Create());
        var user = new ApplicationUser { PasswordHash = "private-hash", SecurityStamp = "private-stamp" };

        var error = Assert.ThrowsAny<Exception>(() => mapper.Map<ApplicationUser, AccountProfileResponse>(user));

        Assert.IsType<InvalidOperationException>(error.GetBaseException());
        Assert.Contains("Implicit mapping", error.GetBaseException().Message);
    }

    /// <summary>Не пересоздаёт claims и не теряет grant/stamp при преобразовании решения сервиса в SignIn/Forbid.</summary>
    [Fact]
    public void OAuthMappingPreservesNativePrincipalAndProtocolErrors()
    {
        var mapper = new Mapper(AuthenticationMapping.Create());
        var principal = new ClaimsPrincipal(new ClaimsIdentity("Bearer"))
            .SetClaim(OpenIddictConstants.Claims.Subject, Guid.NewGuid().ToString())
            .SetClaim("fitlife:security_stamp", "protected-cookie-version")
            .SetAuthorizationId("authorization-family")
            .SetScopes("profile", "offline_access");

        var approved = Assert.IsType<SignInResult>(mapper.Map<OAuthDecision, IActionResult>(new OAuthSignIn(principal)));
        var denied = Assert.IsType<ForbidResult>(mapper.Map<OAuthDecision, IActionResult>(
            new OAuthDenied(OpenIddictConstants.Errors.InvalidGrant)));

        Assert.Same(principal, approved.Principal);
        Assert.Equal(OpenIddictServerAspNetCoreDefaults.AuthenticationScheme, approved.AuthenticationScheme);
        Assert.Equal("authorization-family", approved.Principal.GetAuthorizationId());
        Assert.Equal("protected-cookie-version", approved.Principal.GetClaim("fitlife:security_stamp"));
        Assert.Equal(OpenIddictConstants.Errors.InvalidGrant,
            denied.Properties?.Items[OpenIddictServerAspNetCoreConstants.Properties.Error]);
        Assert.Equal(OpenIddictServerAspNetCoreDefaults.AuthenticationScheme, Assert.Single(denied.AuthenticationSchemes));
    }
}
