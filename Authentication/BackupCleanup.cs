namespace FitnessTracker.Authentication;

public sealed class BackupCleanup(HttpClient client, IConfiguration config)
{
    public async Task Delete(string userId, CancellationToken cancellationToken)
    {
        var address = config["Backend:InternalUrl"] ?? throw new InvalidOperationException("Backend URL is required.");
        var key = config["Backend:ServiceKey"];
        if (string.IsNullOrWhiteSpace(key) || key.Length < 32)
            throw new InvalidOperationException("A service key of at least 32 characters is required.");
        using var request = new HttpRequestMessage(HttpMethod.Delete,
            new Uri(new Uri(address), $"internal/users/{Uri.EscapeDataString(userId)}/backups"));
        request.Headers.Add("X-Service-Key", key);
        using var response = await client.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
    }
}
