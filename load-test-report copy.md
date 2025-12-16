# Event Hub Load Test Report

**Test Date:** 2025-12-16 13:05:48

## Executive Summary

| Metric | Value |
|--------|-------|
| **Target Throughput** | 20000 events/sec |
| **Actual Throughput** | 22360 events/sec |
| **Duration** | 10.02 seconds |
| **Total Events Sent** | 224000 |
| **Success Rate** | 100% |
| **Failed Events** | 0 |

## Performance Metrics

### Latency (ms)
| Percentile | Latency |
|-----------|---------|
| P50 (Median) | 26 |
| P95 | 41 |
| P99 | 61 |
| Min | 17 |
| Max | 91 |
| Average | 27.96 |

### Throughput Analysis
| Metric | Value |
|--------|-------|
| **Target Rate** | 20000 evt/sec |
| **Achieved Rate** | 22360 evt/sec |
| **Efficiency** | 111.8% |
| **Total Batches** | 224 successful, 0 failed |

## Analysis & Recommendations

### Performance Status
✅ **EXCELLENT** - Load test passed all SLA requirements

### Key Findings

1. **Throughput**: Achieved 22360 evt/sec vs target of 20000 evt/sec
2. **Reliability**: 100% of events delivered with 0 failed batches
3. **Latency**: P99 latency of 61 ms (Max: 91 ms)

---
Generated: 2025-12-16 13:05:48
