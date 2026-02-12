-- ============================================================================
-- SPIKE TEST: Pre/Post-Test SQL Queries
-- Purpose: Measure Event Hub → SQL drain time after a 20k req/sec spike
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  RUN BEFORE TEST: Record baseline count                                ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- 1. Baseline row count (run immediately before starting the test)
SELECT COUNT(*) AS BaselineCount FROM EventLogs;


-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  RUN AFTER TEST: Measure spike events and drain time                   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- 2. Total spike events landed in SQL
SELECT 
    COUNT(*) AS TotalSpikeEvents,
    MIN(CreatedAt) AS FirstEvent,
    MAX(CreatedAt) AS LastEvent,
    DATEDIFF(SECOND, MIN(CreatedAt), MAX(CreatedAt)) AS DrainDurationSeconds
FROM EventLogs
WHERE Source IN ('SpikeTest-Batch', 'SpikeTest-Single');

-- 3. Per-source breakdown
SELECT 
    Source,
    COUNT(*) AS EventCount,
    MIN(CreatedAt) AS FirstEvent,
    MAX(CreatedAt) AS LastEvent
FROM EventLogs
WHERE Source IN ('SpikeTest-Batch', 'SpikeTest-Single')
GROUP BY Source;

-- 4. Consumer throughput over time (10-second buckets)
--    Shows ingestion rate and when the backlog finishes draining
SELECT 
    DATEADD(SECOND, 
        (DATEDIFF(SECOND, '2000-01-01', CreatedAt) / 10) * 10, 
        '2000-01-01') AS TimeBucket,
    COUNT(*) AS EventsInBucket,
    COUNT(*) / 10.0 AS EventsPerSecond
FROM EventLogs
WHERE Source IN ('SpikeTest-Batch', 'SpikeTest-Single')
GROUP BY DATEADD(SECOND, 
    (DATEDIFF(SECOND, '2000-01-01', CreatedAt) / 10) * 10, 
    '2000-01-01')
ORDER BY TimeBucket;

-- 5. Duplicate check (should be 0)
SELECT 
    COUNT(*) AS DuplicateCount
FROM (
    SELECT EventId, COUNT(*) AS Cnt
    FROM EventLogs
    WHERE Source IN ('SpikeTest-Batch', 'SpikeTest-Single')
    GROUP BY EventId
    HAVING COUNT(*) > 1
) dupes;

-- 6. Key metric: How long after the test stopped did events keep arriving?
--    Compare the ALT test end time vs the last SQL insert time.
--    Expected: test runs for ~2 min, SQL keeps receiving for N more minutes = drain time.
--    The drain time tells us how much Event Hub is buffering during the spike.
SELECT 
    MIN(CreatedAt) AS FirstSQLInsert,
    MAX(CreatedAt) AS LastSQLInsert,
    DATEDIFF(SECOND, MIN(CreatedAt), MAX(CreatedAt)) AS TotalSQLDurationSeconds,
    -- If test duration is ~150s (30s ramp + 120s), anything beyond that is drain
    CASE 
        WHEN DATEDIFF(SECOND, MIN(CreatedAt), MAX(CreatedAt)) > 150 
        THEN DATEDIFF(SECOND, MIN(CreatedAt), MAX(CreatedAt)) - 150
        ELSE 0
    END AS EstimatedDrainSeconds
FROM EventLogs
WHERE Source IN ('SpikeTest-Batch', 'SpikeTest-Single');
