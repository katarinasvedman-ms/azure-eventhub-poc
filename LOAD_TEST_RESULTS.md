# Load Test Results Summary

## Test Configuration (Common)
- **Test file**: `load-test/api-load-test.jmx`
- **Threads**: 250 batch + 50 single (300 total per engine)
- **Engines**: 2
- **Duration**: ~5 minutes
- **Target endpoint**: `api-logsysng-eyeqfiorm5tv2.azurewebsites.net/api/logs/ingest`

---

## Run 1 — Baseline

**Date**: 2026-02-12, 17:51 – 17:56  
**Test Run ID**: b48841db-74b7-4aa3-9a4c-b30c0ef25068  
**Changes**: None (initial configuration)

### Infrastructure
| Component | Configuration |
|-----------|--------------|
| Web App | P1v3, autoscale min=1, max=5 |
| Event Hub | Standard, 20 TU, auto-inflate max 20, 24 partitions |
| Function App | EP1 (1 vCPU, 3.5 GB), max 10 elastic workers |
| Azure SQL | P1 (125 DTU) |
| SqlEventWriter | 4-operation staging table pattern (CREATE temp → BulkCopy → DELETE dupes → INSERT WHERE NOT EXISTS) |

### API-Side Results (Azure Load Testing)
| Metric | Value |
|--------|-------|
| Load | **836,096** total requests |
| Duration | 5 mins 4 secs |
| Virtual Users (Max) | 552 |
| Throughput | **2,750.32 req/sec** |
| Response Time (P90) | **268.00 ms** |
| Errors | **0%** |

### Consumer-Side Observations
- Function instances: limited by EP1 cap
- SQL DTU: **841%** (overloaded on P1)
- Event Hub: 73% capacity, 0 throttling
- Consumer drain rate: ~2,850 events/sec

### Bottleneck Identified
- **Function EP1** (1 vCPU) + **4-operation staging SQL pattern** = consumer throughput ceiling
- SQL P1 also overloaded but not the primary limiter

---

## Run 2 — Infrastructure Scaling

**Date**: 2026-02-12, 18:47 – 18:52  
**Test Run ID**: b48841db-74b7-4aa3-9a4c-b30c0ef250b9  
**Changes from Run 1**:
- Web App autoscale: min=1→**3**, max=5→**15**
- Event Hub auto-inflate: max 20→**40 TU**
- Function max elastic workers: 10→**20**
- Azure SQL: P1→**P4 (500 DTU)**

### Infrastructure
| Component | Configuration |
|-----------|--------------|
| Web App | P1v3, autoscale min=3, max=15 |
| Event Hub | Standard, 20 TU, auto-inflate max 40, 24 partitions |
| Function App | EP1 (1 vCPU, 3.5 GB), max 20 elastic workers |
| Azure SQL | P4 (500 DTU) |
| SqlEventWriter | 4-operation staging table pattern (unchanged) |

### API-Side Results (Azure Load Testing)
| Metric | Value |
|--------|-------|
| Load | **1.98 M** total requests |
| Duration | 5 mins 3 secs |
| Virtual Users (Max) | 552 |
| Throughput | **6,496.99 req/sec** |
| Response Time (P90) | **192.00 ms** |
| Errors | **0%** |

### Improvement vs Run 1
- **Throughput: 2,750 → 6,497 req/sec (+136%)**
- **Load: 836K → 1.98M requests (+137%)**
- Response time improved: 268ms → 192ms (-28%)
- Primary driver: Web App autoscale increase (more API instances to push to Event Hub)

---

## Run 3 — Function + SQL Writer Optimization

**Date**: 2026-02-12, 19:48 – 19:53  
**Test Run ID**: b48841db-74b7-4aa3-9a4c-b30c0ef250ee  
**Changes from Run 2**:
- Function App: EP1→**EP3 (4 vCPU, 14 GB per instance)**
- SqlEventWriter: **Simplified** — removed 4-operation staging table, replaced with single direct `SqlBulkCopy`
- Added `IGNORE_DUP_KEY=ON` unique index on `EventId_Business` (dedup handled by SQL engine)

### Infrastructure
| Component | Configuration |
|-----------|--------------|
| Web App | P1v3, autoscale min=3, max=15 |
| Event Hub | Standard, 20 TU, auto-inflate max 40, 24 partitions |
| Function App | **EP3 (4 vCPU, 14 GB)**, max 20 elastic workers |
| Azure SQL | P4 (500 DTU) |
| SqlEventWriter | **Single direct SqlBulkCopy** (IGNORE_DUP_KEY handles dedup) |

### API-Side Results (Azure Load Testing)
| Metric | Value |
|--------|-------|
| Load | **2.01 M** total requests |
| Duration | 5 mins 4 secs |
| Virtual Users (Max) | 543 |
| Throughput | **6,493.48 req/sec** |
| Response Time (P90) | **206.00 ms** |
| Errors | **0%** |

