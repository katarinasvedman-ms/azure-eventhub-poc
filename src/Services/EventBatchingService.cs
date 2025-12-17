using MetricSysPoC.Models;
using System.Collections.Concurrent;

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
}

public class EventBatchingService : IEventBatchingService, IDisposable
{
    private readonly ConcurrentQueue<LogEvent> _eventQueue = new();
    private readonly Timer _batchTimer;
    private readonly int _batchSize;
    private readonly int _batchTimeoutMs;

    public event EventHandler<BatchReadyEventArgs>? BatchReady;

    public EventBatchingService()
    {
        _batchSize = 500;
        _batchTimeoutMs = 100;
        _batchTimer = new Timer(CheckAndFlushBatch, null, TimeSpan.FromMilliseconds(_batchTimeoutMs), TimeSpan.FromMilliseconds(_batchTimeoutMs));
    }

    public Task EnqueueEventAsync(LogEvent logEvent)
    {
        _eventQueue.Enqueue(logEvent);
        
        if (_eventQueue.Count >= _batchSize)
        {
            CheckAndFlushBatch(null);
        }
        
        return Task.CompletedTask;
    }

    public Task<int> GetPendingEventCountAsync()
    {
        return Task.FromResult(_eventQueue.Count);
    }

    private void CheckAndFlushBatch(object? state)
    {
        if (_eventQueue.TryDequeue(out var firstEvent))
        {
            var batch = new List<LogEvent> { firstEvent };
            
            while (_eventQueue.TryDequeue(out var logEvent) && batch.Count < _batchSize)
            {
                batch.Add(logEvent);
            }

            if (batch.Any())
            {
                BatchReady?.Invoke(this, new BatchReadyEventArgs 
                { 
                    Events = batch.AsReadOnly(),
                    BatchSize = batch.Count
                });
            }
        }
    }

    public void Dispose()
    {
        _batchTimer?.Dispose();
    }
}
