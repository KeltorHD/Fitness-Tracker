using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет HTTP/JWT-контракты и сохранность данных настоящего API на SQLite.</summary>
[Trait("Category", "HTTP")]
public sealed class BackendTests
{
    private static readonly byte[] _archive = Encoding.UTF8.GetBytes(
        """{"format":"com.fitlife.archive","version":4,"exportedAt":1700000000,"workouts":[],"templates":[],"bodyWeights":[]}""");

    /// <summary>Создаёт отдельное HTTP body с MIME-типом архива для каждого запроса.</summary>
    private static ByteArrayContent Content(byte[]? data = null)
    {
        var content = new ByteArrayContent(data ?? _archive);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/vnd.fitlife+json");
        return content;
    }

    /// <summary>HTTP media type сравнивается без учёта регистра и допускает параметр charset.</summary>
    [Theory]
    [InlineData("Application/JSON; charset=utf-8")]
    [InlineData("APPLICATION/VND.FITLIFE+JSON")]
    public async Task AcceptsCaseInsensitiveMediaTypesAsync(string mediaType)
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        using var content = Content();
        content.Headers.ContentType = MediaTypeHeaderValue.Parse(mediaType);

        using var response = await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", content);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    /// <summary>Неподходящие issuer, тип и subject не дают читать и изменять копии.</summary>
    [Theory]
    [InlineData("issuer", HttpStatusCode.Unauthorized)]
    [InlineData("type", HttpStatusCode.Unauthorized)]
    [InlineData("subject", HttpStatusCode.Forbidden)]
    public async Task RejectsInvalidTokenContractsAsync(string invalid, HttpStatusCode expected)
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(invalid == "subject" ? "not-a-user-uuid" : Guid.NewGuid().ToString(),
            issuer: invalid == "issuer" ? "https://other-issuer.test/" : "https://auth.test/",
            tokenType: invalid == "type" ? "JWT" : "at+jwt");

