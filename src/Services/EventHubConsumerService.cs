using LogsysNgPoC.Models;
using Microsoft.Extensions.Logging;

namespace LogsysNgPoC.Services;

public interface IEventHubConsumerService
{
    Task StartProcessingAsync();
    Task StopProcessingAsync();
}

public class EventHubConsumerService : IEventHubConsumerService
{
    private readonly ILogger<EventHubConsumerService> _logger;

    public EventHubConsumerService(ILogger<EventHubConsumerService> logger)
    {
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    public Task StartProcessingAsync()
    {
        _logger.LogInformation("Consumer started processing events");
        return Task.CompletedTask;
    }

    public Task StopProcessingAsync()
    {
        _logger.LogInformation("Consumer stopped processing events");
        return Task.CompletedTask;
    }
}
