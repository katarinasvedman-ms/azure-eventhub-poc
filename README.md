# Event Hub Pipeline — REST API → Event Hubs → Azure Functions → Azure SQL

<br>

<div align="center">

```
         ┌──────────────────────────────────────────────────────┐
         │               D E S I G N   P R I N C I P L E S     │
         └──────────────────────────────────────────────────────┘
```

<h2 style="border:none; margin:0; padding:0;"><b>The API</b> accepts any request size — the SDK batches internally.</h2>
<h2 style="border:none; margin:0; padding:0;"><b>Event Hubs</b> delivers at least once.</h2>
<h2 style="border:none; margin:0; padding:0;"><b>Azure Functions</b> scale by partitions.</h2>
<h2 style="border:none; margin:0; padding:0;"><b>SQL</b> enforces exactly-once results.</h2>

<br>

*Accept duplicates at the edge. Eliminate them at the store.*

---

</div>

<br>

## Overview

Production-grade event ingestion pipeline handling **2,000–20,000 HTTP requests/sec** (1–10 log events each) with guaranteed idempotency. Clients send logs via REST API; the API buffers internally and publishes to Azure Event Hubs using SDK-managed batching. An Azure Functions consumer reads from Event Hubs in batches and writes to Azure SQL using idempotent bulk inserts.

```
Clients (HTTP)  →  REST API (src/)  →  Azure Event Hubs  →  Azure Functions (src-function/)  →  Azure SQL
  1-10 logs/req     P1v3, autoscale    24 partitions, 8 TUs   EP1 Premium, batch 2000          Premium P1
  2k-20k req/sec    1-5 instances      auto-inflate to 20     min 1, max 10 instances           125 DTU
```

## Architecture at a Glance

| Layer | Area | Configuration | Why it matters |
|-------|------|---------------|----------------|
| **REST API** | Hosting | Azure App Service **P1v3** (2 vCPU, 8 GB) | Handles HTTP ingestion with autoscale 1–5 instances |
| | Endpoints | `POST /api/logs/ingest` + `/ingest-batch` | Single and batch ingestion, returns 202 Accepted |
| | Internal batching | `EventBatchingService` (500 events or 100ms flush) | Decouples HTTP request size from Event Hub batch size |
| | Auth to Event Hub | **Managed Identity** (`DefaultAzureCredential`) | No connection strings — zero-secret deployment |
| **Event Hub** | Partitions | **24 partitions** | Scale unit = partitions. ~1,000 events/sec per partition |
| | Throughput Units | **8 TUs** with auto-inflate to **20** | 8 MB/s ingress, scales to 20 MB/s automatically |
| | Delivery model | At‑least‑once | Replays are expected on failure or rebalance |
| **Azure Functions** | Hosting | **EP1 Premium** (min 1, max burst 10) | No cold start, stable under sustained load |
| | Trigger type | `EventData[]` (batch) | One invocation processes many events |
| | Batch size | `maxEventBatchSize: 2000`, `prefetchCount: 2000` | Maximizes throughput per invocation |
| | Checkpointing | Once per batch (`batchCheckpointFrequency: 1`) | ≤2,000 event replay window on crash |
| **Database (SQL)** | SKU | **Premium P1** (125 DTU, SSD I/O, 500 GB) | 4,283 evt/sec sustained consumer writes |
| | Correctness | `UNIQUE INDEX` on `EventId_Business` | Database is the final authority |
| | Insert pattern | Temp-table staging + `INSERT WHERE NOT EXISTS` | Bulk-copy friendly, race-safe |
| **End‑to‑end** | Processing guarantee | At‑least‑once ingestion, effectively-once in DB | Unique index rejects duplicates |

## Performance Benchmarks

### API Ingestion (Azure Load Testing — 2 engines, 300 threads)
| Metric | Value |
|--------|-------|
| Aggregate req/sec | **2,790** (during ramp) |
| Batch endpoint | 2,320 req/sec × ~5.5 avg events ≈ **12,760 evt/sec** |
| Single endpoint | 463 req/sec |
| P90 response time | **114 ms** |
| Errors | **0** |

### API Ingestion (local single-machine baseline)
| Pattern | Req/sec | Events/sec | P50 |
|---------|---------|------------|-----|
| 5 logs/request | 2,959 | 14,796 | 15ms |
| 1 log/request | 11,236 | 11,236 | 4ms |

