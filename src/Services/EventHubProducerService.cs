using MetricSysPoC.Models;
using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using System.Diagnostics;

namespace MetricSysPoC.Services;

public interface IEventHubProducerService
{
    Task<bool> PublishEventAsync(LogEvent logEvent, string? correlationId = null);
    Task<PublishResponseDto> PublishEventBatchAsync(IEnumerable<LogEvent> logEvents, string? correlationId = null);
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
    /// Publish a single event with input validation and correlation tracking.
    /// </summary>
    public async Task<bool> PublishEventAsync(LogEvent logEvent, string? correlationId = null)
    {
        try
        {
            // Input validation
            if (logEvent == null)
            {
                _logger.LogWarning("Attempted to publish null event");
                throw new ArgumentNullException(nameof(logEvent), "Log event cannot be null");
            }
            
            if (string.IsNullOrWhiteSpace(logEvent.Message))
            {
                _logger.LogWarning("Attempted to publish event with empty message");
                throw new ArgumentException("Log event message cannot be empty", nameof(logEvent.Message));
            }

            correlationId ??= Activity.Current?.Id ?? Guid.NewGuid().ToString();
            
            var json = JsonSerializer.Serialize(logEvent);
            var eventData = new EventData(json);
            eventData.Properties["CorrelationId"] = correlationId;
            
            // SendAsync automatically batches events internally
            await _producerClient.SendAsync(new[] { eventData });
            
            _logger.LogDebug("Published event {EventId} with CorrelationId {CorrelationId}", logEvent.Id, correlationId);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish event {EventId} with CorrelationId {CorrelationId}", logEvent?.Id, correlationId);
            return false;
        }
    }

    /// <summary>
    /// Publish a batch of events with SDK-managed batching and comprehensive error handling.
    /// </summary>
    public async Task<PublishResponseDto> PublishEventBatchAsync(IEnumerable<LogEvent> logEvents, string? correlationId = null)
    {
        var eventList = logEvents?.ToList() ?? new List<LogEvent>();
        correlationId ??= Activity.Current?.Id ?? Guid.NewGuid().ToString();
        
        var response = new PublishResponseDto { CorrelationId = correlationId };

        if (!eventList.Any())
        {
            _logger.LogWarning("Attempted to publish empty batch with CorrelationId {CorrelationId}", correlationId);
            response.Message = "Batch is empty";
            return response;
        }

        try
        {
            var successCount = 0;
            var failureCount = 0;
            var remaining = new List<LogEvent>(eventList);

            // Keep creating batches until all events are sent
            while (remaining.Count > 0)
            {
                try
                {
                    using (var eventBatch = await _producerClient.CreateBatchAsync())
                    {
                        var batchedCount = 0;

                        // Add events to batch until it's full or we run out of events
                        while (remaining.Count > 0)
                        {
                            // Validate before adding
                            var evt = remaining[0];
                            if (string.IsNullOrWhiteSpace(evt.Message))
                            {
                                _logger.LogWarning("Skipping invalid event {EventId} - empty message", evt.Id);
                                remaining.RemoveAt(0);
                                failureCount++;
                                continue;
                            }

                            var json = JsonSerializer.Serialize(evt);
                            var eventData = new EventData(json);
                            eventData.Properties["CorrelationId"] = correlationId;

                            // TryAdd returns false if the batch is full
                            if (!eventBatch.TryAdd(eventData))
                            {
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
                            _logger.LogDebug("Sent batch of {BatchSize} events (CorrelationId: {CorrelationId})", batchedCount, correlationId);
                        }
                    }
                }
                catch (Exception batchEx)
                {
                    _logger.LogError(batchEx, "Failed to send event batch (CorrelationId: {CorrelationId})", correlationId);
                    failureCount += remaining.Count;
                    break;
                }
            }

            response.SuccessCount = successCount;
            response.FailureCount = failureCount;
            response.Message = $"Published {successCount} events, {failureCount} failed";
            
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish event batch (CorrelationId: {CorrelationId})", correlationId);
            response.SuccessCount = 0;
            response.FailureCount = eventList.Count;
            response.Message = $"Batch operation failed: {ex.Message}";
            return response;
        }
    }
}
