using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Consumer;
using Azure.Messaging.EventHubs.Processor;
using Azure.Storage.Blobs;
using MetricSysPoC.Models;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using System.Text.Json;

namespace MetricSysPoC.Services;

public interface IEventHubConsumerService
{
    Task StartProcessingAsync();
    Task StopProcessingAsync();
}

public class EventHubConsumerService : IEventHubConsumerService
{
    private readonly ILogger<EventHubConsumerService> _logger;
    private readonly ISqlPersistenceService _sqlService;
    private readonly EventProcessorClient _processorClient;

    public EventHubConsumerService(
        IConfiguration configuration,
        ILogger<EventHubConsumerService> logger,
        ISqlPersistenceService sqlService)
    {
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _sqlService = sqlService ?? throw new ArgumentNullException(nameof(sqlService));

        // Get Event Hub configuration
        var eventHubNamespace = configuration["EventHub:FullyQualifiedNamespace"];
        var eventHubName = configuration["EventHub:HubName"];
        var consumerGroup = configuration["EventHub:ConsumerGroup"];
        var storageConnectionString = configuration["EventHub:StorageConnectionString"];
        var storageContainerName = configuration["EventHub:StorageContainerName"];

        if (string.IsNullOrEmpty(eventHubNamespace) || string.IsNullOrEmpty(eventHubName))
            throw new InvalidOperationException("Event Hub configuration is missing");
        
        if (string.IsNullOrEmpty(storageConnectionString))
            throw new InvalidOperationException("Storage connection string is missing in configuration");

        // Initialize blob storage for checkpointing
        var blobContainerClient = new BlobContainerClient(
            new Uri($"https://{ExtractStorageAccountName(storageConnectionString)}.blob.core.windows.net/{storageContainerName}"),
            new Azure.Identity.DefaultAzureCredential());

        // Create Event Processor Client with checkpointing
        _processorClient = new EventProcessorClient(
            blobContainerClient,
            consumerGroup,
            eventHubNamespace,
            eventHubName,
            new Azure.Identity.DefaultAzureCredential());

        // Register event handlers
        _processorClient.ProcessEventAsync += ProcessEventHandler;
        _processorClient.ProcessErrorAsync += ProcessErrorHandler;
    }

    public async Task StartProcessingAsync()
    {
        try
        {
            _logger.LogInformation("Starting Event Hub consumer...");
            await _processorClient.StartProcessingAsync();
            _logger.LogInformation("Event Hub consumer started successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to start Event Hub consumer");
            throw;
        }
    }

    public async Task StopProcessingAsync()
    {
        try
        {
            _logger.LogInformation("Stopping Event Hub consumer...");
            await _processorClient.StopProcessingAsync();
            _logger.LogInformation("Event Hub consumer stopped successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to stop Event Hub consumer");
            throw;
        }
    }

    private async Task ProcessEventHandler(ProcessEventArgs eventArgs)
    {
        try
        {
            // Deserialize event data
            var eventBody = eventArgs.Data.EventBody.ToString();
            _logger.LogDebug("Processing event: {EventBody}", eventBody);

            // Try to parse as LogEvent
            var logEvent = JsonSerializer.Deserialize<LogEvent>(eventBody);
            if (logEvent == null)
            {
                _logger.LogWarning("Failed to deserialize event: {EventBody}", eventBody);
                await eventArgs.UpdateCheckpointAsync();
                return;
            }

            // Convert to SQL entry and persist
            var sqlEntry = new EventLogEntry
            {
                Source = logEvent.Source ?? "EventHub",
                Level = logEvent.Level ?? "INFO",
                Message = logEvent.Message,
                PartitionKey = logEvent.PartitionKey,
                Timestamp = DateTime.UtcNow
            };

            // Write to SQL Database using bulk insert (better for throughput)
            await _sqlService.BulkInsertEventsAsync(new List<EventLogEntry> { sqlEntry });

            // Update checkpoint after successful processing
            await eventArgs.UpdateCheckpointAsync();
            _logger.LogDebug("Event processed and checkpointed successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing event from partition {PartitionId}", eventArgs.Partition.PartitionId);
            // Don't update checkpoint - let it retry
            throw;
        }
    }

    private Task ProcessErrorHandler(ProcessErrorEventArgs eventArgs)
    {
        _logger.LogError(
            eventArgs.Exception,
            "Error occurred processing events: {ErrorDescription}",
            eventArgs.Exception?.Message ?? "Unknown error");

        return Task.CompletedTask;
    }

    private static string ExtractStorageAccountName(string connectionString)
    {
        var parts = connectionString.Split(';');
        foreach (var part in parts)
        {
            if (part.StartsWith("AccountName="))
                return part["AccountName=".Length..];
        }
        throw new InvalidOperationException("Could not extract storage account name from connection string");
    }
}
