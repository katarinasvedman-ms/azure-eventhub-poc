# Load Test Guide - 20,000 Events/Sec

## Overview

This guide explains how to run a comprehensive load test that sends **20,000 events per second for one minute** and generates a detailed markdown report with performance metrics, analysis, and recommendations.

---

## What Gets Tested

| Aspect | Details |
|--------|---------|
| **Target Throughput** | 20,000 events/sec |
| **Event Size** | ~1 KB average |
| **Test Duration** | 60 seconds (configurable) |
| **Total Events** | 1,200,000 (60 × 20,000) |
| **Batch Size** | 100 events per batch |
| **Metrics Collected** | Throughput, latency, success rate, failure details |
| **Output Format** | Markdown report with tables and analysis |

---

## How to Run

### Option 1: Via Web API (Recommended)

Start the application and make a request to the load test endpoint:

```bash
# Start the application
dotnet run --configuration Release

# In another terminal, run the load test
curl "http://localhost:5000/api/loadtest/run?duration=60&reportPath=load-test-report.md"
```

**Using PowerShell:**
```powershell
# Start the application
dotnet run --configuration Release

# In another terminal
Invoke-WebRequest `
  -Uri "http://localhost:5000/api/loadtest/run?duration=60&reportPath=load-test-report.md" `
  -Method Get
```

**Using the provided script:**
```powershell
# Make script executable (first time only)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Run the load test
./run-load-test.ps1 -Duration 60 -ReportPath "load-test-report.md"
```

### Option 2: Via API Script (Bash)

```bash
#!/bin/bash
DURATION=60
REPORT_PATH="load-test-report.md"
ENDPOINT="http://localhost:5000"

curl -X GET "$ENDPOINT/api/loadtest/run?duration=$DURATION&reportPath=$REPORT_PATH"
```

### Option 3: Query the API Info Endpoint First

Get information about the load test capabilities:

```bash
curl "http://localhost:5000/api/loadtest/info"
```

Response:
```json
{
  "name": "Event Hub Load Test Service",
  "version": "1.0.0",
  "capabilities": {
    "targetThroughput": "20,000 events/sec",
    "batchSize": 100,
    "eventSize": "~1 KB average",
    "metricsCollected": [
      "Throughput (evt/sec)",
      "Success rate (%)",
      "Latency (min/p50/p95/p99/max)",
      "Failed events",
      "Total events sent"
    ],
    "reportFormat": "Markdown with tables and analysis"
  }
}
```

---

## Test Execution Flow

```
1. Load Test Started
   ├─ Configuration: 20k evt/sec for 60s
   ├─ Generate Events: 100-event batches
   └─ Send to Event Hub

2. During Test
   ├─ Measure latency for each batch
   ├─ Track successes and failures
   ├─ Log progress every 1000 events
   └─ Monitor for exceptions

3. Test Completed
   ├─ Collect all metrics
   ├─ Calculate percentiles (P50, P95, P99)
   ├─ Generate comprehensive report
   └─ Write to markdown file
```

---

## Report Contents

The generated report includes:

### 1. Executive Summary
- Actual throughput vs target (20,000 evt/sec)
- Total events sent and success rate
- Pass/fail status with emoji indicators

### 2. Test Configuration
- Target throughput
- Batch size and event size
- Total duration
- Total events attempted

### 3. Performance Results
- **Throughput**: Actual evt/sec vs target
- **Latency Statistics**: Min, P50, P95, P99, max (milliseconds)
- **Success Rate**: Percentage of successful events

### 4. Detailed Metrics
- Test start/end times
- Number of batches sent
- Total data transferred
- Average events per batch

### 5. Latency Distribution
Table showing:
- Latency ranges (0-10ms, 10-50ms, etc.)
- Count of events in each range
- Percentage distribution

### 6. Analysis & Recommendations

**If PASSED (✅)**:
- Event Hub configuration is suitable for production
- Specific metrics and pass criteria shown
- Recommendations for monitoring and scaling

**If ACCEPTABLE (⚠️)**:
- Identifies specific areas for improvement
- Suggests optimization steps

**If FAILED (❌)**:
- Lists specific issues found
- Detailed troubleshooting recommendations

### 7. Test Environment
- Report generation timestamp
- Machine name and OS
- .NET version
- Number of processors

---

## Example Report Output

```markdown
# Load Test Report - Azure Event Hub

**Test Date**: 2025-12-16 14:32:15 UTC
**Test Duration**: 60.15 seconds
**Test Status**: ✅ COMPLETED

## Executive Summary

| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| **Actual Throughput** | 20,012 evt/sec | 20,000 evt/sec | ✅ PASS |
| **Events Sent** | 1,200,720 | 1,200,000 | ✅ |
| **Success Rate** | 99.99% | ≥99% | ✅ PASS |
| **Failed Events** | 0 | 0 | ✅ PASS |

## Performance Results

### Throughput
- **Actual Throughput**: 20,012 events/sec
- **Target Throughput**: 20,000 events/sec
- **Throughput vs Target**: 100.1%
- **Status**: ✅ EXCELLENT

### Latency Statistics (milliseconds)
| Percentile | Latency (ms) | Status |
|-----------|--------------|--------|
| Min | 2.15 | ✅ |
| P50 (Median) | 47.32 | ✅ GOOD |
| P95 | 89.45 | ✅ GOOD |
| P99 | 124.67 | ✅ GOOD |
| Average | 52.18 | ✅ GOOD |
| Max | 856.32 | ✅ ACCEPTABLE |

...
```

---

## Interpreting Results

