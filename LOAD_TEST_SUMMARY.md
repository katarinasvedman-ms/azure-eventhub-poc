# Load Testing Implementation - Summary

## ✅ What's Been Added

### New Services
- **LoadTestService** (`src/Services/LoadTestService.cs`)
  - Sends 20,000 events/sec for configurable duration
  - Collects comprehensive metrics (throughput, latency, success rate)
  - Generates detailed markdown report with analysis

### New Controller
- **LoadTestController** (`src/Controllers/LoadTestController.cs`)
  - `GET /api/loadtest/run` - Execute load test
  - `GET /api/loadtest/info` - Get capabilities information

### New Scripts
- **run-load-test.ps1** - PowerShell utility for running tests
- **LOAD_TEST_GUIDE.md** - Comprehensive usage guide

### Updated Files
- **Program.cs** - Registered LoadTestService in DI container

---

## 🎯 Key Features

### Metrics Collected
✅ Throughput (events/sec)  
✅ Latency (min, P50, P95, P99, max)  
✅ Success rate (%)  
✅ Failed events count  
✅ Total events sent  
✅ Batch performance  
✅ Time-based statistics  

### Report Contents
✅ Executive summary with pass/fail status  
✅ Performance results with detailed breakdowns  
✅ Latency distribution histogram  
✅ Analysis and recommendations  
✅ Test environment information  
✅ Formatted as professional markdown  

### Analysis Engine
✅ Automatic pass/fail determination  
✅ Contextual recommendations  
✅ Baseline comparisons  
✅ Scaling path guidance  

---

## 🚀 Quick Start

### Step 1: Start the Application
```powershell
dotnet run --configuration Release
```

### Step 2: Run Load Test
**Option A: Via Script (Recommended)**
```powershell
./run-load-test.ps1 -Duration 60
```

**Option B: Via curl**
```bash
curl "http://localhost:5000/api/loadtest/run?duration=60"
```

**Option C: Via PowerShell**
```powershell
Invoke-WebRequest -Uri "http://localhost:5000/api/loadtest/run?duration=60" -Method Get
```

### Step 3: Review Report
```powershell
Get-Content load-test-report.md
```

---

## 📊 Report Example

The generated report includes:

### Summary Section
```
| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| **Actual Throughput** | 20,012 evt/sec | 20,000 evt/sec | ✅ PASS |
| **Events Sent** | 1,200,720 | 1,200,000 | ✅ |
| **Success Rate** | 99.99% | ≥99% | ✅ PASS |
| **Failed Events** | 0 | 0 | ✅ PASS |
```

### Latency Analysis
```
| Percentile | Latency (ms) | Status |
|-----------|--------------|--------|
| P50 | 47.32 | ✅ GOOD |
| P95 | 89.45 | ✅ GOOD |
| P99 | 124.67 | ✅ GOOD |
| Max | 856.32 | ✅ ACCEPTABLE |
```

### Distribution Histogram
```
| Latency Range (ms) | Count | Percentage |
|-------------------|-------|-----------|
| 0 - 10 | 145 | 12.08% |
| 10 - 50 | 542 | 45.17% |
| 50 - 100 | 387 | 32.28% |
| 100 - 200 | 96 | 8.00% |
| 200 - 500 | 22 | 1.83% |
| 500 - 1000 | 8 | 0.67% |
| >= 1000 | 0 | 0.00% |
```

### Analysis & Recommendations
```
### ✅ Test Result: PASSED

Summary: Event Hub is performing excellently for 20,000 events/sec workload.

Key Findings:
- ✅ Achieved 20,012 evt/sec (meets or exceeds 20k target)
- ✅ Success rate of 99.99% (excellent reliability)
- ✅ Median latency of 47.32ms (very responsive)
- ✅ P99 latency of 124.67ms (good tail behavior)

Recommendations:
- ✅ Event Hub configuration is suitable for production
- ✅ Consider monitoring real-world patterns for 1+ week
- ✅ Maintain current partition count (24) for sustained 20k evt/sec
- ✅ Plan upgrade to Premium tier if exceeds 35k evt/sec
```

---

## 📈 Test Scenarios

### Basic Test (60 seconds)
```powershell
./run-load-test.ps1 -Duration 60
```
- **Total Events**: 1.2 million
- **Time**: ~2 minutes (including setup)
- **Report Size**: ~15 KB

### Extended Test (300 seconds)
```powershell
./run-load-test.ps1 -Duration 300 -ReportPath extended-report.md
```
- **Total Events**: 6 million
- **Time**: ~6 minutes (including setup)
- **Report Size**: ~20 KB

### Quick Stress Test (5 minutes)
```powershell
./run-load-test.ps1 -Duration 300
```
- **Total Events**: 6 million
- **Use Case**: Extended stability testing

---

## 🔍 Interpreting Results

### ✅ PASSED
All conditions met:
- Throughput ≥ 19,000 evt/sec (95% of 20k)
- Success rate ≥ 99.9%
- P99 latency < 1,000 ms
- Zero or negligible failed events

