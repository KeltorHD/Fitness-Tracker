using Mapster;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ModelBinding;
using Microsoft.AspNetCore.WebUtilities;
using OpenIddict.Server.AspNetCore;

namespace FitLife.Authentication.Controllers;

/// <summary>Явно преобразует HTTP-контракты и данные сервисов, не маппит Identity/EF entities.</summary>
public static class AuthenticationMapping
{
    /// <summary>Создаёт отдельную конфигурацию для DI и проверяет все разрешённые преобразования при запуске.</summary>
    public static TypeAdapterConfig Create()
    {
        var config = new TypeAdapterConfig { RequireExplicitMapping = true, RequireDestinationMemberSource = true };
        config.NewConfig<NavigationRequest, NavigationInput>().MapToConstructor(true);
        config.NewConfig<ExternalLoginRequest, ExternalLoginInput>().MapToConstructor(true);
        config.NewConfig<PasswordRegistrationRequest, PasswordRegistrationInput>().MapToConstructor(true);
        config.NewConfig<PasswordLoginRequest, PasswordLoginInput>().MapToConstructor(true);
        config.NewConfig<EmailResendRequest, EmailResendInput>().MapToConstructor(true);
        config.NewConfig<EmailConfirmationRequest, EmailConfirmationInput>().MapToConstructor(true);
        config.NewConfig<EmailPendingPageData, EmailPendingPage>().MapToConstructor(true);
        config.NewConfig<EmailConfirmPageData, EmailConfirmPage>().MapToConstructor(true);
        config.NewConfig<EmailConfirmationOutcome, EmailCompletePage>().MapToConstructor(true);
        config.NewConfig<PasskeyRegistrationRequest, PasskeyRegistrationInput>().MapToConstructor(true);
        config.NewConfig<PasskeyRequest, PasskeySubmission>()
            .Map(destination => destination.CredentialJson, source => source.Credential)
            .MapToConstructor(true);
        config.NewConfig<PasskeyRemovalRequest, PasskeyRemovalInput>().MapToConstructor(true);
        config.NewConfig<AccountPasskeyData, PasskeySummary>()
            .Map(destination => destination.CredentialId, source => WebEncoders.Base64UrlEncode(source.CredentialId))
            .MapToConstructor(true);
        config.NewConfig<AccountPageData, AccountPage>().MapToConstructor(true);
        config.NewConfig<AccountProfileData, AccountProfileResponse>().MapToConstructor(true);
        config.NewConfig<LoginPageData, LoginPage>().MapToConstructor(true);
        config.NewConfig<RegistrationPageData, RegistrationPage>().MapToConstructor(true);
        config.NewConfig<PasswordRegistrationOutcome, RegistrationPage>().MapToConstructor(true);
        config.NewConfig<PasskeyDestination, PasskeyResponse>().MapToConstructor(true);
        config.NewConfig<AppAssociationData, AppleAssociationResponse>()
            .MapWith(data => new AppleAssociationResponse(new AppleWebCredentials(data.Apps)));
        config.NewConfig<CallbackMessage, ContentResult>().MapWith(data => new ContentResult
        {
            StatusCode = StatusCodes.Status400BadRequest,
            ContentType = "text/plain; charset=utf-8",
            Content = data.Message
        });
        config.NewConfig<OAuthDecision, IActionResult>().MapWith(decision => CreateOAuthResult(decision));
        config.NewConfig<AuthenticationOperationException, IActionResult>().MapWith(error => CreateErrorResult(error));
        config.NewConfig<PasswordRegistrationOutcome, IActionResult>()
            .MapWith(outcome => CreateRegistrationResult(outcome, config));
        config.NewConfig<PasswordLoginOutcome, IActionResult>()
            .MapWith(outcome => new LoginMessageRedirectResult(outcome.ReturnUrl, outcome.Error));
        config.Compile();
        return config;
    }

    /// <summary>Преобразует только разрешённые протокольные решения, сохраняя principal OpenIddict без remapping.</summary>
    private static IActionResult CreateOAuthResult(OAuthDecision decision) => decision switch
    {
        OAuthSignIn approved => new SignInResult(OpenIddictServerAspNetCoreDefaults.AuthenticationScheme, approved.Principal),
        OAuthRedirect redirect => new RedirectResult(redirect.ReturnUrl),
        OAuthDenied denied => new ForbidResult(OpenIddictServerAspNetCoreDefaults.AuthenticationScheme,
            new AuthenticationProperties(new Dictionary<string, string?>
            { [OpenIddictServerAspNetCoreConstants.Properties.Error] = denied.Error })),
        _ => throw new InvalidOperationException("Unknown OAuth decision.")
    };

    /// <summary>Сохраняет статусы ожидаемых отказов, не перехватывая неизвестные исключения и отмену.</summary>
    private static IActionResult CreateErrorResult(AuthenticationOperationException error)
    {
        var status = error.Failure switch
        {
            AuthenticationFailure.Unauthorized => StatusCodes.Status401Unauthorized,
            AuthenticationFailure.NotFound => StatusCodes.Status404NotFound,
            AuthenticationFailure.Forbidden => StatusCodes.Status403Forbidden,
            AuthenticationFailure.Conflict => StatusCodes.Status409Conflict,
            AuthenticationFailure.InvalidInput => StatusCodes.Status400BadRequest,
            AuthenticationFailure.Unavailable => StatusCodes.Status503ServiceUnavailable,
            _ => throw new InvalidOperationException("Unknown authentication failure.")
        };
        if (error.Title is null) return new StatusCodeResult(status);
        return new ObjectResult(new ProblemDetails { Status = status, Title = error.Title }) { StatusCode = status };
    }

    /// <summary>Создаёт HTML-ошибку с чистым ModelState, исключая повторное отображение введённых паролей.</summary>
    private static IActionResult CreateRegistrationResult(PasswordRegistrationOutcome outcome, TypeAdapterConfig config)
    {
        if (outcome.Error is null) return new LocalRedirectResult(outcome.ReturnUrl);
        var state = new ModelStateDictionary();
        state.AddModelError("", outcome.Error);
        return new ViewResult
        {
            ViewName = "~/Views/Password/Register.cshtml",
            StatusCode = StatusCodes.Status400BadRequest,
            ViewData = new Microsoft.AspNetCore.Mvc.ViewFeatures.ViewDataDictionary(new EmptyModelMetadataProvider(), state)
            { Model = outcome.Adapt<RegistrationPage>(config) }
        };
    }
}