### ✅ PASSED Criteria
All of the following must be true:
- Actual throughput ≥ 19,000 evt/sec (95% of target)
- Success rate ≥ 99.9%
- P99 latency < 1,000 ms
- Zero or near-zero failed events

**Meaning**: Event Hub is production-ready for 20k evt/sec workload

### ⚠️ ACCEPTABLE Criteria
At least 2 of the following:
- Throughput ≥ 15,000 evt/sec (75% of target)
- Success rate ≥ 95%
- Some elevated latencies but not extreme

**Meaning**: Event Hub works but not optimal; optimization recommended

### ❌ FAILED Criteria
Any of the following:
- Throughput < 15,000 evt/sec
- Success rate < 95%
- P99 latency > 5,000 ms
- Significant number of failed events

**Meaning**: Event Hub configuration needs adjustment

---

## Performance Baselines

### Expected Results (Standard Tier, 24 Partitions)

| Metric | Expected | Range |
|--------|----------|-------|
| Throughput | 20,000+ evt/sec | 18,000-22,000 |
| P50 Latency | 30-100 ms | 20-200 |
| P95 Latency | 50-200 ms | 30-500 |
| P99 Latency | 100-500 ms | 50-1,000 |
| Success Rate | >99.9% | >99% |
| Max Latency | <2,000 ms | <5,000 |

---

## Troubleshooting

### Test Fails to Start

**Problem**: `Connection refused` or `Unable to connect to Event Hub`

**Solutions**:
1. Verify Event Hub is deployed: `az resource list --resource-group "rg-logsysng-dev"`
2. Check connection strings in `appsettings.json`
3. Verify firewall allows outbound HTTPS (port 443)
4. Run the application first: `dotnet run`

### Low Throughput

**Problem**: Actual throughput much lower than 20k evt/sec

**Solutions**:
1. Check Event Hub partitions: Should be ≥ 24
2. Review batch size settings
3. Monitor Event Hub throttling in Azure Portal
4. Consider upgrading to Premium tier

### High Latency

**Problem**: P99 latency exceeds 1,000 ms

**Solutions**:
1. Check Event Hub availability in Portal
2. Verify network connectivity
3. Review consumer group checkpoint lag
4. Check if Event Hub is throttling (429 errors)

### Failed Events

**Problem**: Success rate below 99%

**Solutions**:
1. Check exception logs in the report
2. Verify storage account for checkpoints
3. Review producer/consumer configuration
4. Increase retry attempts in code

---

## Customizing the Test

### Change Duration
```bash
# Run 120-second test
curl "http://localhost:5000/api/loadtest/run?duration=120"

# Or via PowerShell
./run-load-test.ps1 -Duration 120
```

### Change Report Path
```bash
# Save to specific location
curl "http://localhost:5000/api/loadtest/run?duration=60&reportPath=/tmp/my-report.md"
```

### Modify Source Code

Edit `LoadTestService.cs`:

```csharp
// Change batch size
int batchSize = 200;  // Default: 100

// Change event size
var events = new List<LogEvent>(batchSize);
for (int i = 0; i < batchSize; i++)
{
    events.Add(new LogEvent
    {
        // ... customize fields
        Message = $"Custom message {i}"
    });
}
```

---

## Performance Tuning

### To Improve Throughput

1. **Increase Partitions**
   - Edit `parameters.dev.json`: `"partitionCount": 32`
   - Redeploy Event Hub

2. **Increase Batch Size**
   - Edit `LoadTestService.cs`: `int batchSize = 200`

3. **Upgrade to Premium Tier**
   - Edit `deploy/main.bicep`: Change SKU to Premium
   - Redeploy

### To Reduce Latency

1. **Increase Consumer Concurrency**
   - Adjust in application configuration

2. **Optimize Event Size**
   - Compress or remove unnecessary fields

3. **Use Premium Tier**
   - Better performance and SLA

---

## Sample Commands

### Quick 60-Second Test
```bash
curl "http://localhost:5000/api/loadtest/run?duration=60"
```

### Extended 300-Second Test
```bash
curl "http://localhost:5000/api/loadtest/run?duration=300&reportPath=extended-test.md"
```

### Check Event Hub Configuration
```bash
az eventhubs eventhub show \
  --namespace-name "eventhub-dev-xxx" \
  --resource-group "rg-logsysng-dev" \
  --name "logs"
```

### View Metrics in Azure Portal
```
https://portal.azure.com
→ Resource Groups
→ rg-logsysng-dev
→ Event Hub Namespace
→ Metrics
```

---

## Next Steps

1. **Deploy Event Hub** (if not already done)
   ```
   cd deploy
   ./deploy.ps1 -ResourceGroupName "rg-logsysng-dev"
   ```

2. **Run Application**
   ```
   dotnet run --configuration Release
   ```

3. **Execute Load Test**
   ```
   ./run-load-test.ps1 -Duration 60
   ```

4. **Review Report**
   - Open `load-test-report.md` in your editor
   - Check if test passed
   - Review recommendations

5. **Optimize (if needed)**
   - Follow troubleshooting steps
   - Adjust configuration
   - Re-run test to validate

---

## Reports Location

Reports are saved in the current working directory:
- `load-test-report.md` (default)
- Custom path via `-ReportPath` parameter

To find the report:
```powershell
Get-Item load-test-report.md | Select-Object FullName
```

---

## Support

For issues or questions:

1. **Review the report** for specific error messages
2. **Check logs** in the application output
3. **Verify Event Hub** is deployed and accessible
4. **See troubleshooting section** above

---

**Ready to test?** Run:
```bash
./run-load-test.ps1 -Duration 60
```

**That's it!** The test will run and generate a comprehensive report. 🚀
