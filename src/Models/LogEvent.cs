namespace LogsysNgPoC.Models;

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
