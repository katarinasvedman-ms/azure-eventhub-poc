# Event Hub Load Test Report

**Test Date:** 2025-12-16 13:33:40

## Executive Summary

| Metric | Value |
|--------|-------|
| **Target Throughput** | 20000 events/sec |
| **Actual Throughput** | 22777 events/sec |
| **Duration** | 10.01 seconds |
| **Total Events Sent** | 228000 |
| **Success Rate** | 100% |
| **Failed Events** | 0 |

## Performance Metrics

### Latency (ms)
| Percentile | Latency |
|-----------|---------|
| P50 (Median) | 26 |
| P95 | 48 |
| P99 | 59 |
| Min | 19 |
| Max | 103 |
| Average | 28.74 |

### Throughput Analysis
| Metric | Value |
|--------|-------|
| **Target Rate** | 20000 evt/sec |
| **Achieved Rate** | 22777 evt/sec |
| **Efficiency** | 113.88% |
| **Total Batches** | 228 successful, 0 failed |

## Analysis & Recommendations

### Performance Status
✅ **EXCELLENT** - Load test passed all SLA requirements

### Key Findings

1. **Throughput**: Achieved 22777 evt/sec vs target of 20000 evt/sec
2. **Reliability**: 100% of events delivered with 0 failed batches
3. **Latency**: P99 latency of 59 ms (Max: 103 ms)

---
Generated: 2025-12-16 13:33:40
