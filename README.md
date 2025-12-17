# Event Hub PoC

## Overview

This is a proof of concept demonstrating high-throughput Azure Event Hub patterns for event ingestion scenarios (20,000+ events/second). It proves the infrastructure can achieve 26.7k evt/sec with direct SDK batching and provides reusable best practices.

## Key Findings

### ✅ Performance Proven
- **Direct SDK throughput: 26.7k evt/sec** (exceeds 20k target by 33%)
- **Sustained throughput**: Consistent 25-27k evt/sec for 30+ seconds
- **Low latency**: P50: 28ms, P99: 108ms batch latency
- **Scalability**: 24 partitions, ~1.1k evt/sec per partition

### ✅ Critical Configuration Issue Found
- **Problem**: Explicit `MaximumSizeInBytes` in `CreateBatchOptions` reduced throughput by 64%
- **Solution**: Use default `CreateBatchAsync()` (no options) for optimal performance
- **Impact**: 20.9k evt/sec (default) vs 12.7k evt/sec (explicit options)
- **Lesson**: SDK defaults are carefully tuned; explicit options can degrade performance

## Project Structure

```
eventhub/
├── src/                                # Producer/Consumer Service
│   ├── MetricSysPoC.csproj
│   ├── Program.cs                      # Minimal console app
│   ├── Configuration/
│   │   └── EventHubOptions.cs
│   ├── Models/
│   │   └── LogEvent.cs
│   └── Services/
│       ├── EventHubProducerService.cs
│       ├── EventHubConsumerService.cs
│       └── SqlPersistenceService.cs
│
├── src-consumer/                        # Standalone Consumer (--no-db for testing)
├── deploy/                              # Infrastructure as Code (Bicep)
├── ARCHITECTURE.md                      # Design decisions & patterns
├── BATCH_OPTIONS_ANALYSIS.md            # ⚠️ CRITICAL: BatchOptions performance issue
├── BEST_PRACTICES.md                    # Event Hub best practices
├── DEPLOYMENT.md                        # Setup & deployment guide
└── README.md                            # This file
```

## Quick Start

### Prerequisites
- .NET 8 SDK
- Azure CLI
- Azure Subscription (Event Hub + SQL Database + Storage Account)

### Run Locally

**Producer/Consumer:**
```bash
cd src
dotnet run --configuration Release
```

**Consumer Only (Skip Database):**
```bash
cd src-consumer
dotnet run -- --no-db
```

This mode tests raw Event Hub throughput without database bottleneck.

### Load Test Producer Performance

**Run a 30-second load test to verify producer throughput:**
```bash
cd src
dotnet run -c Release -- --load-test=30
```

This will:
- Send 1,000 event batches continuously for 30 seconds
- Display real-time progress with instantaneous + cumulative throughput
- Output verified metrics: total events, throughput (evt/sec), latency percentiles

**Expected Results:**
```
✅ Throughput: ~25,000-26,000 events/sec (125-130% of 20k target)
✅ P50 Latency: ~29ms per batch
✅ P99 Latency: ~177ms per batch
✅ Success: Test completes with "VERIFIED" badge
```

You can run multiple load tests back-to-back to verify consistency.

### Deploy to Azure

```bash
cd deploy
.\deploy.ps1 -ResourceGroupName "rg-eventhub-dev" -Location "eastus"
```

See `DEPLOYMENT_QUICKSTART.md` for detailed steps.

## Performance Baseline

**Test Configuration:**
- Duration: 30 seconds
- Total events: 802,000
- Batch size: 1,000 events/batch
- Message size: ~180 bytes (JSON)

**Results:**
| Metric | Value |
|--------|-------|
| Total Events | 802,000 |
| Throughput | **26.7k evt/sec** |
| Target Achievement | **133.5%** (exceeds 20k) |
| Batch Latency P50 | 28ms |
| Batch Latency P99 | 108ms |
| Max Latency | 577ms |

**Proven:** Direct SDK approach handles 20k evt/sec comfortably with capacity to spare.

