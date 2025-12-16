namespace LogsysNgPoC.Configuration;

public class EventHubOptions
{
    public string FullyQualifiedNamespace { get; set; } = string.Empty;
    public string HubName { get; set; } = string.Empty;
    public string ConsumerGroup { get; set; } = string.Empty;
    public string StorageConnectionString { get; set; } = string.Empty;
    public string StorageContainerName { get; set; } = string.Empty;
    public bool UseKeyAuthentication { get; set; }
    public int PartitionCount { get; set; } = 4;
}

public class ApiOptions
{
    public int BatchSize { get; set; } = 100;
    public int BatchTimeoutMs { get; set; } = 1000;
    public int MaxConcurrentPartitionProcessing { get; set; } = 10;
    public string PartitionAssignmentStrategy { get; set; } = "RoundRobin"; // RoundRobin or Affinity
}
