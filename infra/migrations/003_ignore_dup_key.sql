-- ============================================================================
-- Migration 003: Switch unique index to IGNORE_DUP_KEY = ON
--
-- WHY:
--   The current SqlEventWriter uses a 4-step staging pattern per batch:
--     1. CREATE #temp  2. BulkCopy → #temp  3. Dedup staging  4. INSERT WHERE NOT EXISTS
--   With IGNORE_DUP_KEY = ON, SqlBulkCopy can write directly into EventLogs.
--   Duplicate rows are silently discarded by SQL Server (warning, not error).
--   This reduces SQL round-trips from 4 → 1 per batch.
--
-- IMPACT:
--   - SqlBulkCopy into a table with IGNORE_DUP_KEY = ON will NOT raise error 2627.
--   - Duplicate rows produce an informational warning (severity 10) but succeed.
--   - Net effect: same idempotency guarantee, ~4x fewer SQL round-trips.
--
-- ROLLBACK:
--   DROP INDEX [UX_EventLogs_EventId_Business] ON [dbo].[EventLogs];
--   CREATE UNIQUE NONCLUSTERED INDEX [UX_EventLogs_EventId_Business]
--       ON [dbo].[EventLogs] ([EventId_Business])
--       WITH (IGNORE_DUP_KEY = OFF, ONLINE = ON, FILLFACTOR = 90);
-- ============================================================================

-- Drop existing index and recreate with IGNORE_DUP_KEY = ON
IF EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE object_id = OBJECT_ID(N'[dbo].[EventLogs]') 
      AND name = 'UX_EventLogs_EventId_Business'
)
BEGIN
    DROP INDEX [UX_EventLogs_EventId_Business] ON [dbo].[EventLogs];
    PRINT 'Dropped existing index UX_EventLogs_EventId_Business';
END
GO

CREATE UNIQUE NONCLUSTERED INDEX [UX_EventLogs_EventId_Business]
    ON [dbo].[EventLogs] ([EventId_Business])
    WITH (IGNORE_DUP_KEY = ON, ONLINE = ON, FILLFACTOR = 90);
PRINT 'Recreated index UX_EventLogs_EventId_Business with IGNORE_DUP_KEY = ON';
GO

-- The permanent staging table is no longer needed. Drop it to reduce clutter.
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[EventLogs_Staging]') AND type = 'U')
BEGIN
    DROP TABLE [dbo].[EventLogs_Staging];
    PRINT 'Dropped EventLogs_Staging table (no longer needed)';
END
GO

PRINT 'Migration 003 complete. Direct bulk insert with silent duplicate rejection is active.';
GO