**Meaning**: Production-ready!

### ⚠️ ACCEPTABLE
Mixed results:
- Throughput 15,000-19,000 evt/sec
- Success rate 95-99.9%
- Some elevated latencies

**Meaning**: Optimization recommended

### ❌ FAILED
One or more issues:
- Throughput < 15,000 evt/sec
- Success rate < 95%
- P99 latency > 5,000 ms
- Many failed events

**Meaning**: Configuration adjustment needed

---

## 🛠️ Troubleshooting

### Test Won't Start
**Check**:
1. Application running? `dotnet run`
2. Endpoint correct? Default: `http://localhost:5000`
3. Event Hub deployed? See `deploy/` folder

### Low Throughput
**Check**:
1. Partitions: Should be 24+
2. Event Hub throttling in Azure Portal
3. Network latency

**Fix**:
- Upgrade to Premium tier
- Increase partition count
- Check network connectivity

### High Latency
**Check**:
1. Event Hub status
2. Checkpoint lag
3. Consumer performance

**Fix**:
- Optimize batch size
- Increase resources
- Consider Premium tier

### Test Timeout
**Fix**:
- Increase duration parameter gradually
- Check system resources (CPU, memory)
- Monitor Event Hub metrics

---

## 📋 API Reference

### Run Load Test
```
GET /api/loadtest/run?duration=60&reportPath=load-test-report.md

Query Parameters:
  duration: Test duration in seconds (1-600, default: 60)
  reportPath: Output file path (default: load-test-report.md)

Response (200):
{
  "success": true,
  "message": "Load test completed successfully",
  "duration": 60,
  "reportPath": "/path/to/load-test-report.md"
}

Response (400):
{
  "error": "Invalid duration",
  "message": "Duration must be between 1 and 600 seconds"
}
```

### Get Load Test Info
```
GET /api/loadtest/info

Response:
{
  "name": "Event Hub Load Test Service",
  "version": "1.0.0",
  "capabilities": {
    "targetThroughput": "20,000 events/sec",
    "batchSize": 100,
    "eventSize": "~1 KB average",
    "metricsCollected": [...],
    "reportFormat": "Markdown with tables and analysis"
  }
}
```

---

## 📝 Example Commands

### Quick Test
```powershell
./run-load-test.ps1
```

### Longer Test
```powershell
./run-load-test.ps1 -Duration 300
```

### Custom Report Path
```powershell
./run-load-test.ps1 -Duration 60 -ReportPath "./reports/test-20k.md"
```

### Via API
```bash
# Get info
curl http://localhost:5000/api/loadtest/info

# Run test
curl "http://localhost:5000/api/loadtest/run?duration=60"
```

---

## 🎯 Use Cases

### Pre-Production Validation
Run 300-second test to ensure:
- Sustained throughput
- Stable latency
- Zero errors over time

### Deployment Verification
Run 60-second test after deployment:
- Confirm connectivity
- Validate configuration
- Check baseline performance

### Performance Baseline
Run tests regularly:
- Track performance over time
- Identify regressions
- Plan scaling

### Capacity Planning
Run with increasing durations:
- 60s (quick check)
- 300s (extended validation)
- 600s (maximum duration)

---

## 📊 Metrics Definition

| Metric | Definition | Good Range |
|--------|-----------|-----------|
| **Throughput** | Events per second | ≥ 19,000 |
| **P50 Latency** | Median response time | < 100 ms |
| **P95 Latency** | 95th percentile | < 500 ms |
| **P99 Latency** | 99th percentile | < 1,000 ms |
| **Success Rate** | % of successful events | ≥ 99.9% |
| **Max Latency** | Highest response time | < 5,000 ms |

---

## 🚀 Next Steps

1. **Deploy Event Hub** (if needed)
   ```
   ./deploy/deploy.ps1 -ResourceGroupName "rg-logsysng-dev"
   ```

2. **Start Application**
   ```
   dotnet run --configuration Release
   ```

3. **Run Load Test**
   ```
   ./run-load-test.ps1 -Duration 60
   ```

4. **Review Results**
   ```
   Get-Content load-test-report.md
   ```

5. **Optimize (if needed)**
   - Follow recommendations in report
   - Adjust configuration
   - Re-test

---

## 📚 Documentation

- **LOAD_TEST_GUIDE.md** - Comprehensive guide (this repository)
- **LoadTestService.cs** - Implementation details
- **LoadTestController.cs** - API endpoints
- **run-load-test.ps1** - Script usage

---

## ✨ Summary

You now have:
✅ Automated load testing for 20k events/sec  
✅ Comprehensive metric collection  
✅ Professional markdown reports  
✅ Automated analysis and recommendations  
✅ Web API and script interfaces  
✅ Production-ready implementation  

**Ready to test?** Run:
```powershell
./run-load-test.ps1 -Duration 60
```

That's it! 🎉
