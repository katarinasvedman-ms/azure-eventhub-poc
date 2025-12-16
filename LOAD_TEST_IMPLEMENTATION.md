# Load Testing - Complete Implementation

## ✅ Deliverables

### Code Files Created

#### Service (`src/Services/LoadTestService.cs`)
- **LoadTestService** class - Main load test orchestrator
- Sends 20,000 events/sec for configurable duration
- Collects latency, throughput, and success metrics
- Generates comprehensive markdown report
- **Lines of Code**: 350+
- **Methods**:
  - `RunLoadTestAsync(duration, reportPath)` - Execute load test
  - `GenerateReportAsync(reportPath)` - Create markdown report
  - `GetPercentile(values, percentile)` - Calculate percentiles

#### Controller (`src/Controllers/LoadTestController.cs`)
- **LoadTestController** - Web API endpoints
- **Lines of Code**: 100+
- **Endpoints**:
  - `GET /api/loadtest/run?duration=60&reportPath=...` - Run test
  - `GET /api/loadtest/info` - Get capabilities

#### Utility Scripts
- **run-load-test.ps1** - PowerShell test runner
  - Error handling
  - Progress display
  - Report preview
  - Troubleshooting guidance

#### Documentation
- **LOAD_TEST_GUIDE.md** - Comprehensive guide (3,000+ words)
- **LOAD_TEST_SUMMARY.md** - Quick reference

### Integration
- **Program.cs** - Registered LoadTestService in DI container

---

## 🎯 What the Load Test Does

### Execution
1. Generates events at 20,000 events/sec
2. Sends in batches of 100 events
3. Measures latency for each batch
4. Tracks successes and failures
5. Runs for specified duration (default: 60 seconds)
6. Collects comprehensive metrics

### Total for 60-Second Test
- **Total Events**: 1,200,000
- **Total Batches**: 12,000
- **Test Execution Time**: ~60-65 seconds
- **Report Generation**: ~2-3 seconds

### Example: 60-Second Run
```
Timeline:
  0:00-1:00   → Load test sends 1.2M events
  1:00-1:05   → Collect final metrics
  1:05-1:10   → Calculate latency percentiles & distribution
  1:10-1:15   → Generate markdown report with analysis
```

---

## 📊 Metrics Collected

| Metric | Collection Method | Used For |
|--------|------------------|----------|
| **Throughput** | Events/Elapsed Time | Performance baseline |
| **Latency (min)** | Min of all batch latencies | Best case |
| **Latency (P50)** | 50th percentile | Typical case |
| **Latency (P95)** | 95th percentile | High percentile |
| **Latency (P99)** | 99th percentile | Tail latency |
| **Latency (max)** | Max of all batch latencies | Worst case |
| **Success Count** | Total successful events | Reliability |
| **Failed Count** | Total failed events | Error rate |
| **Success Rate** | (Success / Total) × 100 | SLA compliance |
| **Latency Distribution** | Histogram binning | Visualization |

---

## 📄 Report Structure

### Sections (in order)
1. **Header** - Title, date, status
2. **Executive Summary** - Key metrics in table form
3. **Test Configuration** - Parameters used
4. **Performance Results** - Throughput and latency details
5. **Success Rate** - Event delivery reliability
6. **Detailed Metrics** - Comprehensive statistics
7. **Latency Distribution** - Histogram table
8. **Analysis & Recommendations** - Pass/fail logic and guidance
9. **Test Environment** - System information
10. **Report Info** - File path and generation note

### Example Executive Summary Table
```markdown
| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| **Actual Throughput** | 20,012 evt/sec | 20,000 evt/sec | ✅ PASS |
| **Events Sent** | 1,200,720 | 1,200,000 | ✅ |
| **Success Rate** | 99.99% | ≥99% | ✅ PASS |
| **Failed Events** | 0 | 0 | ✅ PASS |
```

---

## 🚀 How to Run

