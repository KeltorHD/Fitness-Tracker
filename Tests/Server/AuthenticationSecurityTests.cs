using System.Net;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет границы защиты до обработки анонимных OAuth-запросов.</summary>
[Trait("Category", "HTTP")]
public sealed class AuthenticationSecurityTests
{
    /// <summary>Ответы OpenIddict, завершающие authentication middleware, также расходуют IP-лимит.</summary>
    [Theory]
    [InlineData("/connect/token", true, HttpStatusCode.BadRequest)]
    [InlineData("/connect/authorize", false, HttpStatusCode.BadRequest)]
    [InlineData("/.well-known/openid-configuration", false, HttpStatusCode.OK)]
    public async Task LimitsAnonymousProtocolRequestsAsync(string path, bool post, HttpStatusCode initialStatus)
    {
        // Arrange: изолированный Auth с настоящим OpenIddict и общим IP для серии запросов.
        using var factory = new AuthFactory();
        using var client = await factory.SignedInAsync();
        client.DefaultRequestHeaders.Remove("Cookie");

        // Act/Assert: 120 запросов укладываются в окно; следующий отклоняется до OpenIddict.
        for (var index = 0; index <= 120; index++)
        {
            using var request = new HttpRequestMessage(post ? HttpMethod.Post : HttpMethod.Get, path);
            if (post)
                request.Content = new FormUrlEncodedContent(new Dictionary<string, string> { ["grant_type"] = "invalid" });
            using var response = await client.SendAsync(request);
            Assert.Equal(index < 120 ? initialStatus : HttpStatusCode.TooManyRequests, response.StatusCode);
        }
    }
}