**Results:**
| Metric | Value |
|--------|-------|
| Total Events | 802,000 |
| Throughput | **26.7k evt/sec** |
| Target Achievement | **133.5%** (exceeds 20k) |
| Batch Latency P50 | 28ms |
| Batch Latency P99 | 108ms |
| Max Latency | 577ms |

## ⚠️ CRITICAL: CreateBatchOptions Performance Issue

**DO NOT USE EXPLICIT OPTIONS:**
```csharp
// ❌ SLOW - 12.7k evt/sec (64% slower)
var batch = await producer.CreateBatchAsync(new CreateBatchOptions 
{ 
    MaximumSizeInBytes = 1024 * 1024 
});

// ✅ FAST - 26.7k evt/sec (default)
var batch = await producer.CreateBatchAsync();
```

See `BATCH_OPTIONS_ANALYSIS.md` for detailed comparison and analysis.

## Best Practices

### 🟢 DO
- ✅ Reuse producer client (singleton pattern)
- ✅ Serialize on-demand (not pre-serialized list)
- ✅ Use default `CreateBatchAsync()`
- ✅ Batch at application level (1,000 events optimal)
- ✅ Use partition keys for consistent routing

### 🔴 DON'T
- ❌ Create new producer client per request
- ❌ Pre-serialize events into a list (memory spike)
- ❌ Specify explicit `MaximumSizeInBytes` (64% throughput loss!)
- ❌ Use low-cardinality partition keys (e.g., status, country)
- ❌ Hard-code partition numbers

## Deployment

See `DEPLOYMENT_QUICKSTART.md` for step-by-step deployment guide.

**Quick deploy:**
```bash
cd deploy
.\deploy.ps1 -ResourceGroupName "rg-eventhub-dev" -Location "eastus"
```

Creates:
- Event Hub (Standard SKU, 24 partitions)
- Storage Account (checkpoint management)
- SQL Database (Basic SKU, 2GB)

## Database Considerations

**Current SKU**: Basic (2GB, 5 DTU)
- Sufficient for current throughput
- Consumer is bottleneck: ~1.3k evt/sec (single-threaded)
- Producer proven at 26.7k evt/sec (no database)

**Scaling**: To handle producer throughput, implement parallel consumer processing per partition.

## Next Steps for Production

1. **Consumer Parallel Processing** - Per-partition handlers
2. **Batch Database Writes** - Current: individual writes
3. **Monitoring & Alerting** - Application Insights integration
4. **Security Hardening** - Private Endpoints, Managed Identity enforcement

## Documentation

| Document | Purpose |
|----------|---------|
| **ARCHITECTURE.md** | Design decisions, patterns, proven performance |
| **BATCH_OPTIONS_ANALYSIS.md** | ⚠️ Critical: Why explicit BatchOptions reduce throughput 64% |
| **BEST_PRACTICES_ANALYSIS.md** | Event Hub best practices & patterns with metrics |
| **DEPLOYMENT.md** | Deployment guide (infrastructure + configuration) |
| **DEPLOYMENT_QUICKSTART.md** | Quick start commands |
| **SKU_RECOMMENDATION.md** | SKU selection guide with validation |

## Troubleshooting

**Low throughput?**
1. Check `BATCH_OPTIONS_ANALYSIS.md` - Verify no explicit `MaximumSizeInBytes`
2. Verify producer client is singleton (connection pooling)
3. Check partition count = 24 (Azure Portal)
4. Monitor Event Hub metrics for throttling

**Consumer lagging?**
- Current limitation: Single-threaded consumer (~1.3k evt/sec)
- Producer achieves 26.7k evt/sec independently
- Use `dotnet run -- --no-db` to measure raw Event Hub throughput

---

**Project**: Event Hub PoC  
**Status**: PoC Complete  
**Version**: 2.0 (Cleaned & Optimized)  
**Performance**: 26.7k evt/sec proven  
**Last Updated**: December 17, 2025