        using var read = await client.GetAsync("/v1/backups");
        using var write = await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content());

        Assert.Equal(expected, read.StatusCode);
        Assert.Equal(expected, write.StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<BackupDbContext>().Backups.ToListAsync());
    }

    /// <summary>Metadata берётся из внедрённых часов, а заголовки и скачанные байты соответствуют копии.</summary>
    [Fact]
    public async Task ReturnsDeterministicMetadataAndDownloadHeadersAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString(), scope: "profile backups");
        var id = Guid.NewGuid();
        using var uploaded = await client.PutAsync($"/v1/backups/{id}", Content());
        Assert.Equal(HttpStatusCode.Created, uploaded.StatusCode);
        var info = Assert.IsType<BackupInfo>(await uploaded.Content.ReadFromJsonAsync<BackupInfo>());

        using var download = await client.GetAsync($"/v1/backups/{id}");

        Assert.Equal(BackendFactory.BackupTime, info.CreatedAt);
        Assert.Equal($"/v1/backups/{id}", uploaded.Headers.Location?.ToString());
        Assert.Equal($"\"{info.Sha256}\"", download.Headers.ETag?.ToString());
        Assert.Equal("no-store", download.Headers.CacheControl?.ToString());
        Assert.Equal("application/vnd.fitlife+json", download.Content.Headers.ContentType?.MediaType);
        Assert.Equal(_archive.Length, download.Content.Headers.ContentLength);
        Assert.Equal(_archive, await download.Content.ReadAsByteArrayAsync());
    }

    /// <summary>Неверный ID и Content-Type отклоняются до записи с правильным HTTP-контрактом.</summary>
    [Fact]
    public async Task RejectsInvalidIdAndUnsupportedContentTypeWithoutWritingAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        using var invalidId = await client.PutAsync($"/v1/backups/{Guid.Empty}", Content());
        Assert.Equal(HttpStatusCode.BadRequest, invalidId.StatusCode);
        Assert.Equal("invalid_id", (await invalidId.Content.ReadFromJsonAsync<System.Text.Json.JsonElement>()).GetProperty("code").GetString());

        using var unsupported = await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", new StringContent("private-payload"));

        Assert.Equal(HttpStatusCode.UnsupportedMediaType, unsupported.StatusCode);
        Assert.DoesNotContain("private-payload", await unsupported.Content.ReadAsStringAsync());
        Assert.Empty((await client.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
    }

    /// <summary>Отказ сохранения не создаёт копию; тот же UUID безопасно повторяется после исправления.</summary>
    [Fact]
    public async Task FailedSaveDoesNotPublishBackupAndCanBeRetriedAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var id = Guid.NewGuid();
        factory.Saves.Fail = true;

        using var failed = await client.PutAsync($"/v1/backups/{id}", Content());

        Assert.Equal(HttpStatusCode.InternalServerError, failed.StatusCode);
        Assert.DoesNotContain("Simulated", await failed.Content.ReadAsStringAsync());
        Assert.Empty((await client.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
        factory.Saves.Fail = false;
        using var retry = await client.PutAsync($"/v1/backups/{id}", Content());
        Assert.Equal(HttpStatusCode.Created, retry.StatusCode);
        Assert.Single((await client.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
    }

    /// <summary>Если marker не сохранился, транзакция возвращает удалённые копии, а повтор удаляет их.</summary>
    [Fact]
    public async Task FailedAccountCleanupRollsBackDeletedPayloadsAsync()
    {
        using var factory = new BackendFactory();
        var owner = Guid.NewGuid().ToString();
        using var client = factory.Client(owner);
        var id = Guid.NewGuid();
        using var created = await client.PutAsync($"/v1/backups/{id}", Content());
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        client.DefaultRequestHeaders.Add("X-Service-Key", BackendFactory.ServiceKey);
        factory.Saves.Fail = true;

        using var failed = await client.DeleteAsync($"/internal/users/{owner}/backups");

        Assert.Equal(HttpStatusCode.InternalServerError, failed.StatusCode);
        Assert.Equal(_archive, await client.GetByteArrayAsync($"/v1/backups/{id}"));
        factory.Saves.Fail = false;
        using var retry = await client.DeleteAsync($"/internal/users/{owner}/backups");
        Assert.Equal(HttpStatusCode.NoContent, retry.StatusCode);
        Assert.Empty((await client.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
    }

    /// <summary>Отмена перед SaveChanges откатывает транзакцию и не оставляет частичную копию.</summary>
    [Fact]
    public async Task CanceledSaveLeavesNoBackupAndAllowsRetryAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        using var cancellation = new CancellationTokenSource();
        var id = Guid.NewGuid();
        var owner = Guid.NewGuid().ToString();
        using (var scope = factory.Services.CreateScope())
        {
            var storage = scope.ServiceProvider.GetRequiredService<BackupStorage>();
            factory.Saves.CancelBeforeSave = cancellation;
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => storage.Put(owner, id, _archive, cancellation.Token));
        }
        factory.Saves.CancelBeforeSave = null;
        using var verification = factory.Services.CreateScope();
        Assert.Empty(await verification.ServiceProvider.GetRequiredService<BackupDbContext>().Backups.ToListAsync());
        var (info, created) = await verification.ServiceProvider.GetRequiredService<BackupStorage>().Put(owner, id, _archive, default);
        Assert.True(created);
        Assert.Equal(id, info.Id);
    }

    /// <summary>Проверяет неизменяемость, повтор PUT, точные байты и изоляцию данных между пользователями.</summary>
    [Fact]
    public async Task BackupRoundTripIsImmutableIdempotentAndIsolatedBySubjectAsync()
    {
        using var factory = new BackendFactory();
        using var owner = factory.Client(Guid.NewGuid().ToString());
        using var other = factory.Client(Guid.NewGuid().ToString());
        var id = Guid.NewGuid();
        using var uploaded = await owner.PutAsync($"/v1/backups/{id}", Content());
        Assert.Equal(HttpStatusCode.Created, uploaded.StatusCode);
        var info = await uploaded.Content.ReadFromJsonAsync<BackupInfo>();
        Assert.Equal(Convert.ToHexStringLower(SHA256.HashData(_archive)), info!.Sha256);
        Assert.Equal(_archive.Length, info.Size);
        Assert.Equal(HttpStatusCode.OK, (await owner.PutAsync($"/v1/backups/{id}", Content())).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await owner.PutAsync($"/v1/backups/{id}", Content(Encoding.UTF8.GetBytes(
            Encoding.UTF8.GetString(_archive).Replace("1700000000", "1700000001"))))).StatusCode);
        Assert.Equal(_archive, await owner.GetByteArrayAsync($"/v1/backups/{id}"));
        Assert.Single((await owner.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
        Assert.Empty((await other.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
        Assert.Equal(HttpStatusCode.NotFound, (await other.GetAsync($"/v1/backups/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await other.DeleteAsync($"/v1/backups/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await owner.DeleteAsync($"/v1/backups/{id}")).StatusCode);
        Assert.Empty((await owner.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
    }

    /// <summary>Backend разрешает работу со своей копией без scopes; их наличие не даёт доступ к чужой.</summary>
    [Theory]
    [InlineData(null)]
    [InlineData("profile")]
    [InlineData("backups admin")]
    public async Task BackendAccessUsesLocalOwnershipInsteadOfScopesAsync(string? scope)
    {
        using var factory = new BackendFactory();
        using var owner = factory.Client(Guid.NewGuid().ToString(), scope: scope);
        using var other = factory.Client(Guid.NewGuid().ToString(), scope: "admin backups");
        var id = Guid.NewGuid();
        using var created = await owner.PutAsync($"/v1/backups/{id}", Content());
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        Assert.Equal(_archive, await owner.GetByteArrayAsync($"/v1/backups/{id}"));
        using var deniedRead = await other.GetAsync($"/v1/backups/{id}");
        using var deniedDelete = await other.DeleteAsync($"/v1/backups/{id}");
        Assert.Equal(HttpStatusCode.NotFound, deniedRead.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, deniedDelete.StatusCode);
        Assert.Equal(_archive, await owner.GetByteArrayAsync($"/v1/backups/{id}"));
    }

    /// <summary>Отвергает отсутствие bearer, неверные audience/подпись и истёкший JWT.</summary>
    [Fact]
    public async Task RejectsUnauthenticatedWrongAudienceSignatureAndExpiredTokensAsync()
    {
        using var factory = new BackendFactory();
        var id = Guid.NewGuid().ToString();
        using var anonymous = factory.Client();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/v1/backups")).StatusCode);
        using var wrongAudience = factory.Client(id, audience: "another-api");
        Assert.Equal(HttpStatusCode.Unauthorized, (await wrongAudience.GetAsync("/v1/backups")).StatusCode);
        using var expired = factory.Client(id, expires: DateTime.UtcNow.AddMinutes(-10));
        Assert.Equal(HttpStatusCode.Unauthorized, (await expired.GetAsync("/v1/backups")).StatusCode);
        using var rsa = RSA.Create(2048);
        using var wrongSignature = factory.Client(id, key: new RsaSecurityKey(rsa) { KeyId = "other" });
        Assert.Equal(HttpStatusCode.Unauthorized, (await wrongSignature.GetAsync("/v1/backups")).StatusCode);
    }

    /// <summary>Архив ровно в 30 MiB сохраняется и скачивается без изменения байтов.</summary>
    [Fact]
    public async Task AcceptsAndDownloadsArchiveAtThirtyMiBLimitAsync()
    {
        // Arrange: валидный JSON с допустимыми пробелами до точной границы размера.
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var id = Guid.NewGuid();
        var payload = new byte[30 * 1024 * 1024];
        payload.AsSpan().Fill((byte)' ');
        _archive.CopyTo(payload, 0);

        // Act: сохраняем копию и читаем её через те же публичные маршруты.
        using var upload = await client.PutAsync($"/v1/backups/{id}", Content(payload));
        using var download = await client.GetAsync($"/v1/backups/{id}");

        // Assert: метаданные и скачанное содержимое совпадают с исходным архивом.
        Assert.Equal(HttpStatusCode.Created, upload.StatusCode);
        var info = Assert.IsType<BackupInfo>(await upload.Content.ReadFromJsonAsync<BackupInfo>());
        Assert.Equal(payload.Length, info.Size);
        Assert.Equal(Convert.ToHexStringLower(SHA256.HashData(payload)), info.Sha256);
        Assert.Equal(HttpStatusCode.OK, download.StatusCode);
        Assert.Equal(payload, await download.Content.ReadAsByteArrayAsync());
    }

    /// <summary>Ошибки архива и превышение квоты не изменяют ранее сохранённые копии.</summary>
    [Fact]
    public async Task RejectsMalformedOversizedUnsupportedArchivesAndQuotaWithoutEvictingBackupsAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content("{}"u8.ToArray()))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content(
            Encoding.UTF8.GetBytes(Encoding.UTF8.GetString(_archive).Replace("\"version\":4", "\"version\":99"))))).StatusCode);
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}",
            Content(new byte[30 * 1024 * 1024 + 1]))).StatusCode);
        for (var index = 0; index < 10; index++)
            Assert.Equal(HttpStatusCode.Created, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content())).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content())).StatusCode);
        Assert.Equal(10, (await client.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!.Length);
    }

    /// <summary>Очистка требует внутренний ключ, повторяется безопасно и запрещает последующие PUT.</summary>
    [Fact]
    public async Task AccountCleanupRequiresServiceCredentialAndBlocksUploadsWithOldAccessTokensAsync()
    {
        using var factory = new BackendFactory();
        var id = Guid.NewGuid().ToString();
        using var client = factory.Client(id);
        Assert.Equal(HttpStatusCode.Created, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content())).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.DeleteAsync($"/internal/users/{id}/backups")).StatusCode);
        client.DefaultRequestHeaders.Add("X-Service-Key", BackendFactory.ServiceKey);
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/internal/users/{id}/backups")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/internal/users/{id}/backups")).StatusCode);
        Assert.Empty((await client.GetFromJsonAsync<BackupInfo[]>("/v1/backups"))!);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PutAsync($"/v1/backups/{Guid.NewGuid()}", Content())).StatusCode);
    }
}
