-- ============================================================================
-- E2E Latency Report — Run after consumer has drained all events
--
-- Replace @testRunId with the value printed by the producer load test.
-- ============================================================================

DECLARE @testRunId NVARCHAR(100) = 'loadtest-REPLACE-ME';

-- Summary
SELECT
    @testRunId                                                    AS TestRunId,
    COUNT(*)                                                      AS TotalEvents,
    AVG(DATEDIFF(MILLISECOND, [Timestamp], CreatedAt))            AS AvgE2E_ms,
    MIN(DATEDIFF(MILLISECOND, [Timestamp], CreatedAt))            AS MinE2E_ms,
    MAX(DATEDIFF(MILLISECOND, [Timestamp], CreatedAt))            AS MaxE2E_ms,
    AVG(DATEDIFF(MILLISECOND, [Timestamp], EnqueuedTimeUtc))      AS AvgProducerToEH_ms,
    AVG(DATEDIFF(MILLISECOND, EnqueuedTimeUtc, CreatedAt))        AS AvgEHToSQL_ms,
    MIN([Timestamp])                                              AS FirstEventCreated,
    MAX(CreatedAt)                                                AS LastEventInserted,
    DATEDIFF(SECOND, MIN([Timestamp]), MAX(CreatedAt))            AS WallClockSeconds,
    CAST(COUNT(*) * 1.0 / NULLIF(DATEDIFF(SECOND, MIN([Timestamp]), MAX(CreatedAt)), 0) AS DECIMAL(10,1))
                                                                  AS EffectiveEventsPerSec
FROM EventLogs
WHERE Source = @testRunId;

-- Percentile breakdown (P50, P95, P99)
SELECT
    @testRunId AS TestRunId,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY DATEDIFF(MILLISECOND, [Timestamp], CreatedAt))
        OVER () AS P50_E2E_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY DATEDIFF(MILLISECOND, [Timestamp], CreatedAt))
        OVER () AS P95_E2E_ms,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY DATEDIFF(MILLISECOND, [Timestamp], CreatedAt))
        OVER () AS P99_E2E_ms
FROM EventLogs
WHERE Source = @testRunId
OFFSET 0 ROWS FETCH FIRST 1 ROWS ONLY;

-- Per-second throughput (how fast did events land in SQL?)
SELECT
    DATEADD(SECOND, DATEDIFF(SECOND, '2000-01-01', CreatedAt), '2000-01-01') AS SecondBucket,
    COUNT(*) AS EventsInserted
FROM EventLogs
WHERE Source = @testRunId
GROUP BY DATEADD(SECOND, DATEDIFF(SECOND, '2000-01-01', CreatedAt), '2000-01-01')
ORDER BY SecondBucket;
