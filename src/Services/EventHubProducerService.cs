using LogsysNgPoC.Models;
using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;
using Microsoft.Extensions.Logging;
using System.Text.Json;

namespace LogsysNgPoC.Services;

public interface IEventHubProducerService
{
    Task<bool> PublishEventAsync(LogEvent logEvent);
    Task<int> PublishEventBatchAsync(IEnumerable<LogEvent> logEvents);
}

public class EventHubProducerService : IEventHubProducerService
{
    private readonly EventHubProducerClient _producerClient;
    private readonly ILogger<EventHubProducerService> _logger;

    public EventHubProducerService(EventHubProducerClient producerClient, ILogger<EventHubProducerService> logger)
    {
        _producerClient = producerClient ?? throw new ArgumentNullException(nameof(producerClient));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    /// <summary>
    /// Publish a single event. The SDK handles automatic batching internally.
    /// </summary>
    public async Task<bool> PublishEventAsync(LogEvent logEvent)
    {
        try
        {
            var json = JsonSerializer.Serialize(logEvent);
            var eventData = new EventData(json);
            
            // SendAsync automatically batches events internally
            await _producerClient.SendAsync(new[] { eventData });
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish event {EventId}", logEvent.Id);
            return false;
        }
    }

    /// <summary>
    /// Publish a batch of events using CreateBatchAsync for optimal SDK-managed batching.
    /// This is the best practice approach - the SDK handles all batching logic, size limits, and serialization.
    /// </summary>
    public async Task<int> PublishEventBatchAsync(IEnumerable<LogEvent> logEvents)
    {
        var eventList = logEvents.ToList();
        if (!eventList.Any())
            return 0;

        try
        {
            var successCount = 0;
            var remaining = eventList.ToList();

            // Keep creating batches until all events are sent
            while (remaining.Count > 0)
            {
                // CreateBatchAsync respects the maximum message size and partition limits
                using (var eventBatch = await _producerClient.CreateBatchAsync())
                {
                    var batchedCount = 0;

                    // Add events to batch until it's full or we run out of events
                    while (remaining.Count > 0)
                    {
                        var json = JsonSerializer.Serialize(remaining[0]);
                        var eventData = new EventData(json);

                        // TryAdd returns false if the batch is full
                        if (!eventBatch.TryAdd(eventData))
                        {
                            // Batch is full, send it
                            break;
                        }

                        batchedCount++;
                        successCount++;
                        remaining.RemoveAt(0);
                    }

                    // Send the batch
                    if (batchedCount > 0)
                    {
                        await _producerClient.SendAsync(eventBatch);
                        _logger.LogDebug("Sent batch of {BatchSize} events", batchedCount);
                    }
                }
            }

            return successCount;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish event batch of {Count} events", eventList.Count);
            return 0;
        }
    }
}
