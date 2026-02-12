namespace MetricSysPoC.Models;

/// <summary>
/// Represents a log event to be sent to Event Hub.
/// Keep this lightweight to optimize serialization performance.
/// </summary>
public class LogEvent
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    public string Source { get; set; } = string.Empty;
    public string Level { get; set; } = "INFO";
    public string Message { get; set; } = string.Empty;
    public string? PartitionKey { get; set; }
    public Dictionary<string, string>? Metadata { get; set; }
}

/// <summary>
/// DTO for external API contracts - prevents leaking internal domain models.
/// </summary>
public class LogEventDto
{
    public string? Id { get; set; }
    public DateTime Timestamp { get; set; }
    public string? Source { get; set; }
    public string? Level { get; set; }
    public string? Message { get; set; }
    public string? PartitionKey { get; set; }
}

/// <summary>
/// Response DTO for batch operations with correlation tracking.
/// </summary>
public class PublishResponseDto
{
    public int SuccessCount { get; set; }
    public int FailureCount { get; set; }
    public string? CorrelationId { get; set; }
    public string? Message { get; set; }
}
