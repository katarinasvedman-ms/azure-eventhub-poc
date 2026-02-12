-- ============================================================
-- Azure Load Testing – E2E Pipeline Analysis
-- Run AFTER the load test completes to measure full pipeline
-- ============================================================

-- 1. Total events ingested from the load test
SELECT 
    COUNT(*) AS TotalEvents,
    MIN(Timestamp) AS FirstEvent,
    MAX(Timestamp) AS LastEvent,
    DATEDIFF(SECOND, MIN(Timestamp), MAX(Timestamp)) AS DurationSec,
    CAST(COUNT(*) AS FLOAT) / NULLIF(DATEDIFF(SECOND, MIN(Timestamp), MAX(Timestamp)), 0) AS AvgEventsPerSec
FROM LogEvents
WHERE Source IN ('AzureLoadTest', 'AzureLoadTest-Single')
  AND Timestamp > DATEADD(HOUR, -1, GETUTCDATE());

-- 2. Breakdown by endpoint pattern (batch vs single)
SELECT 
    Source,
    COUNT(*) AS EventCount,
    MIN(Timestamp) AS FirstEvent,
    MAX(Timestamp) AS LastEvent,
    DATEDIFF(SECOND, MIN(Timestamp), MAX(Timestamp)) AS DurationSec,
    CAST(COUNT(*) AS FLOAT) / NULLIF(DATEDIFF(SECOND, MIN(Timestamp), MAX(Timestamp)), 0) AS EvtPerSec
FROM LogEvents
WHERE Source IN ('AzureLoadTest', 'AzureLoadTest-Single')
  AND Timestamp > DATEADD(HOUR, -1, GETUTCDATE())
GROUP BY Source;

-- 3. Consumer throughput over time (10-second buckets)
SELECT 
    DATEADD(SECOND, (DATEDIFF(SECOND, '2000-01-01', ProcessedAt) / 10) * 10, '2000-01-01') AS TimeBucket,
    COUNT(*) AS EventsInBucket,
    COUNT(*) / 10.0 AS EvtPerSec
FROM LogEvents
WHERE Source IN ('AzureLoadTest', 'AzureLoadTest-Single')
  AND Timestamp > DATEADD(HOUR, -1, GETUTCDATE())
GROUP BY DATEADD(SECOND, (DATEDIFF(SECOND, '2000-01-01', ProcessedAt) / 10) * 10, '2000-01-01')
ORDER BY TimeBucket;

-- 4. Duplicate check (should be 0)
SELECT 
    COUNT(*) AS TotalRows,
    COUNT(DISTINCT EventId) AS UniqueEvents,
    COUNT(*) - COUNT(DISTINCT EventId) AS DuplicateRows
FROM LogEvents
WHERE Source IN ('AzureLoadTest', 'AzureLoadTest-Single')
  AND Timestamp > DATEADD(HOUR, -1, GETUTCDATE());

-- 5. E2E latency: time from event creation to SQL insert (requires ProcessedAt column)
SELECT 
    COUNT(*) AS SampleSize,
    AVG(DATEDIFF(MILLISECOND, Timestamp, ProcessedAt)) AS AvgE2ELatencyMs,
    PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY DATEDIFF(MILLISECOND, Timestamp, ProcessedAt)) OVER () AS P50_E2E_Ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY DATEDIFF(MILLISECOND, Timestamp, ProcessedAt)) OVER () AS P95_E2E_Ms,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY DATEDIFF(MILLISECOND, Timestamp, ProcessedAt)) OVER () AS P99_E2E_Ms
FROM LogEvents
WHERE Source IN ('AzureLoadTest', 'AzureLoadTest-Single')
  AND Timestamp > DATEADD(HOUR, -1, GETUTCDATE())
  AND ProcessedAt IS NOT NULL;
