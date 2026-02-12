-- ============================================================================
-- Migration: Add idempotency support to EventLogs table
-- 
-- WHY THIS GUARANTEES "EXACTLY-ONCE OUTCOME" UNDER AT-LEAST-ONCE DELIVERY:
--
--   Event Hubs + Functions = at-least-once delivery. The runtime may re-deliver
--   events on host restarts, rebalancing, or if the function throws. Each event
--   carries a stable EventId (set by the producer or derived deterministically
--   from partitionKey + sequenceNumber + offset). The UNIQUE INDEX on EventId
--   causes SQL Server to reject any INSERT that would create a duplicate row
--   (error 2627). The application catches this error and treats it as success
--   ("this event was already persisted"). The net effect is exactly-once in SQL.
--
--   This is Pattern 1 idempotency: INSERT + catch duplicate key.
--   It is race-condition-free (no "check then insert") and requires only one
--   round trip per event.
--
-- EXECUTION ORDER:
--   1. Add the EventId column (nullable initially for existing rows)
--   2. Backfill existing rows with a unique synthetic ID
--   3. Make the column NOT NULL
--   4. Create the unique index
-- ============================================================================

-- Step 1: Add EventId column if it doesn't exist
IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID(N'[dbo].[EventLogs]') 
      AND name = 'EventId_Business'
)
BEGIN
    ALTER TABLE [dbo].[EventLogs]
        ADD [EventId_Business] NVARCHAR(256) NULL;
    PRINT 'Added EventId_Business column';
END
GO

-- Step 2: Backfill existing rows that have NULL EventId_Business
-- Use a deterministic value so re-runs are safe
UPDATE [dbo].[EventLogs]
SET [EventId_Business] = CONCAT('legacy_', CAST([EventId] AS NVARCHAR(20)))
WHERE [EventId_Business] IS NULL;
GO

-- Step 3: Make NOT NULL
ALTER TABLE [dbo].[EventLogs]
    ALTER COLUMN [EventId_Business] NVARCHAR(256) NOT NULL;
GO

-- Step 4: Create unique index for idempotency enforcement
-- Use IGNORE_DUP_KEY = OFF (default) so that individual inserts raise error 2627
-- which the application catches and treats as "already exists = success".
-- 
-- For SqlBulkCopy scenarios, we use a staging pattern instead (see writer code).
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE object_id = OBJECT_ID(N'[dbo].[EventLogs]') 
      AND name = 'UX_EventLogs_EventId_Business'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX [UX_EventLogs_EventId_Business]
        ON [dbo].[EventLogs] ([EventId_Business])
        WITH (ONLINE = ON, FILLFACTOR = 90);
    PRINT 'Created unique index UX_EventLogs_EventId_Business';
END
GO

-- Step 5: Create staging table for idempotent bulk inserts
-- The writer bulk-copies into this staging table, then does
-- INSERT INTO EventLogs SELECT ... FROM staging WHERE NOT EXISTS (...)
-- This avoids duplicate key errors from SqlBulkCopy (which cannot catch per-row errors).
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[EventLogs_Staging]') AND type = 'U')
BEGIN
    CREATE TABLE [dbo].[EventLogs_Staging] (
        [EventId_Business] NVARCHAR(256) NOT NULL,
        [Source]            NVARCHAR(100) NOT NULL,
        [Level]             NVARCHAR(50)  NOT NULL,
        [Message]           NVARCHAR(MAX) NOT NULL,
        [PartitionKey]      NVARCHAR(100) NULL,
        [Timestamp]         DATETIME2(7)  NOT NULL,
        [EnqueuedTimeUtc]   DATETIME2(7)  NULL,
        [SequenceNumber]    BIGINT        NULL
    );
    PRINT 'Created EventLogs_Staging table';
END
GO

-- Add EnqueuedTimeUtc and SequenceNumber to main table for observability
IF NOT EXISTS (
    SELECT 1 FROM sys.columns 
    WHERE object_id = OBJECT_ID(N'[dbo].[EventLogs]') 
      AND name = 'EnqueuedTimeUtc'
)
BEGIN
    ALTER TABLE [dbo].[EventLogs]
        ADD [EnqueuedTimeUtc] DATETIME2(7) NULL,
            [SequenceNumber]  BIGINT       NULL;
    PRINT 'Added EnqueuedTimeUtc and SequenceNumber columns';
END
GO

PRINT 'Migration complete. Idempotency enforcement is active.';
GO
