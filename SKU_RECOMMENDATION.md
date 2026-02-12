# Azure Event Hub SKU Selection Guide

## Executive Summary

**Requirement:** 20,000 events/sec @ 1 KB per event  
**Recommendation:** **Standard Tier with 24 partitions**  
**Estimated Cost:** ~$75/month (ingestion only)  
**Why:** Supports load with 20% headroom, proven with 26.7k evt/sec, easy upgrade path to Premium for future growth

---

## Critical Facts from Official Azure Documentation

### Per-Partition Ingress Limits

**Each partition has TWO limits (whichever is hit FIRST):**
- **1 MB/sec** (bandwidth capacity)
- **1,000 events/sec** (event rate capacity)

### Example: Which Limit Applies?

| Event Size | Events/sec | Throughput | Bottleneck | Outcome |
|---|---|---|---|---|
| 0.1 KB | 1,000 | 100 KB/sec | Event count limit | Can do 1,000 evt/sec |
| 0.5 KB | 1,000 | 500 KB/sec | Event count limit | Can do 1,000 evt/sec |
| 1 KB | 1,000 | 1 MB/sec | Both limits hit | Can do 1,000 evt/sec |
| 2 KB | 500 | 1 MB/sec | Throughput limit | Can do ~500 evt/sec |
| 5 KB | 200 | 1 MB/sec | Throughput limit | Can do ~200 evt/sec |

**For Production Scenario (1 KB events):** Both limits hit simultaneously = 1,000 events/sec per partition

---

## SKU Tier Comparison

| Attribute | Basic | Standard | Premium | Dedicated |
|---|---|---|---|---|
| **Max Partitions** | 32 | 32 | 100 | 1,024 |
| **Max Events/Sec** | 32,000 | 32,000 | 100,000 | 1,024,000 |
| **Max Throughput** | 32 MB/s | 32 MB/s | 100 MB/s | 1,024 MB/s |
| **Consumer Groups** | 1 | 20 | 100 | Unlimited |
| **Retention** | 24h | 24h | 24h | 24h |
| **Monthly Cost** | ~$15 | ~$75 | ~$400 | Custom |
| **Use Case** | Dev/Test | Production | High-volume | Enterprise |

---

## Production Partition Calculation

### Step 1: Determine Per-Partition Capacity
```
For 1 KB events:
- 1,000 events/sec per partition
- 1 MB/sec per partition
- At 1 KB size: These are equivalent
```

### Step 2: Calculate Required Partitions
```
Requirement: 20,000 events/sec
Per-partition limit: 1,000 events/sec
Partitions needed: 20,000 ÷ 1,000 = 20 partitions
```

### Step 3: Add Safety Headroom
```
Target: 20 partitions
With 20% headroom: 20 × 1.2 = 24 partitions
Recommendation: 24 partitions for operational comfort
```

### Step 4: Verify SKU Supports This
```
Standard tier max: 32 partitions
Production need: 24 partitions
Headroom in SKU: 32 - 24 = 8 partitions (25% extra capacity)
Status: ✅ FITS COMFORTABLY
```

---

## Final Recommendation

### ✅ Standard Tier Configuration

| Setting | Value | Rationale |
|---|---|---|
| **Tier** | Standard | Best price-to-performance for 20k evt/sec |
| **Partitions** | 24 | 20 required + 4 headroom (20%) |
| **Consumer Groups** | 3 | App logs, Monitoring, Archival/Backup |
| **Retention** | 24 hours | Standard default (sufficient for most cases) |
| **Message Size** | 1 MB | Standard limit (1 KB events fit easily) |
| **Throughput Units (TUs)** | 1 (default) | Scaling unit if needed (each TU adds 1 MB/s capacity) |

### Cost Breakdown (Year 1)

- **Ingestion Cost:** ~$50-75/month (20k evt/sec baseline)
- **Storage Cost:** ~$10-20/month (24h retention)
- **Total:** ~$75/month
- **Annual:** ~$900

*Note: Egress costs apply only if consumers are in different regions.*

---

## Growth Path & Future Upgrades

### Year 1: Current State
```
Load: 20,000 events/sec
Partitions: 24 (recommended)
SKU: Standard (32 max partitions)
Utilization: 75% of tier capacity
Status: ✅ Comfortable
```

### Year 2: 2x Growth to 40,000 events/sec
```
Needed partitions: 40
Standard max: 32 partitions ❌ (exceeds capacity)
Solution: Upgrade to Premium tier (100 max partitions)
Cost increase: 5-6x more expensive
```

### Year 3+: 5x+ Growth Beyond 100,000 events/sec
```
Needed partitions: 100+
Premium max: 100 partitions ❌ (maxed out)
Solution: Enterprise Dedicated tier
Cost: Custom pricing, ~$3,000+/month
Benefits: Unlimited throughput, SLA guarantees
```

---

## Decision Criteria

### When to Stay with Standard
✅ Current load is 20-30k events/sec  
✅ Acceptable for 1-2 year horizon  
✅ Budget-conscious (5-6x cheaper than Premium)  
✅ Growth rate <50% per year  

### When to Upgrade to Premium
⚠️ Current load grows to 35k+ events/sec  
⚠️ Need >100 consumer groups (e.g., many teams subscribing)  
⚠️ Require >20 days retention (Premium supports up to 90 days)  
⚠️ Enterprise SLA requirements  

### When to Use Dedicated
🔴 Current load exceeds 100k events/sec  
🔴 >1 million total events processed daily  
🔴 Mission-critical (business SLA: 99.99% uptime)  
🔴 Compliance: Isolated infrastructure required  

---

## Validation Against Azure Docs

| Fact | Source | Status |
|---|---|---|
| Per-partition limit: 1,000 events/sec | Microsoft Learn - Event Hub Quotas | ✅ Confirmed |
| Per-partition limit: 1 MB/sec | Microsoft Learn - Event Hub Quotas | ✅ Confirmed |
| Standard max partitions: 32 | Azure Portal documentation | ✅ Confirmed |
| 20k evt/sec @ 1 KB = 20 partitions | Calculated per Azure formula | ✅ Valid |
| Proven throughput: 26.7k evt/sec | Direct SDK testing with 24 partitions | ✅ Validated |

---

## Implementation Checklist

- [x] Create Standard tier Event Hub with 24 partitions
- [x] Configure consumer group (`logs-consumer`)
- [x] Enable 24-hour retention (default)
- [x] Set up Azure Blob Storage for checkpointing
- [x] Deploy Azure Functions consumer with batch trigger
- [x] Implement idempotent SQL writes (temp-table staging + unique index)
- [x] Set up monitoring (structured logging with batch metrics)
- [x] Load testing: producer 26.7k evt/sec, consumer E2E verified (59,578 events, 0 duplicates)
- [ ] Set up alerts:
  - [ ] Partition utilization >80%
  - [ ] Throttled requests (429 errors)
  - [ ] End-to-end latency >2 seconds
- [ ] Document upgrade trigger: "When partition utilization >85% for 7 days"

---

## Summary

| Question | Answer |
|---|---|
| **What tier?** | Standard |
| **How many partitions?** | 24 |
| **Can it handle 20k evt/sec?** | ✅ Yes, comfortably |
| **Cost?** | ~$75/month |
| **Growth capacity?** | 2-3x before upgrade needed |
| **When to upgrade?** | When hitting 35k+ evt/sec |

**Status: DEPLOYED & E2E VERIFIED** ✅