### Producer (direct SDK throughput)
| Metric | Value |
|--------|-------|
| Throughput | **50,683 evt/sec** (parallelized, 8 concurrent senders) |
| Batch latency P50 | 28ms |

### Consumer Pipeline (E2E)
| Metric | Value |
|--------|-------|
| Consumer throughput | **4,283 evt/sec** sustained |
| Batch size | 2,000 events/invocation |
| Duplicates | **0** across all test runs (1.3M+ events) |
| Hosting | EP1 Premium + SQL Premium P1 |

### Key Findings
- **Zero errors** under distributed load test (Azure Load Testing)
- **Zero duplicates** across 1.3M+ events — idempotency layer works
- **Parallel SQL writes tested and reverted** — no benefit (DTU is the ceiling, not write concurrency)
- **Critical**: Do NOT use explicit `MaximumSizeInBytes` in `CreateBatchOptions` (see `BATCH_OPTIONS_ANALYSIS.md`)

## Project Structure

```
eventhub/
├── src/                                 # REST API + Load Test Tool
│   ├── Program.cs                       # ASP.NET Core host + --load-test mode
│   ├── Controllers/
│   │   └── LogsController.cs            # POST /api/logs/ingest + /ingest-batch
│   ├── Configuration/
│   │   └── EventHubOptions.cs           # Event Hub connection settings
│   ├── Models/
│   │   └── LogEvent.cs                  # Event data model
│   ├── Middleware/
│   │   └── AuthenticationMiddleware.cs
│   └── Services/
│       ├── EventHubProducerService.cs   # Producer with SDK batching
│       └── EventBatchingService.cs      # In-memory buffer (500 events / 100ms)
│
├── src-function/                        # Azure Functions Consumer (isolated worker)
│   ├── Program.cs                       # Function host + DI setup
│   ├── host.json                        # Event Hub trigger tuning
│   ├── local.settings.json              # Local connection strings
│   ├── Functions/
│   │   └── EventHubBatchFunction.cs     # Batch EventHubTrigger (2000/batch)
│   └── Services/
│       ├── SqlEventWriter.cs            # Idempotent bulk SQL writer
│       └── EventRecord.cs              # DTO + BatchWriteResult
│
├── infra/                               # Infrastructure as Code (Bicep)
│   ├── main.bicep                       # Orchestrator (all modules)
│   ├── function-app.bicep               # Function App module
│   ├── api-app.bicep                    # REST API Web App module
│   ├── sql.bicep                        # SQL Server + Database module
│   ├── topic.bicep                      # Event Hub namespace + hub
│   ├── parameters.dev.json              # Dev environment parameters
│   ├── deploy.ps1 / deploy.sh           # Deployment scripts
│   ├── sql-schema.sql                   # Base SQL schema
│   └── migrations/
│       └── 001_add_idempotency.sql      # Unique index for idempotency
│
├── load-test/                           # Azure Load Testing
│   ├── api-load-test.jmx               # JMeter test plan (batch + single)
│   ├── load-test.yaml                   # ALT config (engines, thresholds)
│   └── post-test-analysis.sql          # SQL queries for E2E pipeline analysis
│
├── ARCHITECTURE.md                      # Design decisions & patterns
├── BATCH_OPTIONS_ANALYSIS.md            # ⚠️ CRITICAL: BatchOptions performance issue
├── BEST_PRACTICES.md                    # Event Hub best practices & patterns
├── DEPLOYMENT.md                        # Setup & deployment guide
├── DEPLOYMENT_QUICKSTART.md             # Quick start commands
├── SKU_RECOMMENDATION.md                # SKU selection guide
└── README.md                            # This file
```

## Quick Start

### Prerequisites
- .NET 8 SDK
- Azure CLI
- Azure Functions Core Tools v4 (v4.6.0+)
- Azure Subscription (Event Hub + SQL Database + Storage Account)

### Deploy Infrastructure

```powershell
cd infra
.\deploy.ps1 -ResourceGroupName "rg-logsysng-dev" -Location "swedencentral"
```

See `DEPLOYMENT_QUICKSTART.md` for detailed steps.

### Run the Consumer (Azure Functions)

