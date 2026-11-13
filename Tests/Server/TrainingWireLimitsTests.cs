using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using FitLife.Backend;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace FitLife.Server.Tests;

/// <summary>Проверяет реальные потоки HTTP, точную границу тела, отмену и ограничение размера страниц.</summary>
[Trait("Category", "HTTP")]
public sealed class TrainingWireLimitsTests
{
    /// <summary>Ровно 30 MiB принимаются; лишний байт отклоняется также без Content-Length.</summary>
    [Theory]
    [InlineData(0, true)]
    [InlineData(1, true)]
    [InlineData(1, false)]
    public async Task EnforcesBodyLimitWithAndWithoutKnownLengthAsync(int extra, bool knownLength)
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var mutation = TrainingTestData.Weight();
        var prefix = JsonSerializer.SerializeToUtf8Bytes(new[] { mutation }, TrainingJson.Options);
        using var content = new PaddedContent(prefix, TrainingStorage.MaximumBytes + extra, knownLength);
        using var response = await client.PostAsync("/v1/training/changes", content);
        Assert.Equal(extra == 0 ? HttpStatusCode.OK : HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
        var page = await client.GetFromJsonAsync<TrainingPage>("/v1/training/changes", TrainingJson.Options);
        Assert.NotNull(page);
        if (extra == 0) Assert.Equal(mutation.Id, Assert.Single(page.Changes).Id);
        else Assert.Empty(page.Changes);
    }

    /// <summary>Отмена незавершённого chunked body не оставляет пользовательских записей.</summary>
    [Fact]
    public async Task CancellationDuringStreamingBodyDoesNotWriteAnythingAsync()
    {
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        using var cancellation = new CancellationTokenSource();
        using var content = new WaitingContent(cancellation.Token);
        var pending = client.PostAsync("/v1/training/changes", content, cancellation.Token);
        await content.Started.Task;
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending);
        await using var scope = factory.Services.CreateAsyncScope();
        var database = scope.ServiceProvider.GetRequiredService<BackupDbContext>();
        Assert.Empty(await database.TrainingOwners.ToListAsync());
        Assert.Empty(await database.TrainingRecords.ToListAsync());
    }

    /// <summary>Две большие записи разделяются по байтовому бюджету даже при limit=100, без потери курсора.</summary>
    [Fact]
    public async Task PageByteBudgetSplitsLargeRecordsWithoutOmissionAsync()
    {
        // Arrange: две допустимые записи вместе превышают байтовый бюджет одной страницы.
        using var factory = new BackendFactory();
        using var client = factory.Client(Guid.NewGuid().ToString());
        var original = TrainingTestData.Mutation(TrainingKinds.Workout);
        var first = TrainingTestData.Edit(original, value => value["notes"] = new string('a', 16 * 1024 * 1024));
        var secondId = Guid.NewGuid();
        var second = TrainingTestData.Edit(first with { Id = secondId }, value => value["id"] = secondId);
        var savedFirst = Assert.Single(await TrainingTestData.SendAsync(client, first));
        var savedSecond = Assert.Single(await TrainingTestData.SendAsync(client, second));
        // Act: размер limit не должен обходить ограничение тела ответа.
        using var response = await client.GetAsync("/v1/training/changes?after=0&limit=100");
        var bytes = await response.Content.ReadAsByteArrayAsync();
        response.EnsureSuccessStatusCode();
        // Assert: курсор продолжает чтение со второй записи, без повторов и пропусков.
        Assert.True(bytes.Length < 32 * 1024 * 1024);
        var page = JsonSerializer.Deserialize<TrainingPage>(bytes, TrainingJson.Options)!;
        Assert.Equal(first.Id, Assert.Single(page.Changes).Id);
        Assert.True(page.HasMore);
        Assert.Equal(savedFirst.Revision, page.Cursor);
        var next = await client.GetFromJsonAsync<TrainingPage>($"/v1/training/changes?after={page.Cursor}&limit=100", TrainingJson.Options);
        Assert.NotNull(next);
        Assert.Equal(second.Id, Assert.Single(next.Changes).Id);
        Assert.Equal(savedSecond.Revision, next.Cursor);
        Assert.False(next.HasMore);
    }

    /// <summary>Генерирует хвост пробелов постепенно, не создавая 30 MiB буфер на стороне тестового клиента.</summary>
    private sealed class PaddedContent : HttpContent
    {
        private readonly byte[] _prefix;
        private readonly long _totalBytes;
        private readonly bool _knownLength;
        /// <summary>Задаёт фактический JSON Content-Type для проверки прикладного reader.</summary>
        internal PaddedContent(byte[] prefix, long totalBytes, bool knownLength)
        {
            _prefix = prefix; _totalBytes = totalBytes; _knownLength = knownLength;
            Headers.ContentType = new MediaTypeHeaderValue("application/json");
        }

        /// <summary>Покрывает обычную и потоковую передачу одного и того же тела.</summary>
        protected override bool TryComputeLength(out long length) { length = _totalBytes; return _knownLength; }

        /// <summary>Поддерживает transport, использующий старую сигнатуру HttpContent.</summary>
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) => WriteAsync(stream, CancellationToken.None);

        /// <summary>Передаёт отмену до каждого следующего чанка.</summary>
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context, CancellationToken cancellationToken) => WriteAsync(stream, cancellationToken);

        /// <summary>Пишет валидный JSON и ограниченный фиксированный буфер whitespace.</summary>
        private async Task WriteAsync(Stream stream, CancellationToken cancellationToken)
        {
            await stream.WriteAsync(_prefix, cancellationToken);
            var buffer = new byte[65_536];
            Array.Fill(buffer, (byte)' ');
            for (var remaining = _totalBytes - _prefix.Length; remaining > 0;)
            {
                var count = (int)Math.Min(buffer.Length, remaining);
                await stream.WriteAsync(buffer.AsMemory(0, count), cancellationToken);
                remaining -= count;
            }
        }
    }

    /// <summary>Оставляет тело недописанным до явной отмены, без задержек и внешней сети.</summary>
    private sealed class WaitingContent : HttpContent
    {
        private readonly CancellationToken _cancellationToken;
        /// <summary>Сигнализирует начало чтения тела тестовым host.</summary>
        internal TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        /// <summary>Привязывает ожидание к токену сценария также для transport без cancellation overload.</summary>
        internal WaitingContent(CancellationToken cancellationToken)
        {
            _cancellationToken = cancellationToken;
            Headers.ContentType = new MediaTypeHeaderValue("application/json");
        }
        /// <summary>Имитирует chunked передачу без Content-Length.</summary>
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
        /// <summary>Пишет начало пакета и ожидает явную отмену сценария.</summary>
        protected override async Task SerializeToStreamAsync(Stream stream, TransportContext? context)
        {
            await stream.WriteAsync("["u8.ToArray(), _cancellationToken);
            Started.TrySetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, _cancellationToken);
        }
    }
}
