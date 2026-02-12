using MetricSysPoC.Models;
using System.Collections.Concurrent;
using Microsoft.Extensions.Logging;
using System.Diagnostics;

namespace MetricSysPoC.Services;

public interface IEventBatchingService
{
    Task EnqueueEventAsync(LogEvent logEvent);
    Task<int> GetPendingEventCountAsync();
    event EventHandler<BatchReadyEventArgs>? BatchReady;
}

public class BatchReadyEventArgs : EventArgs
{
    public IReadOnlyList<LogEvent> Events { get; set; } = new List<LogEvent>();
    public int BatchSize { get; set; }
    public string? CorrelationId { get; set; }
}

public class EventBatchingService : IEventBatchingService, IDisposable
{
    private readonly ConcurrentQueue<LogEvent> _eventQueue = new();
    private readonly Timer _batchTimer;
    private readonly int _batchSize;
    private readonly int _batchTimeoutMs;
    private readonly ILogger<EventBatchingService> _logger;

    public event EventHandler<BatchReadyEventArgs>? BatchReady;

    public EventBatchingService(ILogger<EventBatchingService> logger)
    {
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _batchSize = 500;
        _batchTimeoutMs = 100;
        _batchTimer = new Timer(CheckAndFlushBatch, null, TimeSpan.FromMilliseconds(_batchTimeoutMs), TimeSpan.FromMilliseconds(_batchTimeoutMs));
    }

    public Task EnqueueEventAsync(LogEvent logEvent)
    {
        try
        {
            // Input validation
            if (logEvent == null)
            {
                _logger.LogWarning("Attempted to enqueue null event");
                throw new ArgumentNullException(nameof(logEvent), "Log event cannot be null");
            }
            
            if (string.IsNullOrWhiteSpace(logEvent.Message))
            {
                _logger.LogWarning("Attempted to enqueue event with empty message");
                throw new ArgumentException("Log event message cannot be empty", nameof(logEvent.Message));
            }
            
            if (string.IsNullOrWhiteSpace(logEvent.Source))
            {
                _logger.LogWarning("Attempted to enqueue event with empty source");
                throw new ArgumentException("Log event source cannot be empty", nameof(logEvent.Source));
            }

            _eventQueue.Enqueue(logEvent);
            
            if (_eventQueue.Count >= _batchSize)
            {
                CheckAndFlushBatch(null);
            }
            
            return Task.CompletedTask;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error enqueuing event {EventId}", logEvent?.Id);
            throw;
        }
    }

    public Task<int> GetPendingEventCountAsync()
    {
        return Task.FromResult(_eventQueue.Count);
    }

    private void CheckAndFlushBatch(object? state)
    {
        try
        {
            if (_eventQueue.TryDequeue(out var firstEvent))
            {
                // Pre-allocate list to reduce allocations
                var batch = new List<LogEvent>(_batchSize) { firstEvent };
                var correlationId = Activity.Current?.Id ?? Guid.NewGuid().ToString();
                
                while (_eventQueue.TryDequeue(out var logEvent) && batch.Count < _batchSize)
                {
                    batch.Add(logEvent);
                }

                if (batch.Any())
                {
                    _logger.LogDebug("Flushing batch of {BatchSize} events (CorrelationId: {CorrelationId})", batch.Count, correlationId);
                    BatchReady?.Invoke(this, new BatchReadyEventArgs 
                    { 
                        Events = batch.AsReadOnly(),
                        BatchSize = batch.Count,
                        CorrelationId = correlationId
                    });
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking and flushing batch");
        }
    }

    public void Dispose()
    {
        _batchTimer?.Dispose();
    }
}