```powershell
cd src-function
dotnet publish -c Release -o publish
cd publish
$token = (az account get-access-token --resource "https://database.windows.net/" --query accessToken -o tsv)
$env:SqlAccessToken = $token
func start
```

### Run the API Locally

```powershell
cd src
dotnet run
# Health check: GET http://localhost:5000/health
# Single event: POST http://localhost:5000/api/logs/ingest
# Batch: POST http://localhost:5000/api/logs/ingest-batch
```

### HTTP Load Test (against running API)

```powershell
cd src

# 5-second burst, 5 logs per request, against local API
dotnet run -c Release -- --load-test=5 --api-url=http://localhost:5000 --logs-per-request=5

# Against Azure-deployed API
dotnet run -c Release -- --load-test=30 --api-url=https://api-logsysng-eyeqfiorm5tv2.azurewebsites.net --logs-per-request=5
```

### Azure Load Testing

Upload `load-test/api-load-test.jmx` to your Azure Load Testing resource for distributed load generation. See `load-test/load-test.yaml` for configuration and `load-test/post-test-analysis.sql` for SQL-side E2E analysis after the test.
```

### Send Events (HTTP Load Test)

```powershell
cd src

# Against local API (5 logs/request, 30 seconds)
dotnet run -c Release -- --load-test=30 --api-url=http://localhost:5000 --logs-per-request=5

# Against Azure API
dotnet run -c Release -- --load-test=30 --api-url=https://api-logsysng-eyeqfiorm5tv2.azurewebsites.net --logs-per-request=1
```

Expected output:
```
[10/30s] Sent 32,500 requests | 1s: 3,100 req/s (15,500 evt/s) | Avg: 2,800 req/s | P50: 15ms
...
```

## Performance Baseline

### API Throughput (Azure Load Testing)

| Metric | Value |
|--------|-------|
| Engine instances | 2 |
| Virtual users | 300 (250 batch + 50 single) |
| Aggregate req/sec | **2,790** |
| Batch req/sec | 2,320 (≈12,760 evt/sec) |
| P90 response time | **114 ms** |
| Errors | **0** |

### Consumer Pipeline (E2E Verified)

| Metric | Value |
|--------|-------|
| Consumer throughput | **4,283 evt/sec** sustained |
| Consumer type | Azure Functions EP1 Premium |
| Batch size | 2,000 events/invocation |
| SQL tier | Premium P1 (125 DTU) |
| Total events verified | **1.3M+** across all test runs |
| Duplicates | **0** |

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/logs/ingest` | Single log event (returns 202) |
| `POST` | `/api/logs/ingest-batch` | 1–N log events (returns 202) |
| `GET` | `/api/logs/queue-stats` | Current buffer size |
| `GET` | `/health` | Health check |

### Request Body — Single Ingest
```json
{
  "message": "User logged in",
  "source": "AuthService",
  "level": "Information",
  "partitionKey": "user-12345"
}
```

### Request Body — Batch Ingest
```json
{
  "events": [
    { "message": "Event 1", "source": "Svc", "level": "Information" },
    { "message": "Event 2", "source": "Svc", "level": "Warning" }
  ]
}
```

## Consumer Architecture

The consumer is an **Azure Functions isolated worker** (EP1 Premium) with Event Hub batch trigger:

1. Functions runtime delivers up to **2,000** events per invocation
2. Deserialize each event, isolating poison messages
3. `SqlBulkCopy` valid events into `#EventLogs_Staging` (session-scoped temp table)
4. Deduplicate within the staging batch (`WITH Dupes AS (...) DELETE WHERE _rn > 1`)
5. `INSERT INTO EventLogs SELECT ... FROM #staging WHERE NOT EXISTS` — atomic idempotent merge
6. Functions runtime checkpoints AFTER successful return

**Key Design Decisions:**
- **Temp table staging**: Each `SqlConnection` gets its own `#EventLogs_Staging` — no cross-partition races
- **Intra-batch dedup**: Duplicate events within the same batch are removed before SQL insert
- **Poison event isolation**: A single bad event doesn't kill the batch — it's logged and skipped
- **Separated checkpoint store**: `checkpointStoreConnection` in host.json avoids I/O contention with host internals

## CRITICAL: CreateBatchOptions Performance Issue

