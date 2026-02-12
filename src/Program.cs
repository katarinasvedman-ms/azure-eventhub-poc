using Azure.Identity;
using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;
using MetricSysPoC.Configuration;
using MetricSysPoC.Services;
using MetricSysPoC.Middleware;

// Check for load test mode
var loadTestArg = args.FirstOrDefault(a => a.StartsWith("--load-test="));
if (loadTestArg is not null)
{
    var parts = loadTestArg.Split('=');
    if (int.TryParse(parts.LastOrDefault(), out var seconds) && seconds > 0)
    {
        var apiUrl = args.FirstOrDefault(a => a.StartsWith("--api-url="))?.Split('=', 2).LastOrDefault()
                     ?? "http://localhost:5000";
        var logsPerReq = 1;
        var logsArg = args.FirstOrDefault(a => a.StartsWith("--logs-per-request="))?.Split('=').LastOrDefault();
        if (int.TryParse(logsArg, out var lpr) && lpr > 0) logsPerReq = lpr;

        await RunLoadTest(seconds, apiUrl, logsPerReq);
        return;
    }
}

var builder = WebApplication.CreateBuilder(args);

// ========================
// Configuration Setup
// ========================
var eventHubOptions = new EventHubOptions();
builder.Configuration.GetSection("EventHub").Bind(eventHubOptions);

builder.Services.Configure<EventHubOptions>(builder.Configuration.GetSection("EventHub"));

// ========================
// Azure Client Setup
// ========================
var credential = new DefaultAzureCredential();

// Event Hub Producer Client (singleton for connection pooling)
EventHubProducerClient producerClient;
if (eventHubOptions.UseKeyAuthentication && !string.IsNullOrEmpty(eventHubOptions.ConnectionString))
{
    producerClient = new EventHubProducerClient(eventHubOptions.ConnectionString, eventHubOptions.HubName);
}
else
{
    producerClient = new EventHubProducerClient(
        eventHubOptions.FullyQualifiedNamespace,
        eventHubOptions.HubName,
        credential);
}

builder.Services.AddSingleton(producerClient);

// ========================
// Application Services
// ========================
builder.Services.AddSingleton<IEventHubProducerService, EventHubProducerService>();
builder.Services.AddSingleton<IEventBatchingService, EventBatchingService>();

// ========================
// API Setup
// ========================
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "LogsysNG Event Hub PoC",
        Version = "v1",
        Description = "Proof of Concept for high-throughput Event Hub integration"
    });
});

builder.Services.AddHealthChecks();

// ========================
// Observability
// ========================
builder.Services
    .AddApplicationInsightsTelemetry()
    .AddLogging(logging =>
    {
        logging.AddApplicationInsights();
        logging.AddConsole();
    });

// ========================
// Build & Configure App
// ========================
var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseRouting();
app.MapControllers();
app.MapHealthChecks("/health");

// ========================
// Wire up batching → Event Hub producer
// ========================
var batchingService = app.Services.GetRequiredService<IEventBatchingService>();
var producerService = app.Services.GetRequiredService<IEventHubProducerService>();

if (batchingService is EventBatchingService typedBatching)
{
    typedBatching.BatchReady += async (sender, args) =>
    {
        try
        {
            await producerService.PublishEventBatchAsync(args.Events, args.CorrelationId);
        }
        catch (Exception ex)
        {
            app.Logger.LogError(ex, "Failed to publish batch of {Count} events", args.BatchSize);
        }
    };
}

// Graceful shutdown
app.Lifetime.ApplicationStopping.Register(() =>
{
    app.Logger.LogInformation("Application shutting down — flushing remaining events");
    producerClient.CloseAsync().GetAwaiter().GetResult();
});

await app.RunAsync();