### Consumer-Side Results (SQL Analysis)
| Metric | Value |
|--------|-------|
| **Total rows inserted** | **9,377,012** |
| **Duplicates** | **0** (IGNORE_DUP_KEY perfect) |
| Function instances | **20** (max, all active) |
| Event Hub enqueue window | 18:48 – 18:53 (5 min — test duration) |
| SQL insert window | 18:48 – 18:58 (**10 min 20 sec**) |
| Backlog drain time | **~5 min 20 sec** after test ended |
| **Sustained consumer rate** | **~15,700 events/sec** |
| SQL DTU | **100%** (saturated throughout) |
| Avg lag (enqueue → SQL) | **166 seconds** |
| Max lag | 382 seconds (6.4 min) |
| Distinct partitions | 1,500 |
| Sources | 96.5% batch, 3.5% single |

### Consumer Throughput Per Minute (SQL inserts)
| Minute | Rows Inserted | Rate (/sec) |
|--------|--------------|-------------|
| 18:48 | 88,520 | ~1,475 (ramp-up) |
| 18:49 | 1,007,900 | **16,798** |
| 18:50 | 978,000 | **16,300** |
| 18:51 | 948,000 | **15,800** |
| 18:52 | 940,000 | **15,667** |
| 18:53 | 938,000 | **15,633** |
| 18:54 | 934,000 | **15,567** (draining backlog) |
| 18:55 | 944,000 | **15,733** |
| 18:56 | 943,608 | **15,727** |
| 18:57 | 927,869 | **15,464** |
| 18:58 | 727,115 | ~12,119 (tail) |

### Event Hub Enqueue Rate Per Minute
| Minute | Events Enqueued | Rate (/sec) |
|--------|----------------|-------------|
| 18:48 | 662,586 | ~11,043 |
| 18:49 | 2,074,144 | **34,569** |
| 18:50 | 2,004,402 | **33,407** |
| 18:51 | 1,980,831 | **33,014** |
| 18:52 | 1,723,446 | **28,724** |
| 18:53 | 931,603 | ~15,527 (tail) |

### Improvement vs Run 2
- **API throughput: ~unchanged** (6,497 → 6,493/s — expected, changes were consumer-side)
- **Consumer drain rate: ~2,850 → ~15,700 events/sec (+451%)** — much higher than initial estimate
- **9.4M events** pushed into Event Hub in 5 min (~31K events/sec enqueue rate)
- Function scaled to full 20 instances on EP3
- Zero duplicates — IGNORE_DUP_KEY working perfectly
- SQL P4 now the bottleneck (100% DTU with 20 concurrent bulk writers)
- **Only need ~27% more consumer throughput to hit 20K/s target**

---

## Summary Table

| Metric | Run 1 (Baseline) | Run 2 (Infra Scale) | Run 3 (Code + EP3) |
|--------|-------------------|---------------------|---------------------|
| **Load** | 836K | 1.98M | 2.01M |
| **API Throughput** | 2,750/s | 6,497/s | 6,493/s |
| **Response Time (P90)** | 268 ms | 192 ms | 206 ms |
| **Errors** | 0% | 0% | 0% |
| **Virtual Users** | 552 | 552 | 543 |
| **Total Events to SQL** | — | — | 9,377,012 |
| **Consumer Drain Rate** | ~2,850/s | — | **~15,700/s** |
| **Duplicates** | — | — | 0 |
| **Avg Lag (EH→SQL)** | — | — | 166s |
| **Backlog Drain Time** | — | — | ~5 min |
| **Function SKU** | EP1 (1 vCPU) | EP1 (1 vCPU) | EP3 (4 vCPU) |
| **Function Instances** | limited | — | 20 |
| **SQL Tier** | P1 (125 DTU) | P4 (500 DTU) | P4 (500 DTU) |
| **SQL DTU%** | 841% | — | 100% |
| **Bottleneck** | Function + SQL | Web App (API) ceiling | SQL |

---

## Key Takeaways

1. **Event Hub buffer pattern works** — API→EH ingestion runs at full speed with 0 errors regardless of consumer capacity.
2. **API throughput jumped 2.36x** (2,750 → 6,497/s) by scaling Web App autoscale (min=3, max=15).
3. **Consumer drain rate improved 5.5x** (2,850 → 15,700/s) by upgrading Function to EP3 + simplifying SqlEventWriter.
4. **15,700/s is 78% of 20K target** — only ~27% more SQL capacity needed to reach 20K/s consumer throughput.
5. **Zero duplicates** across 9.4M events — IGNORE_DUP_KEY dedup strategy is flawless.
6. **Bottleneck shifted progressively**: Function → SQL (classic bottleneck migration).
7. **Runs 2 & 3 same API throughput** confirms consumer-side changes don't affect ingestion rate — the buffer pattern decouples them.
8. **Run 1 only pushed 836K requests** vs ~2M in runs 2/3 — Web App was the API-side bottleneck in run 1.
9. **Next bottleneck**: SQL P4 (500 DTU) at 100%. Scaling to P6 (1000 DTU, +100%) should push consumer past 20K/s.
10. **Event Hub enqueued ~31K events/sec** during the test — far more than API req/sec because batch requests expand to multiple events.

---

## Next Steps
- [ ] **Scale SQL to P6 (1000 DTU)** — doubling DTU should push consumer from 15,700 → ~20K+/sec
- [ ] Increase ALT threads/engines to push toward 20k req/sec API throughput
- [ ] Run spike test (`spike-test.jmx` — 5 engines, 1000 threads)
- [ ] **Scale back to dev SKUs** after testing (EP3 + P4 = ~$1,550/mo)