**DO NOT USE EXPLICIT OPTIONS (producer-side):**
```csharp
// SLOW - 64% throughput loss
var batch = await producer.CreateBatchAsync(new CreateBatchOptions 
{ 
    MaximumSizeInBytes = 1024 * 1024 
});

// FAST - 26.7k evt/sec (default)
var batch = await producer.CreateBatchAsync();
```

See `BATCH_OPTIONS_ANALYSIS.md` for detailed comparison and analysis.

## Best Practices

### 🟢 DO
- ✅ Reuse producer client (singleton pattern)
- ✅ Use default `CreateBatchAsync()` (no explicit options)
- ✅ Process events in batches with Azure Functions batch trigger (`EventData[]`)
- ✅ Use temp-table staging for idempotent bulk writes
- ✅ Checkpoint after successful batch processing only
- ✅ Isolate poison events within a batch
- ✅ Separate checkpoint store from function host storage

### 🔴 DON'T
- ❌ Process events one at a time
- ❌ Checkpoint after every single event (catastrophic for throughput)
- ❌ Use a shared permanent staging table (cross-partition race conditions)
- ❌ Specify explicit `MaximumSizeInBytes` (64% throughput loss!)
- ❌ Let one poison event fail the entire batch
- ❌ Use low-cardinality partition keys (e.g., status, country)

## Infrastructure

| Resource | Configuration | SKU |
|----------|---------------|-----|
| Web App (API) | `api-logsysng-eyeqfiorm5tv2` | **P1v3** (2 vCPU, 8 GB), autoscale 1–5 |
| Event Hub | `eventhub-dev-eyeqfiorm5tv2` / `logs`, 24 partitions | Standard, **8 TUs** (auto-inflate → 20) |
| Function App | `func-logsysng-premium-eyeqfiorm5tv2` | **EP1 Premium** (min 1, max burst 10) |
| Azure SQL | `sqlserver-logsysng-eyeqfiorm5tv2` / `eventhub-logs-db` | **Premium P1** (125 DTU, SSD) |
| Storage | `sablobeyeqfiorm5tv2` (checkpoints) | Standard LRS |
| Auth | Managed Identity everywhere | No connection strings to EH |
| Region | Sweden Central | |

## Documentation

| Document | Purpose |
|----------|---------|
| **ARCHITECTURE.md** | Design decisions, patterns, proven performance |
| **BATCH_OPTIONS_ANALYSIS.md** | Critical: Why explicit BatchOptions reduce throughput 64% |
| **BEST_PRACTICES.md** | Event Hub best practices & patterns with metrics |
| **DEPLOYMENT.md** | Deployment guide (infrastructure + configuration) |
| **DEPLOYMENT_QUICKSTART.md** | Quick start commands |
| **SKU_RECOMMENDATION.md** | SKU selection guide with validation |

## Troubleshooting

**Low producer throughput?**
1. Check `BATCH_OPTIONS_ANALYSIS.md` — no explicit `MaximumSizeInBytes`
2. Verify producer client is singleton (connection pooling)
3. Check partition count = 24 (Azure Portal)
4. Monitor Event Hub metrics for throttling

**Function not processing events?**
1. Verify `func start` shows "Found: Host.Functions.ProcessEventBatch"
2. Check Event Hub connection string has `ListenPolicy` (Listen rights)
3. Verify `initialOffsetOptions.enqueuedTimeUtc` is before your events' enqueue time
4. Check checkpoint blobs in `azure-webjobs-eventhub` container
5. Use Functions Core Tools v4.6.0+ (`func --version`)

**SQL auth failures?**
1. For AAD-only SQL: pass pre-acquired token via `$env:SqlAccessToken`
2. Ensure `az login --tenant <tenant-id>` matches the SQL server's tenant
3. Verify your identity is set as SQL AAD admin

**Stale checkpoints after failed runs?**
- Delete the `azure-webjobs-eventhub` blob container to reset all checkpoints
- Or adjust `initialOffsetOptions.enqueuedTimeUtc` in host.json

---

**Project**: Event Hub Pipeline  
**Status**: E2E Verified — Azure Load Testing  
**Version**: 4.0  
**Performance**: API 2,790 req/sec (114ms P90) | Producer 50.7k evt/sec | Consumer 4,283 evt/sec | 0 duplicates  
**Last Updated**: February 12, 2026
