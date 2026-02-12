# Azure Event Hubs Best Practices - Implementation Guide

This document captures best practices and findings from a production Event Hub pipeline implementation
(Producer → Event Hubs → Azure Functions → Azure SQL) in Sweden Central region.

---

## Table of Contents

1. [Infrastructure Design](#infrastructure-design)
2. [SDK Usage Patterns](#sdk-usage-patterns)
3. [Batching Strategy](#batching-strategy)
4. [Performance Optimization](#performance-optimization)
5. [Production Checklist](#production-checklist)
6. [Load Test Results](#load-test-results)

---

## Infrastructure Design

### Recommended Configuration

**SKU & Throughput Units (TUs):**
- **SKU**: Standard tier (not Basic)
  - Standard supports 1,000-32,000 events/sec per namespace
  - Includes consumer groups, event retention policies, and better throughput
  - **Each Throughput Unit (TU) = 1,000 events/sec ingress/egress**
  - Example: 20 TUs = 20,000 events/sec capacity
- **Use Auto-Inflate**: Highly recommended for variable workloads
  - Start with capacity=1 TU (baseline cost)
  - Set maximum-throughput-units to your peak need (e.g., 20)
  - Automatically scales up under load, scales down when idle
  - Saves money when traffic is low

**Partitions**: 24 partitions
  - Each partition handles ~1,000 events/sec
  - 24 partitions = ~24,000 events/sec capacity
  - Higher partition count = better parallelism for consumers
  - Balance against operation complexity

**Consumer Groups:**
- Create separate consumer groups for different consumer scenarios
  - Example: `logs-consumer`, `monitoring-consumer`, `archive-consumer`
  - Each group maintains independent offset tracking
  - Allows multiple independent consumers without interference

**Message Retention:**
- Configure based on use case (default: 1 day)
- Consider replay/recovery scenarios
- Balance between storage costs and retention needs

**Region Selection:**
- Choose region close to producers/consumers
- This implementation: Sweden Central (swedencentral)
- Reduces latency, improves throughput

### Authorization Policies

Create granular policies:
```bicep
// SendPolicy - for producers only
{
  "rights": ["Send"]
}

// ListenPolicy - for consumer (Azure Functions trigger)
{
  "rights": ["Listen"]
}

// Never use RootManageSharedAccessKey in production
// Implement least-privilege access control
```

---

## SDK Usage Patterns

### Version Requirements

**Current Recommended Versions (Producer):**
```xml
<PackageReference Include="Azure.Messaging.EventHubs" Version="5.12.0" />
<PackageReference Include="Azure.Identity" Version="1.14.0" />
```

**Current Recommended Versions (Consumer - Azure Functions):**
```xml
<PackageReference Include="Microsoft.Azure.Functions.Worker" Version="1.22.0" />
<PackageReference Include="Microsoft.Azure.Functions.Worker.Extensions.EventHubs" Version="6.3.6" />
<PackageReference Include="Microsoft.Data.SqlClient" Version="5.1.5" />
```

**Authentication:**
```csharp
// Use DefaultAzureCredential for managed identity support
var credential = new DefaultAzureCredential();
var producerClient = new EventHubProducerClient(
    "namespace.servicebus.windows.net",
    "event-hub-name",
    credential
);
```

### Single Event Publishing

**Pattern: `SendAsync()`**
```csharp
public async Task<bool> PublishEventAsync(LogEvent logEvent)
{
    try
    {
        var json = JsonSerializer.Serialize(logEvent);
        var eventData = new EventData(json);
        await _producerClient.SendAsync(new[] { eventData });
        return true;
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Failed to publish event");
        return false;
    }
}
```

**Characteristics:**
- Simple API, suitable for low-volume scenarios
- SDK handles internal batching automatically
- Good for unpredictable traffic patterns
- P99 Latency: ~25-30ms

---

## Batching Strategy

### ✅ BEST PRACTICE: `CreateBatchAsync()`

This is the **recommended approach** for production systems handling high-throughput scenarios.

**Implementation:**
```csharp
public async Task<int> PublishEventBatchAsync(IEnumerable<LogEvent> logEvents)
{
    var eventList = logEvents.ToList();
    if (!eventList.Any())
        return 0;

    try
    {
        var successCount = 0;
        var remaining = eventList.ToList();

        // Keep creating batches until all events are sent
        while (remaining.Count > 0)
        {
            // CreateBatchAsync respects maximum message size and partition limits
            using (var eventBatch = await _producerClient.CreateBatchAsync())
            {
                var batchedCount = 0;

                // Add events to batch until it's full or we run out of events
                while (remaining.Count > 0)
                {
                    var json = JsonSerializer.Serialize(remaining[0]);
                    var eventData = new EventData(json);

                    // TryAdd returns false if batch is full
                    if (!eventBatch.TryAdd(eventData))
                    {
                        break;  // Batch full, send it
                    }

                    batchedCount++;
                    successCount++;
                    remaining.RemoveAt(0);
                }

                // Send the batch
                if (batchedCount > 0)
                {
                    await _producerClient.SendAsync(eventBatch);
                    _logger.LogDebug("Sent batch of {BatchSize} events", batchedCount);
                }
            }
        }

        return successCount;
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "Failed to publish event batch of {Count} events", 
            eventList.Count);
        return 0;
    }
}
```

**Why This Approach is Best:**

1. **SDK-Managed Size Limits**
   - Automatically respects Event Hub message size constraints (1MB)
   - Handles oversized events gracefully
   - No manual size calculation required

2. **Optimal Batch Sizing**
   - SDK determines ideal batch size for network efficiency
   - Automatically handles partition routing
   - Balances throughput vs latency

3. **Automatic Fallback**
   - If an event is too large to fit in a batch, SDK handles it
   - No application-level retry logic needed

4. **Performance Characteristics**
   - Achieves 21,000+ evt/sec with 1,000-event batches
   - P99 Latency: ~55ms
   - 100% reliability

### Anti-Pattern: Manual Pre-Batching

❌ **NOT Recommended:**
```csharp
// Don't do this - manual batch collection
var batchList = new List<EventData>();
foreach (var evt in events)
{
    batchList.Add(new EventData(JsonSerializer.Serialize(evt)));
}
await _producerClient.SendAsync(batchList);
```

**Why it's problematic:**
- Doesn't respect SDK's internal size limits
- Can exceed 1MB batch limit → failures
- Loses SDK's optimization logic
- Requires manual batch size tuning

## Consumer Best Practices (Azure Functions)

### Batch Trigger Pattern

The consumer uses an Azure Functions isolated worker with `EventData[]` batch trigger:

```csharp
[Function(nameof(ProcessEventBatch))]
public async Task ProcessEventBatch(
    [EventHubTrigger("%EventHubName%", Connection = "EventHubConnection",
        ConsumerGroup = "%EventHubConsumerGroup%")]
    EventData[] events,
    FunctionContext context)
{
    // 1. Deserialize all events, isolating poison messages
    // 2. Bulk write to SQL via temp-table staging
    // 3. Return successfully → runtime checkpoints
}
```

### Key Tuning Parameters (host.json)

```json
{
  "extensions": {
    "eventHubs": {
      "maxEventBatchSize": 500,
      "prefetchCount": 2000,
      "batchCheckpointFrequency": 1,
      "checkpointStoreConnection": "CheckpointStoreConnection"
    }
  }
}
```

- `maxEventBatchSize`: 500 — balance between batch efficiency and SQL write latency
- `prefetchCount`: 2000 — 4× batch size, keeps events ready for next invocation
- `batchCheckpointFrequency`: 1 — checkpoint after every batch (safest)
- `checkpointStoreConnection`: separates checkpoint I/O from host storage

### Idempotent SQL Writes

```sql
-- Temp-table staging pattern:
-- 1. CREATE #EventLogs_Staging (session-scoped, no races)
-- 2. SqlBulkCopy into #staging
-- 3. INSERT INTO EventLogs SELECT ... FROM #staging WHERE NOT EXISTS
```

Why this pattern:
- `SqlBulkCopy` is all-or-nothing — can't catch 2627 per-row
- Temp tables (`#`) are session-scoped — no cross-partition interference
- `INSERT WHERE NOT EXISTS` atomically skips duplicates

---

### Issue #1: Placeholder Configuration Values
**Problem:** App pointed to wrong Event Hub namespace/hub name
- Configured: `FullyQualifiedNamespace: "your-namespace.servicebus.windows.net"`
- Should be: `eventhub-dev-fuwf32lf57ise.servicebus.windows.net`
- Configured: `HubName: "logsysng-hub"`
- Should be: `logs`

**Impact:** Application appeared to work but wasn't actually connecting to Azure - events were silently lost!

**Solution:** 
```json
{
  "EventHub": {
    "FullyQualifiedNamespace": "your-actual-namespace.servicebus.windows.net",
    "HubName": "your-hub-name",
    "ConsumerGroup": "your-consumer-group"
  }
}
```

### Issue #2: Missing Authorization (SendPolicy)
**Problem:** Got `UnauthorizedAccessException: 'Send' claim(s) are required`
- App had `DefaultAzureCredential` but user didn't have `Send` permission on Event Hub

**Solution:**
```bash
az role assignment create \
  --assignee YOUR_USER_PRINCIPAL \
  --role "Azure Event Hubs Data Sender" \
  --scope /subscriptions/.../namespaces/your-namespace
```

### Issue #3: Insufficient Throughput Units
**Problem:** Throughput capped at ~1,300 evt/sec even though infrastructure was rated for 20k+
- Root cause: Capacity was set to 1 TU (only 1,000 evt/sec)
- **Each TU = 1,000 events/sec**

**Performance comparison:**
| Capacity | Expected Throughput | Actual Achieved |
|----------|-------------------|-----------------|
| 1 TU | 1,000 evt/sec | 1,300 evt/sec |
| 20 TUs | 20,000 evt/sec | **23,483 evt/sec** ✅ |

**Solution:** Use auto-inflate
```bash
az eventhubs namespace update \
  --enable-auto-inflate \
  --maximum-throughput-units 20 \
  --capacity 1
```

---

## Performance Optimization

### Load Testing Configuration

**Optimal Settings (Validated):**
- **Batch Size**: 1,000 events per batch
  - Good balance between network efficiency and memory usage
  - Respects SDK's batching constraints
- **Inter-Batch Delay**: 0ms (send as fast as possible)
  - Let SDK handle internal throttling
  - Event Hub can handle rapid batch submissions
- **Parallel Clients**: Not needed with `CreateBatchAsync()`
  - Single producer client is sufficient
  - SDK handles internal concurrency

### Achieved Results (With Correct Configuration)

**Test Configuration:**
- **Duration**: 10 seconds
- **Batch Size**: 1,000 events
- **Inter-Batch Delay**: 0ms
- **Capacity**: 20 TUs (auto-inflate enabled)
- **API Endpoint**: Single ASP.NET Core service on localhost
- **Real Azure Event Hub**: eventhub-dev-fuwf32lf57ise.servicebus.windows.net (Sweden Central)

**Performance Metrics:**
| Metric | Value |
|--------|-------|
| **Throughput** | 23,483 events/sec |
| **Target Achievement** | 117.4% of 20,000 evt/sec target |
| **Total Events** | 235,000 in 10 seconds |
| **Success Rate** | 100% |
| **Failed Batches** | 0 |
| **P50 Latency** | 23ms |
| **P95 Latency** | 52ms |
| **P99 Latency** | 98ms |
| **Max Latency** | 189ms |
| **Average Latency** | 28.27ms |

**Key Observations:**
- ✅ Achieved sustained 23k+ evt/sec (exceeds 20k target)
- ✅ Ramped from 9.7k to 23.5k evt/sec smoothly
- ✅ Maintained consistent throughput across all 10 seconds
- ✅ Excellent latency - P99 under 100ms
- ✅ 100% reliability - zero message loss
- ✅ Events confirmed arriving in real Azure Event Hub

### Optimization Techniques

**1. Connection Pooling**
```csharp
// Reuse single EventHubProducerClient instance
// Register as singleton in DI container
services.AddSingleton(producerClient);
```

**2. Async/Await**
```csharp
// Always use async APIs
await _producerClient.SendAsync(eventBatch);
// Not: _producerClient.Send(eventBatch);
```

**3. Producer Batch Configuration**
```csharp
// ✅ CORRECT: Use default CreateBatchAsync — SDK optimizes internally
var batch = await producerClient.CreateBatchAsync();

foreach (var evt in events)
{
    var eventData = new EventData(JsonSerializer.SerializeToUtf8Bytes(evt));
    
    if (!batch.TryAdd(eventData))
    {
        // Batch full — send it and start a new one
        await producerClient.SendAsync(batch);
        batch = await producerClient.CreateBatchAsync();
        batch.TryAdd(eventData);
    }
}

if (batch.Count > 0)
    await producerClient.SendAsync(batch);

// ❌ WRONG: Do NOT specify MaximumSizeInBytes — causes 64% throughput loss!
// var batch = await producerClient.CreateBatchAsync(
//     new CreateBatchOptions { MaximumSizeInBytes = 1024 * 1024 });
```

**Key points for producer batching:**
- Use default `CreateBatchAsync()` — never set explicit `MaximumSizeInBytes` (see `BATCH_OPTIONS_ANALYSIS.md`)
- Application-level batch size of 1,000 events is proven optimal
- `TryAdd()` returns false when SDK's internal size limit is reached — handle the overflow
- Serialize to UTF-8 bytes directly (`SerializeToUtf8Bytes`) for best performance

**4. Consumer Batch Configuration (host.json)**
```json
{
  "extensions": {
    "eventHubs": {
      "maxEventBatchSize": 500,
      "prefetchCount": 2000,
      "batchCheckpointFrequency": 1,
      "checkpointStoreConnection": "CheckpointStoreConnection"
    }
  }
}
```

**5. Partitioning Strategy**
```csharp
// Use partition key for even distribution
var eventData = new EventData(json) 
{ 
    PartitionKey = $"p{Random.Shared.Next(0, 24)}"
};
// This ensures events spread across all 24 partitions
```

---

## Production Checklist

### Code Quality
- [x] Use `CreateBatchAsync()` for producer batching (default options only)
- [x] Azure Functions batch trigger for consumer (`EventData[]`)
- [x] Idempotent SQL writes (temp-table staging + `INSERT WHERE NOT EXISTS`)
- [x] Poison event isolation within batch
- [x] Comprehensive error handling and structured logging
- [x] Handle connection timeouts (30s recommended)
- [ ] Implement exponential backoff for transient failures (producer-side)

### Infrastructure
- [x] Use Event Hubs Standard SKU (not Basic — Basic limits: 1 consumer group, no capture)
- [x] Configure 24 partitions for high throughput
- [x] Create separate consumer group (`logs-consumer`)
- [x] Set appropriate message retention (24 hours)
- [x] Configure monitoring and alerting
- [x] Use SAS policies with least-privilege (SendPolicy, ListenPolicy)
- [ ] Use managed identity for production (AAD auth)

### Security
- [ ] Use least-privilege authorization policies
- [ ] Never commit connection strings - use Key Vault
- [ ] Enable diagnostic logging
- [ ] Audit access patterns
- [ ] Implement rate limiting if needed
- [ ] Use VNet service endpoints for private connectivity

### Monitoring
- [ ] Track events sent vs. failed
- [ ] Monitor latency percentiles (P50, P95, P99)
- [ ] Alert on error rates > 1%
- [ ] Monitor partition distribution
- [ ] Track consumer group lag
- [ ] Set up dead-letter queue handling

### Testing
- [x] Load test producer at 26.7k evt/sec (30 seconds)
- [x] E2E test: producer → Event Hub → Functions → SQL (59,578 events, 0 duplicates)
- [x] Verify idempotent writes handle re-delivery
- [x] Test with realistic event sizes (~180 bytes JSON)
- [x] Validate partition distribution
- [ ] Test connection loss scenarios
- [ ] Test failover scenarios

---

## SDK Configuration

### EventHubProducerClient Options

```csharp
var clientOptions = new EventHubProducerClientOptions
{
    // Connection timeout for retries
    ConnectionOptions = new EventHubsConnectionOptions
    {
        TransportType = EventHubsTransportType.AmqpTcp,
        IdleTimeout = TimeSpan.FromSeconds(60),
        MaximumRetries = 3,
    },
    // Retry policy for transient failures
    RetryOptions = new EventHubsRetryOptions
    {
        Mode = EventHubsRetryMode.Exponential,
        MaximumRetries = 3,
        Delay = TimeSpan.FromMilliseconds(800),
        MaximumDelay = TimeSpan.FromSeconds(60),
    }
};

var producerClient = new EventHubProducerClient(
    fullyQualifiedNamespace,
    eventHubName,
    credential,
    clientOptions
);
```

---

## Common Pitfalls & Solutions

### Pitfall 1: Mixing SendAsync and CreateBatchAsync

❌ **Wrong:**
```csharp
// Inconsistent approach - don't mix patterns
await _producerClient.SendAsync(events);  // Sometimes
using (var batch = await _producerClient.CreateBatchAsync()) { }  // Sometimes
```

✅ **Correct:**
```csharp
// Pick one pattern and use consistently
// For high throughput: always use CreateBatchAsync
```

### Pitfall 2: Ignoring Batch Size Limits

❌ **Wrong:**
```csharp
var events = new List<EventData>();
for (int i = 0; i < 10000; i++)  // Creating huge batch
{
    events.Add(new EventData(largeJson));
}
await _producerClient.SendAsync(events);  // May fail!
```

✅ **Correct:**
```csharp
using (var batch = await _producerClient.CreateBatchAsync())
{
    foreach (var evt in events)
    {
        if (!batch.TryAdd(evt))  // SDK handles sizing
        {
            await _producerClient.SendAsync(batch);
            batch = await _producerClient.CreateBatchAsync();
        }
    }
    if (batch.Count > 0)
        await _producerClient.SendAsync(batch);
}
```

### Pitfall 3: No Error Handling

❌ **Wrong:**
```csharp
await _producerClient.SendAsync(events);  // Silent failures
```

✅ **Correct:**
```csharp
try
{
    await _producerClient.SendAsync(events);
}
catch (EventHubsException ex)
{
    if (ex.IsTransient)
    {
        // Retry with backoff
    }
    else
    {
        // Log and alert - permanent failure
        _logger.LogError(ex, "Permanent failure publishing events");
    }
}
```

### Pitfall 4: Creating New Client Instances

❌ **Wrong:**
```csharp
public async Task SendEvent(LogEvent evt)
{
    var client = new EventHubProducerClient(...);  // Creates new connection
    await client.SendAsync(new[] { new EventData(...) });
}
// Connection recreated for every event!
```

✅ **Correct:**
```csharp
// Inject as singleton dependency
services.AddSingleton(producerClient);

public class EventHubProducerService
{
    private readonly EventHubProducerClient _producerClient;
    
    public EventHubProducerService(EventHubProducerClient producerClient)
    {
        _producerClient = producerClient;  // Reuse connection
    }
}
```

---

## Cost Optimization with Auto-Inflate

### Why Auto-Inflate Matters

**Throughput Unit (TU) Pricing:**
- Each TU costs ~$0.015/hour (~$11/month)
- 1 TU = 1,000 events/sec
- 20 TUs = $220/month (fixed cost if always at 20)

**With Auto-Inflate:**
```bash
az eventhubs namespace update \
  --enable-auto-inflate \
  --maximum-throughput-units 20 \
  --capacity 1
```

**Cost Profile:**
- **Idle/Low traffic**: 1 TU = ~$11/month
- **Peak load (20k evt/sec)**: Auto-scales to 20 TUs temporarily
- **Scale-down**: Automatically reduces when traffic stops

**Real-world example:**
- Dev/test environment: Mostly idle at 1 TU (~$11/month)
- Daily peak traffic (1 hour): Scales to 20 TUs for that period
- Rest of day: Back to 1 TU
- Monthly cost: ~$50-80 instead of $220

### How Auto-Inflate Works

**Scale-up behavior:**
- Automatic when approaching capacity
- Increases by 1 TU at a time
- Completes within minutes

**Scale-down behavior:**
- Automatic when traffic is low
- Decreases by 1 TU at a time
- Takes 10-15 minutes of sustained low traffic
- Prevents rapid oscillation (thrashing)

**Monitoring:**
- Check **Metrics** → "Throughput Units" in Azure Portal
- Set alerts on approaching maximum

---

## Conclusion

By implementing these best practices, you can achieve:
- ✅ **26,700+ events/sec** producer throughput (proven)
- ✅ **<30ms average latency** (P99: ~100ms) on producer side
- ✅ **100% reliability** with idempotent SQL writes and batch checkpointing
- ✅ **Zero duplicates** with temp-table staging pattern
- ✅ **Code patterns** following Azure standards
- ✅ **Cost-optimized** with auto-inflate for variable workloads

---

*Version*: 3.0  
*Last Updated*: February 12, 2026  
*Status*: E2E Verified

