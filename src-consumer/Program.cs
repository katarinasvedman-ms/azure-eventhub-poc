using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Processor;
using Azure.Storage.Blobs;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using System.Collections.Concurrent;
using System.Data;
using System.Text.Json;
using Azure.Identity;

// Configuration
var config = new ConfigurationBuilder()
    .AddJsonFile("appsettings.json", optional: false)
    .Build();

var logger = LoggerFactory.Create(builder => builder.AddConsole())
    .CreateLogger("EventHubConsumer");

// Define functions first
async Task CleanupDatabase()
{
    Console.WriteLine("\n╔════════════════════════════════════════════════════════════════════════════════╗");
    Console.WriteLine("║                       Database Cleanup Utility                                  ║");
    Console.WriteLine("╚════════════════════════════════════════════════════════════════════════════════╝\n");

    var sqlConnectionString = config["ConnectionStrings:SqlDatabase"];
    var sqlTokenProvider = new DefaultAzureCredential();

    try
    {
        using var connection = new SqlConnection(sqlConnectionString);
        var token = await sqlTokenProvider.GetTokenAsync(
            new Azure.Core.TokenRequestContext(new[] { "https://database.windows.net/.default" }));
        connection.AccessToken = token.Token;
        await connection.OpenAsync();
        Console.WriteLine("✅ Connected to database\n");

        // Check current size
        using (var cmd = new SqlCommand(@"
            SELECT 
                COUNT(*) AS TotalEvents,
                CAST(SUM(DATALENGTH(Message)) / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS DataSizeMB
            FROM [dbo].[EventLogs]", connection))
        {
            using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                var count = reader.GetInt32(0);
                var sizeMb = reader.IsDBNull(1) ? 0 : reader.GetDecimal(1);
                Console.WriteLine($"📊 Before cleanup:");
                Console.WriteLine($"   Events: {count:N0}");
                Console.WriteLine($"   Data size: ~{sizeMb} MB\n");
            }
        }

        // Delete all events
        using (var cmd = new SqlCommand("DELETE FROM [dbo].[EventLogs]", connection))
        {
            var deleted = await cmd.ExecuteNonQueryAsync();
            Console.WriteLine($"🗑️  Deleted {deleted:N0} events\n");
        }

        // Check size after
        using (var cmd = new SqlCommand(@"
            SELECT COUNT(*) FROM [dbo].[EventLogs]", connection))
        {
            var remaining = (int)await cmd.ExecuteScalarAsync();
            Console.WriteLine($"✅ After cleanup: {remaining:N0} events\n");
        }

        // Shrink database to reclaim space
        Console.WriteLine("📦 Shrinking database to reclaim space...");
        using (var cmd = new SqlCommand("DBCC SHRINKDATABASE (0, 10)", connection))
        {
            cmd.CommandTimeout = 600;
            await cmd.ExecuteNonQueryAsync();
        }
        Console.WriteLine("✅ Database shrunk\n");

        Console.WriteLine("╔════════════════════════════════════════════════════════════════════════════════╗");
        Console.WriteLine("║                  ✨ Cleanup complete! Ready for new events.                   ║");
        Console.WriteLine("╚════════════════════════════════════════════════════════════════════════════════╝");
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"\n❌ Error: {ex.Message}");
        Environment.Exit(1);
    }
}

// Check for command line arguments
bool skipDatabase = args.Length > 0 && args[0] == "--no-db";

// Check for cleanup mode
if (args.Length > 0 && args[0] == "--cleanup")
{
    await CleanupDatabase();
    return;
}

// Event Hub config
var eventHubNamespace = config["EventHub:FullyQualifiedNamespace"];
var eventHubName = config["EventHub:HubName"];
var consumerGroup = config["EventHub:ConsumerGroup"];
var storageConnectionString = config["EventHub:StorageConnectionString"];
var storageContainerName = config["EventHub:StorageContainerName"];
var sqlConnectionString = config["ConnectionStrings:SqlDatabase"];

if (string.IsNullOrEmpty(eventHubNamespace) || string.IsNullOrEmpty(eventHubName))
{
    logger.LogError("Event Hub configuration is missing");
    return;
}

// Get SQL token provider for Azure AD authentication
var sqlTokenProvider = new DefaultAzureCredential();

logger.LogInformation("Starting Event Hub Consumer...");
logger.LogInformation("Event Hub: {EventHub}", eventHubName);
logger.LogInformation("Consumer Group: {ConsumerGroup}", consumerGroup);
if (skipDatabase) logger.LogInformation("⚠️  Database writes disabled (--no-db mode)");

// Initialize database schema if needed
if (!skipDatabase)
{
    try
    {
        using var initConn = new SqlConnection(sqlConnectionString);
        var token = await sqlTokenProvider.GetTokenAsync(
            new Azure.Core.TokenRequestContext(new[] { "https://database.windows.net/.default" }));
        initConn.AccessToken = token.Token;
        await initConn.OpenAsync();
        
        const string createTableSql = @"
        IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[EventLogs]') AND type in (N'U'))
        CREATE TABLE [dbo].[EventLogs] (
            [EventId] BIGINT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
            [Source] NVARCHAR(100) NOT NULL,
            [Level] NVARCHAR(50) NOT NULL,
            [Message] NVARCHAR(MAX) NOT NULL,
            [PartitionKey] NVARCHAR(100),
            [Timestamp] DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
            [CreatedAt] DATETIME2(7) NOT NULL DEFAULT GETUTCDATE()
        );
        IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_EventLogs_Timestamp')
            CREATE NONCLUSTERED INDEX [IX_EventLogs_Timestamp] ON [dbo].[EventLogs]([Timestamp] DESC);
        IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_EventLogs_Level')
            CREATE NONCLUSTERED INDEX [IX_EventLogs_Level] ON [dbo].[EventLogs]([Level]) INCLUDE ([Message], [Timestamp]);
        IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_EventLogs_PartitionKey')
            CREATE NONCLUSTERED INDEX [IX_EventLogs_PartitionKey] ON [dbo].[EventLogs]([PartitionKey]) INCLUDE ([Level], [Timestamp]);
    ";
    
    using var initCmd = new SqlCommand(createTableSql, initConn);
    await initCmd.ExecuteNonQueryAsync();
    logger.LogInformation("Database schema initialized");
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error initializing schema (table may already exist): {Message}", ex.Message);
    }
}
else
{
    logger.LogInformation("Skipping database schema initialization");
}

// Initialize blob storage for checkpointing
var blobContainerClient = new BlobContainerClient(
    new Uri($"https://{ExtractStorageAccountName(storageConnectionString)}.blob.core.windows.net/{storageContainerName}"),
    new Azure.Identity.DefaultAzureCredential());

// Create Event Processor Client
var processorClient = new EventProcessorClient(
    blobContainerClient,
    consumerGroup,
    eventHubNamespace,
    eventHubName,
    new DefaultAzureCredential());

// Set to start from latest position when no checkpoint exists
processorClient.PartitionInitializingAsync += args =>
{
    logger.LogInformation("Partition {PartitionId} initializing - starting from Latest", args.PartitionId);
    return Task.CompletedTask;
};

// Metrics
long eventsProcessed = 0;
long eventsFailedSQL = 0;
long eventsBatched = 0;
DateTime startTime = DateTime.UtcNow;
var batchLatencyTracker = new LatencyTracker();
var e2eLatencyTracker = new LatencyTracker();

// Token cache
var tokenCache = new { Token = "", ExpiresAt = DateTime.UtcNow };
var tokenLock = new object();

async Task<string> GetCachedToken()
{
    lock (tokenLock)
    {
        if (tokenCache.ExpiresAt > DateTime.UtcNow.AddSeconds(30))
            return tokenCache.Token;
    }
    
    var token = await sqlTokenProvider.GetTokenAsync(
        new Azure.Core.TokenRequestContext(new[] { "https://database.windows.net/.default" }));
    
    lock (tokenLock)
    {
        tokenCache = new { Token = token.Token, ExpiresAt = token.ExpiresOn.UtcDateTime };
    }
    
    return token.Token;
}

// Per-partition batch queues for buffering events
var partitionBatches = new ConcurrentDictionary<int, List<(string Source, string Level, string Message, string PartitionKey, DateTime Timestamp, DateTime ReceiveTime, long PublishedAtTicks)>>();
var batchSemaphore = new SemaphoreSlim(1, 1);

// Batch configuration (can be tuned for latency vs throughput tradeoff)
int BATCH_SIZE = int.TryParse(Environment.GetEnvironmentVariable("BATCH_SIZE"), out var bs) ? bs : 200;
int BATCH_TIMEOUT_MS = int.TryParse(Environment.GetEnvironmentVariable("BATCH_TIMEOUT_MS"), out var bt) ? bt : 250;

logger.LogInformation("Batch Configuration: Size={BatchSize} events, Timeout={TimeoutMs}ms", BATCH_SIZE, BATCH_TIMEOUT_MS);

async Task BulkInsertBatch(List<(string, string, string, string, DateTime, DateTime, long)> batch)
{
    if (batch.Count == 0) return;
    if (skipDatabase) return; // Skip if --no-db mode

    int batchCount = 0;
    try
    {
        // Create a copy to safely iterate
        var batchCopy = new List<(string, string, string, string, DateTime, DateTime, long)>(batch);
        batchCount = batchCopy.Count;

        // Record E2E latency for all events BEFORE writing to SQL (captures queue time)
        // Only record for recent events (< 10 minutes old) to exclude ancient backlog
        var nowTicks = DateTime.UtcNow.Ticks;
        long maxAgeMs = 10 * 60 * 1000; // 10 minutes in milliseconds
        
        foreach (var (_, _, _, _, _, _, publishedAtTicks) in batchCopy)
        {
            long e2eLatencyMs = (nowTicks - publishedAtTicks) / 10000;
            
            // Only track recent events to avoid backlog skewing metrics
            if (e2eLatencyMs < maxAgeMs)
            {
                e2eLatencyTracker.Record(e2eLatencyMs);
            }
        }

        var dt = new DataTable();
        dt.Columns.Add("Source", typeof(string));
        dt.Columns.Add("Level", typeof(string));
        dt.Columns.Add("Message", typeof(string));
        dt.Columns.Add("PartitionKey", typeof(string));
        dt.Columns.Add("Timestamp", typeof(DateTime));

        foreach (var (source, level, message, partitionKey, timestamp, receiveTime, publishedAtTicks) in batchCopy)
        {
            dt.Rows.Add(source ?? "", level ?? "INFO", message ?? "", partitionKey, timestamp);
        }

        using var conn = new SqlConnection(sqlConnectionString);
        conn.AccessToken = await GetCachedToken();
        await conn.OpenAsync();

        using (var bulkCopy = new SqlBulkCopy(conn))
        {
            bulkCopy.DestinationTableName = "[dbo].[EventLogs]";
            bulkCopy.ColumnMappings.Add("Source", "Source");
            bulkCopy.ColumnMappings.Add("Level", "Level");
            bulkCopy.ColumnMappings.Add("Message", "Message");
            bulkCopy.ColumnMappings.Add("PartitionKey", "PartitionKey");
            bulkCopy.ColumnMappings.Add("Timestamp", "Timestamp");
            bulkCopy.BatchSize = 500;
            await bulkCopy.WriteToServerAsync(dt);
        }

        eventsBatched += batchCount;
        logger.LogInformation("✓ Bulk inserted {Count} events", batchCount);
        batch.Clear();
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error bulk inserting batch of {Count} events", batchCount);
        eventsFailedSQL += batchCount;
    }
}

// Background task: Periodically flush batches
_ = Task.Run(async () =>
{
    while (true)
    {
        await Task.Delay(BATCH_TIMEOUT_MS);
        
        await batchSemaphore.WaitAsync();
        try
        {
            foreach (var partitionId in partitionBatches.Keys.ToList())
            {
                if (partitionBatches.TryGetValue(partitionId, out var batch) && batch.Count > 0)
                {
                    await BulkInsertBatch(batch);
                }
            }
        }
        finally
        {
            batchSemaphore.Release();
        }
    }
});

// Register event handlers
processorClient.ProcessEventAsync += async args =>
{
    var eventReceiveTime = DateTime.UtcNow;
    try
    {
        var eventBody = args.Data.EventBody.ToString();
        
        // Parse JSON event
        using var doc = JsonDocument.Parse(eventBody);
        var root = doc.RootElement;
        
        var source = root.TryGetProperty("source", out var sourceProp) ? sourceProp.GetString() : "EventHub";
        var level = root.TryGetProperty("level", out var levelProp) ? levelProp.GetString() : "INFO";
        var message = root.TryGetProperty("message", out var msgProp) ? msgProp.GetString() : "";
        var partitionKey = root.TryGetProperty("partitionKey", out var pkProp) ? pkProp.GetString() : null;
        var publishedAtTicks = root.TryGetProperty("publishedAt", out var pubProp) && pubProp.TryGetInt64(out var ticks) ? ticks : DateTime.UtcNow.Ticks;

        // Add to partition batch
        var partitionId = int.Parse(args.Partition.PartitionId);
        var batch = partitionBatches.GetOrAdd(partitionId, _ => new List<(string, string, string, string, DateTime, DateTime, long)>());

        bool shouldFlush = false;
        lock (batch)
        {
            batch.Add((source, level, message, partitionKey, DateTime.UtcNow, eventReceiveTime, publishedAtTicks));
            shouldFlush = batch.Count >= BATCH_SIZE;
        }

        if (shouldFlush)
        {
            await batchSemaphore.WaitAsync();
            try
            {
                var batchStartTime = DateTime.UtcNow;
                await BulkInsertBatch(batch);
                var batchLatency = (long)(DateTime.UtcNow - batchStartTime).TotalMilliseconds;
                batchLatencyTracker.Record(batchLatency);
            }
            finally
            {
                batchSemaphore.Release();
            }
        }

        eventsProcessed++;
        if (eventsProcessed % 5000 == 0)
        {
            var elapsed = DateTime.UtcNow - startTime;
            var rate = eventsProcessed / elapsed.TotalSeconds;
            var (batchP50, batchP95, batchP99, batchMin, batchMax, batchAvg) = batchLatencyTracker.GetStats();
            var (e2eP50, e2eP95, e2eP99, e2eMin, e2eMax, e2eAvg) = e2eLatencyTracker.GetStats();
            logger.LogInformation("📊 Processed {Count} evt ({Rate:F0} evt/s) | Batch Latency: P50={BatchP50}ms P95={BatchP95}ms P99={BatchP99}ms Avg={BatchAvg:F1}ms | E2E Latency: P50={E2EP50}ms P95={E2EP95}ms P99={E2EP99}ms Avg={E2EAvg:F1}ms", 
                eventsProcessed, rate, batchP50, batchP95, batchP99, batchAvg, e2eP50, e2eP95, e2eP99, e2eAvg);
        }

        // Update checkpoint
        await args.UpdateCheckpointAsync();
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error processing event");
        eventsFailedSQL++;
    }
};

processorClient.ProcessErrorAsync += args =>
{
    logger.LogError(args.Exception, "Error in event processor: {Message}", args.Exception?.Message ?? "Unknown");
    return Task.CompletedTask;
};

try
{
    logger.LogInformation("Starting Event Hub consumer processing...");
    await processorClient.StartProcessingAsync();
    
    logger.LogInformation("✓ Consumer started successfully");
    logger.LogInformation("Batch Mode: {BatchSize} events per batch or {TimeoutMs}ms timeout", BATCH_SIZE, BATCH_TIMEOUT_MS);
    logger.LogInformation("Consumer running. Press Ctrl+C to stop.");
    
    // Keep running until Ctrl+C
    var cts = new CancellationTokenSource();
    Console.CancelKeyPress += (s, e) =>
    {
        e.Cancel = true;
        cts.Cancel();
    };

    await Task.Delay(-1, cts.Token);
}
catch (OperationCanceledException)
{
    logger.LogInformation("Stopping consumer...");
}
catch (Exception ex)
{
    logger.LogError(ex, "Fatal error in consumer: {Message}", ex.Message);
    throw;
}
finally
{
    // Flush remaining batches
    await batchSemaphore.WaitAsync();
    try
    {
        foreach (var partitionId in partitionBatches.Keys.ToList())
        {
            if (partitionBatches.TryGetValue(partitionId, out var batch) && batch.Count > 0)
            {
                await BulkInsertBatch(batch);
            }
        }
    }
    finally
    {
        batchSemaphore.Release();
    }

    await processorClient.StopProcessingAsync();
    var elapsed = DateTime.UtcNow - startTime;
    var (batchP50Final, batchP95Final, batchP99Final, batchMinFinal, batchMaxFinal, batchAvgFinal) = batchLatencyTracker.GetStats();
    var (e2eP50Final, e2eP95Final, e2eP99Final, e2eMinFinal, e2eMaxFinal, e2eAvgFinal) = e2eLatencyTracker.GetStats();
    logger.LogInformation("Consumer stopped. Processed {Count} events in {Duration:F1}s ({Rate:F0} evt/sec, {Failed} failed)  |  Batch Latency: P50={BatchP50}ms P95={BatchP95}ms P99={BatchP99}ms Min={BatchMin}ms Max={BatchMax}ms Avg={BatchAvg:F1}ms  |  E2E Latency: P50={E2EP50}ms P95={E2EP95}ms P99={E2EP99}ms Min={E2EMin}ms Max={E2EMax}ms Avg={E2EAvg:F1}ms",
        eventsProcessed, elapsed.TotalSeconds, eventsProcessed / elapsed.TotalSeconds, eventsFailedSQL, batchP50Final, batchP95Final, batchP99Final, batchMinFinal, batchMaxFinal, batchAvgFinal, e2eP50Final, e2eP95Final, e2eP99Final, e2eMinFinal, e2eMaxFinal, e2eAvgFinal);
}

static string ExtractStorageAccountName(string connectionString)
{
    var parts = connectionString.Split(';');
    foreach (var part in parts)
    {
        if (part.StartsWith("AccountName="))
            return part.Substring("AccountName=".Length);
    }
    throw new ArgumentException("Could not extract storage account name");
}

// Latency tracking for throughput measurement
file class LatencyTracker
{
    private readonly List<long> _latencies = new();
    private readonly object _lock = new();

    public void Record(long latencyMs)
    {
        lock (_lock)
        {
            _latencies.Add(latencyMs);
        }
    }

    public (long P50, long P95, long P99, long Min, long Max, double Avg) GetStats()
    {
        lock (_lock)
        {
            if (_latencies.Count == 0)
                return (0, 0, 0, 0, 0, 0);

            var sorted = _latencies.OrderBy(x => x).ToList();
            var p50 = sorted[(int)(sorted.Count * 0.50)];
            var p95 = sorted[(int)(sorted.Count * 0.95)];
            var p99 = sorted[(int)(sorted.Count * 0.99)];
            var min = sorted[0];
            var max = sorted[sorted.Count - 1];
            var avg = sorted.Average();

            return (p50, p95, p99, min, max, avg);
        }
    }

    public int Count
    {
        get
        {
            lock (_lock)
            {
                return _latencies.Count;
            }
        }
    }
}