// Load test function — sends HTTP requests to the API, simulating real client traffic
static async Task RunLoadTest(int durationSeconds, string apiUrl, int logsPerRequest)
{
    var loggerFactory = LoggerFactory.Create(l => l.AddConsole());
    var logger = loggerFactory.CreateLogger("LoadTest");

    const int MAX_CONCURRENT_REQUESTS = 64;
    var handler = new SocketsHttpHandler
    {
        PooledConnectionLifetime = TimeSpan.FromMinutes(5),
        MaxConnectionsPerServer = MAX_CONCURRENT_REQUESTS
    };
    var httpClient = new HttpClient(handler) { BaseAddress = new Uri(apiUrl) };

    var latencyTracker = new LatencyTracker();
    var startTime = DateTime.UtcNow;
    var testRunId = $"loadtest-{startTime:yyyyMMddTHHmmssZ}";
    var endTime = startTime.AddSeconds(durationSeconds);
    var eventCount = 0;
    var requestCount = 0;
    var errorCount = 0;
    var lastReportTime = DateTime.UtcNow;
    var lastReportCount = 0;
    var semaphore = new SemaphoreSlim(MAX_CONCURRENT_REQUESTS);
    var pendingTasks = new List<Task>();
    var lockObj = new object();
    var random = new Random();

    Console.WriteLine($"╔════════════════════════════════════════════════════════════╗");
    Console.WriteLine($"║             HTTP LOAD TEST                                ║");
    Console.WriteLine($"╚════════════════════════════════════════════════════════════╝");
    Console.WriteLine();
    Console.WriteLine($"  Target API:           {apiUrl}");
    Console.WriteLine($"  Duration:             {durationSeconds}s");
    Console.WriteLine($"  Logs per request:     {logsPerRequest}");
    Console.WriteLine($"  Max concurrency:      {MAX_CONCURRENT_REQUESTS}");
    Console.WriteLine($"  Test Run ID:          {testRunId}");
    Console.WriteLine();

    // Choose endpoint based on logs per request
    var useBatchEndpoint = logsPerRequest > 1;

    while (DateTime.UtcNow < endTime)
    {
        await semaphore.WaitAsync();

        Interlocked.Add(ref eventCount, logsPerRequest);
        Interlocked.Increment(ref requestCount);

        var task = Task.Run(async () =>
        {
            try
            {
                var reqStart = DateTime.UtcNow;
                HttpResponseMessage response;

                if (useBatchEndpoint)
                {
                    var events = Enumerable.Range(0, logsPerRequest).Select(i => new
                    {
                        message = $"Load test event {testRunId}",
                        source = testRunId,
                        level = "INFO",
                        partitionKey = $"key-{random.Next(100)}"
                    });
                    var payload = new { events };
                    response = await httpClient.PostAsJsonAsync("/api/logs/ingest-batch", payload);
                }
                else
                {
                    var payload = new
                    {
                        message = $"Load test event {testRunId}",
                        source = testRunId,
                        level = "INFO",
                        partitionKey = $"key-{random.Next(100)}"
                    };
                    response = await httpClient.PostAsJsonAsync("/api/logs/ingest", payload);
                }

                var latencyMs = (long)(DateTime.UtcNow - reqStart).TotalMilliseconds;
                latencyTracker.Record(latencyMs);

                if (!response.IsSuccessStatusCode)
                {
                    Interlocked.Increment(ref errorCount);
                    if (errorCount <= 5) // Only log first few errors
                        logger.LogWarning("HTTP {StatusCode} from API", response.StatusCode);
                }
            }
            catch (Exception ex)
            {
                Interlocked.Increment(ref errorCount);
                if (errorCount <= 5)
                    logger.LogWarning(ex, "Request failed");
            }
            finally
            {
                semaphore.Release();
            }
        });

        lock (lockObj)
        {
            pendingTasks.Add(task);
            pendingTasks.RemoveAll(t => t.IsCompleted);
        }

        var now = DateTime.UtcNow;
        var elapsed = (int)(now - startTime).TotalSeconds;

        if ((now - lastReportTime).TotalSeconds >= 1)
        {
            var intervalSecs = (now - lastReportTime).TotalSeconds;
            var intervalEvents = eventCount - lastReportCount;
            var intervalRate = intervalEvents / intervalSecs;
            var totalSecs = (now - startTime).TotalSeconds;
            var avgRate = eventCount / totalSecs;
            Console.WriteLine($"[{elapsed:D2}/{durationSeconds}s] {eventCount:N0} events ({requestCount:N0} req) | Last 1s: {intervalRate:F0} evt/s | Avg: {avgRate:F0} evt/s | Errors: {errorCount}");
            lastReportTime = now;
            lastReportCount = eventCount;
        }
    }

    // Drain in-flight
    var sendWindowElapsed = DateTime.UtcNow - startTime;
    List<Task> remaining;
    lock (lockObj) { remaining = new List<Task>(pendingTasks); }
    await Task.WhenAll(remaining);

    var totalElapsed = DateTime.UtcNow - startTime;
    var evtRate = eventCount / sendWindowElapsed.TotalSeconds;
    var reqRate = requestCount / sendWindowElapsed.TotalSeconds;
    var (p50, p95, p99, min, max, avg) = latencyTracker.GetStats();

    Console.WriteLine();
    Console.WriteLine("╔════════════════════════════════════════════════════════════╗");
    Console.WriteLine("║             LOAD TEST RESULTS                             ║");
    Console.WriteLine("╚════════════════════════════════════════════════════════════╝");
    Console.WriteLine();
    Console.WriteLine($"Configuration:");
    Console.WriteLine($"  Target:               {apiUrl}");
    Console.WriteLine($"  Duration:             {durationSeconds}s");
    Console.WriteLine($"  Logs/request:         {logsPerRequest}");
    Console.WriteLine($"  Concurrency:          {MAX_CONCURRENT_REQUESTS}");
    Console.WriteLine($"  Test Run ID:          {testRunId}");
    Console.WriteLine();
    Console.WriteLine($"Throughput:");
    Console.WriteLine($"  Total Events:         {eventCount:N0}");
    Console.WriteLine($"  Total Requests:       {requestCount:N0}");
    Console.WriteLine($"  Events/sec:           {evtRate:F0}");
    Console.WriteLine($"  Requests/sec:         {reqRate:F0}");
    Console.WriteLine($"  Errors:               {errorCount}");
    Console.WriteLine();
    Console.WriteLine($"HTTP Latency (per request):");
    Console.WriteLine($"  P50:                  {p50}ms");
    Console.WriteLine($"  P95:                  {p95}ms");
    Console.WriteLine($"  P99:                  {p99}ms");
    Console.WriteLine($"  Average:              {avg:F1}ms");
    Console.WriteLine($"  Min/Max:              {min}ms - {max}ms");
    Console.WriteLine();
    Console.WriteLine("✓ Test Complete");
    Console.WriteLine();
    Console.WriteLine($"Run this SQL query after the consumer has drained all events:");
    Console.WriteLine();
    Console.WriteLine($"  SELECT COUNT(*) AS TotalEvents,");
    Console.WriteLine($"    AVG(DATEDIFF_BIG(MILLISECOND, [Timestamp], CreatedAt)) AS AvgE2E_ms,");
    Console.WriteLine($"    DATEDIFF_BIG(SECOND, MIN([Timestamp]), MAX(CreatedAt)) AS WallClockSeconds");
    Console.WriteLine($"  FROM EventLogs WHERE Source = '{testRunId}';");
    Console.WriteLine();
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