### Simplest Method
```powershell
# Terminal 1: Start app
dotnet run --configuration Release

# Terminal 2: Run test
./run-load-test.ps1
```

**Result**: `load-test-report.md` is generated and partially displayed

### With Custom Duration
```powershell
./run-load-test.ps1 -Duration 300  # 5-minute test
```

### Via Web API
```bash
# Terminal 1: Start app
dotnet run --configuration Release

# Terminal 2: Direct API call
curl "http://localhost:5000/api/loadtest/run?duration=60"
```

### Check Capabilities First
```bash
curl "http://localhost:5000/api/loadtest/info"
```

---

## 📋 Pass/Fail Criteria

### ✅ PASSED (Production-Ready)
- Throughput ≥ 19,000 evt/sec (95%+ of 20k target)
- Success Rate ≥ 99.9% (excellent reliability)
- P99 Latency < 1,000 ms (acceptable tail)
- Zero or negligible failed events

### ⚠️ ACCEPTABLE (Usable with Caution)
- Throughput 15,000-19,000 evt/sec
- Success Rate 95-99.9%
- P99 Latency 1,000-5,000 ms
- Some failed events (< 5%)

### ❌ FAILED (Not Suitable)
- Throughput < 15,000 evt/sec
- Success Rate < 95%
- P99 Latency > 5,000 ms
- Significant failed events

---

## 🔍 Example Report Output

### Snippet 1: Executive Summary
```markdown
| Metric | Value | Target | Status |
|--------|-------|--------|--------|
| **Actual Throughput** | 20,012 evt/sec | 20,000 evt/sec | ✅ PASS |
| **Events Sent** | 1,200,720 | 1,200,000 | ✅ |
| **Success Rate** | 99.99% | ≥99% | ✅ PASS |
| **Failed Events** | 0 | 0 | ✅ PASS |
```

### Snippet 2: Latency Analysis
```markdown
| Percentile | Latency (ms) | Status |
|-----------|--------------|--------|
| Min | 2.15 | ✅ |
| P50 (Median) | 47.32 | ✅ GOOD |
| P95 | 89.45 | ✅ GOOD |
| P99 | 124.67 | ✅ GOOD |
| Average | 52.18 | ✅ GOOD |
| Max | 856.32 | ✅ ACCEPTABLE |
```

### Snippet 3: Recommendations
```markdown
### ✅ Test Result: PASSED

Summary: Event Hub performing excellently for 20,000 events/sec.

Key Findings:
- ✅ Achieved 20,012 evt/sec (meets or exceeds target)
- ✅ Success rate of 99.99% (excellent reliability)
- ✅ Median latency of 47.32ms (very responsive)
- ✅ P99 latency of 124.67ms (good tail behavior)

Recommendations:
- ✅ Event Hub configuration is suitable for production
- ✅ Monitor real-world patterns for 1+ week before production
- ✅ Maintain current partition count (24) for 20k evt/sec
- ✅ Plan Premium tier upgrade if exceeds 35k evt/sec
```

---

## 📁 Files & Location

```
eventhub/
├── src/
│   ├── Services/
│   │   └── LoadTestService.cs .................. Service implementation
│   ├── Controllers/
│   │   └── LoadTestController.cs .............. API endpoints
│   └── Program.cs ............................. (Updated with DI registration)
│
├── run-load-test.ps1 .......................... PowerShell script
├── LOAD_TEST_GUIDE.md ......................... Comprehensive guide
├── LOAD_TEST_SUMMARY.md ....................... Quick reference
│
└── (Generated after running test)
    └── load-test-report.md ................... Markdown report
```

---

## 🎯 Use Cases

### Pre-Deployment Testing
```powershell
# Verify infrastructure before production use
./run-load-test.ps1 -Duration 60
# ✅ Should PASS
```

### Post-Deployment Validation
```powershell
# Quick sanity check after deployment
./run-load-test.ps1
```

### Extended Stress Testing
```powershell
# Run longer test for stability validation
./run-load-test.ps1 -Duration 300
```

