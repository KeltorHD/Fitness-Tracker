using System.Collections.Concurrent;
using FitnessTracker.Authentication;

namespace FitnessTracker.Server.Tests;

/// <summary>Хранит только синтетические письма изолированных тестов, не обращается к SMTP.</summary>
internal sealed class TestEmailSender : IAccountEmailSender
{
    /// <summary>Письма с синтетическими адресами и токенами одноразового host.</summary>
    internal ConcurrentQueue<(string Email, string Link)> Messages { get; } = new();
    /// <summary>Управляемый безопасный отказ транспорта.</summary>
    internal bool Fails { get; set; }

    /// <summary>Учитывает отмену и имитирует принятый SMTP либо недоступность.</summary>
    public Task SendConfirmationAsync(string email, string confirmationLink, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (Fails) throw new EmailDeliveryException("smtp_unavailable");
        Messages.Enqueue((email, confirmationLink));
        return Task.CompletedTask;
    }
}
