using System.Net;
using System.Security.Cryptography;
using FitnessTracker.Authentication;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace FitnessTracker.Server.Tests;

/// <summary>Проверяет HTTPS OAuth при завершении TLS на хостовом Nginx и защиту от поддельных forwarded headers.</summary>
[Trait("Category", "HTTP")]
public sealed class HostNginxForwardingTests
{
    /// <summary>Только доверенный gateway может подтвердить исходный HTTPS поверх внутреннего HTTP.</summary>
    [Theory]
    [InlineData("172.30.0.1", true)]
    [InlineData("::ffff:172.30.0.1", true)]
    [InlineData("198.51.100.9", false)]
    [InlineData("::ffff:198.51.100.9", false)]
    public async Task RequiresTrustedPeerForForwardedHttpsAsync(string peerAddress, bool trusted)
    {
        // Arrange: настоящий Auth pipeline получает HTTP-запрос, как от Nginx на Docker host.
        using var factory = new AuthFactory(IPAddress.Parse(peerAddress), "172.30.0.1");
        using var client = await factory.SignedInAsync();
        client.BaseAddress = new Uri("http://localhost");
        client.DefaultRequestHeaders.Add("X-Forwarded-Proto", "https");
        client.DefaultRequestHeaders.Add("X-Forwarded-For", "203.0.113.8");
        var url = QueryHelpers.AddQueryString("/connect/authorize", new Dictionary<string, string?>
        {
            ["client_id"] = AuthConfiguration.ClientId,
            ["redirect_uri"] = AuthConfiguration.Callback,
            ["response_type"] = "code",
            ["scope"] = "profile",
            ["state"] = "nginx-state",
            ["code_challenge"] = Base64UrlEncoder.Encode(SHA256.HashData("nginx-test-verifier"u8.ToArray())),
            ["code_challenge_method"] = "S256"
        });

        // Act: не подменяем OpenIddict, cookies или UseForwardedHeaders.
        using var response = await client.GetAsync(url);

        // Assert: доверенный proxy завершает PKCE authorize; чужой peer не обходит требование HTTPS.
        if (trusted)
        {
            Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
            var callback = Assert.IsType<Uri>(response.Headers.Location);
            Assert.Equal(new Uri(AuthConfiguration.Callback).GetLeftPart(UriPartial.Path), callback.GetLeftPart(UriPartial.Path));
            var query = QueryHelpers.ParseQuery(callback.Query);
            Assert.Equal("nginx-state", query["state"].ToString());
            Assert.False(string.IsNullOrWhiteSpace(query["code"]));
            Assert.False(query.ContainsKey("access_token"));
        }
        else
        {
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.Null(response.Headers.Location);
            var error = await response.Content.ReadAsStringAsync();
            Assert.Contains("invalid_request", error);
            Assert.Contains("https://documentation.openiddict.com/errors/ID2083", error);
        }
    }
}