### Performance Baseline
```powershell
# Establish baseline for future comparisons
./run-load-test.ps1 -Duration 60 -ReportPath baseline.md
```

---

## 🛠️ Integration Points

### With Event Hub
- Uses `EventHubProducerService` to send events
- Leverages batch sending capability
- Measures actual Event Hub latency
- Tests production connection string

### With Application
- Registered in `Program.cs` DI container
- Exposed via `LoadTestController` API
- Logs to application's logger
- Uses existing configuration

### With Monitoring
- Can log metrics to Application Insights
- Metrics available in Azure Portal
- Results exportable to CSV (via report)

---

## ⚙️ Configuration

### In LoadTestService.cs
```csharp
// Adjust target throughput
long targetEventsPerSecond = 20_000;

// Adjust batch size
int batchSize = 100;

// Adjust event size/content
events.Add(new LogEvent { ... });
```

### In run-load-test.ps1
```powershell
# Adjust defaults
[int]$Duration = 60
[string]$Endpoint = "http://localhost:5000"
```

---

## 📈 Performance Expectations

### On Standard Tier (24 Partitions)

| Aspect | Expected | Range |
|--------|----------|-------|
| **Throughput** | 20,000 evt/sec | 18,000-22,000 |
| **P50 Latency** | 50 ms | 20-100 |
| **P95 Latency** | 100 ms | 50-200 |
| **P99 Latency** | 200 ms | 100-500 |
| **Success Rate** | 99.9%+ | 99%+ |
| **Max Latency** | 1,000 ms | <2,000 |

---

## 🚨 Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Connection refused | App not running | `dotnet run` first |
| Low throughput | Few partitions | Increase to 32 |
| High latency | Network/throttling | Check Event Hub status |
| Failed events | Connection issues | Verify credentials |
| Timeout | Test too long | Reduce duration |

---

## ✨ Key Features

✅ **Automated**: No manual measurement needed  
✅ **Comprehensive**: 10+ metrics collected  
✅ **Professional**: Markdown report with tables  
✅ **Intelligent**: Automatic pass/fail analysis  
✅ **Actionable**: Specific recommendations  
✅ **Scalable**: Configurable duration  
✅ **Observable**: Detailed logging during test  
✅ **Production-Ready**: Error handling & validation  

---

## 📚 Documentation

| Doc | Purpose | Audience |
|-----|---------|----------|
| LOAD_TEST_GUIDE.md | Comprehensive guide | Everyone |
| LOAD_TEST_SUMMARY.md | Quick reference | Operators |
| This file | Overview | Developers |

---

## 🎉 Ready to Test?

### Quick Start
```powershell
# Terminal 1
dotnet run --configuration Release

# Terminal 2
./run-load-test.ps1

# Result: load-test-report.md generated! 📊
```

### Next Steps
1. Review `LOAD_TEST_GUIDE.md` for detailed usage
2. Run first test: `./run-load-test.ps1`
3. Review generated report
4. Interpret results using pass/fail criteria
5. Optimize if needed, re-test

---

## 📞 Support

- **Guide**: See LOAD_TEST_GUIDE.md
- **Code**: See LoadTestService.cs (350+ lines of comments)
- **API**: See LoadTestController.cs
- **Script**: See run-load-test.ps1 (built-in help)

---

**Status**: ✅ Complete & Ready to Use  
**Test Scenario**: 20,000 events/sec × 60 seconds  
**Output**: Professional markdown report with analysis  
**Time to Production**: Ready now! 🚀

---

## Quick Commands

```powershell
# Run 60-second test
./run-load-test.ps1

# Run 5-minute test
./run-load-test.ps1 -Duration 300

# Run and save to custom path
./run-load-test.ps1 -Duration 60 -ReportPath ./reports/test.md

# Query API info
curl http://localhost:5000/api/loadtest/info

# Run via API
curl "http://localhost:5000/api/loadtest/run?duration=60"
```

That's everything! You're ready to load test. 🎯
