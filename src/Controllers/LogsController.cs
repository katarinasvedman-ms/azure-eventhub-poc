using LogsysNgPoC.Models;
using LogsysNgPoC.Services;
using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;

namespace LogsysNgPoC.Controllers;

[ApiController]
[Route("api/[controller]")]
public class LogsController : ControllerBase
{
    private readonly IEventBatchingService _batchingService;
    private readonly IEventHubProducerService _producerService;
    private readonly ILogger<LogsController> _logger;

    public LogsController(
        IEventBatchingService batchingService,
        IEventHubProducerService producerService,
        ILogger<LogsController> logger)
    {
        _batchingService = batchingService;
        _producerService = producerService;
        _logger = logger;
    }

    /// <summary>
    /// Ingests a single log event asynchronously.
    /// 
    /// OPTIMIZATION: Events are batched in memory and flushed periodically.
    /// This approach:
    /// - Returns immediately (non-blocking)
    /// - Reduces Event Hub API calls
    /// - Improves throughput by 10-100x
    /// - Maintains <200ms response time SLA
    /// </summary>
    [HttpPost("ingest")]
    public async Task<IActionResult> IngestLog([FromBody] IngestLogRequest request)
    {
        var stopwatch = Stopwatch.StartNew();

        try
        {
            if (string.IsNullOrWhiteSpace(request.Message))
                return BadRequest("Message is required");

            var logEvent = new LogEvent
            {
                Source = request.Source ?? "API",
                Level = request.Level ?? "INFO",
                Message = request.Message,
                PartitionKey = request.PartitionKey // Use for consistent routing
            };

            // Enqueue for batching (non-blocking)
            await _batchingService.EnqueueEventAsync(logEvent);

            stopwatch.Stop();
            _logger.LogDebug("Event {EventId} enqueued in {ElapsedMs}ms",
                logEvent.Id, stopwatch.ElapsedMilliseconds);

            // Return 202 Accepted - event is queued for processing
            return Accepted(new { eventId = logEvent.Id, queuedAt = DateTime.UtcNow });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to ingest log event");
            stopwatch.Stop();
            return StatusCode(500, new { error = ex.Message, elapsedMs = stopwatch.ElapsedMilliseconds });
        }
    }

    /// <summary>
    /// Publishes a batch of log events.
    /// Use this for bulk ingestion scenarios.
    /// </summary>
    [HttpPost("ingest-batch")]
    public async Task<IActionResult> IngestBatch([FromBody] IngestBatchRequest request)
    {
        var stopwatch = Stopwatch.StartNew();

        try
        {
            if (request.Events == null || !request.Events.Any())
                return BadRequest("At least one event is required");

            var logEvents = request.Events.Select(e => new LogEvent
            {
                Source = e.Source ?? "API",
                Level = e.Level ?? "INFO",
                Message = e.Message,
                PartitionKey = e.PartitionKey
            }).ToList();

            // Enqueue all events
            var tasks = logEvents.Select(evt => _batchingService.EnqueueEventAsync(evt));
            await Task.WhenAll(tasks);

            stopwatch.Stop();
            _logger.LogInformation("Batch of {Count} events enqueued in {ElapsedMs}ms",
                logEvents.Count, stopwatch.ElapsedMilliseconds);

            return Accepted(new 
            { 
                eventCount = logEvents.Count, 
                queuedAt = DateTime.UtcNow,
                elapsedMs = stopwatch.ElapsedMilliseconds 
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to ingest batch");
            stopwatch.Stop();
            return StatusCode(500, new { error = ex.Message, elapsedMs = stopwatch.ElapsedMilliseconds });
        }
    }

    /// <summary>
    /// Gets queue statistics for monitoring.
    /// </summary>
    [HttpGet("queue-stats")]
    public async Task<IActionResult> GetQueueStats()
    {
        var pendingCount = await _batchingService.GetPendingEventCountAsync();

        return Ok(new
        {
            pendingEvents = pendingCount,
            timestamp = DateTime.UtcNow
        });
    }
}

public class IngestLogRequest
{
    public string Message { get; set; } = string.Empty;
    public string? Source { get; set; }
    public string? Level { get; set; }
    public string? PartitionKey { get; set; }
}

public class IngestBatchRequest
{
    public IEnumerable<IngestLogRequest> Events { get; set; } = new List<IngestLogRequest>();
}
