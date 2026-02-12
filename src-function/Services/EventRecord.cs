namespace EventHubFunction.Services;

/// <summary>
/// Represents a single deserialized event ready for SQL persistence.
/// </summary>
public class EventRecord
{
    /// <summary>
    /// Stable, deterministic event ID used as the idempotency key.
    /// Must be unique per logical event (set by producer or derived from partition+sequence).
    /// </summary>
    public required string EventId { get; set; }

    public required string Source { get; set; }
    public required string Level { get; set; }
    public required string Message { get; set; }
    public string? PartitionKey { get; set; }
    public DateTime Timestamp { get; set; }
    public DateTime EnqueuedTimeUtc { get; set; }
    public long SequenceNumber { get; set; }
}

/// <summary>
/// Result of a batch write operation, including idempotency metrics.
/// </summary>
public class BatchWriteResult
{
    public int InsertedCount { get; set; }
    public int DuplicateCount { get; set; }
    public int ErrorCount { get; set; }
}
