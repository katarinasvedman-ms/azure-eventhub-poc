-- Event Hub Logs Table Schema
-- Created for bottleneck testing: Event Hub → SQL DB throughput

CREATE TABLE [dbo].[EventLogs] (
    [EventId] BIGINT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
    [Source] NVARCHAR(100) NOT NULL,
    [Level] NVARCHAR(50) NOT NULL,
    [Message] NVARCHAR(MAX) NOT NULL,
    [PartitionKey] NVARCHAR(100),
    [Timestamp] DATETIME2(7) NOT NULL DEFAULT GETUTCDATE(),
    [CreatedAt] DATETIME2(7) NOT NULL DEFAULT GETUTCDATE()
);

-- Index for querying by timestamp
CREATE NONCLUSTERED INDEX [IX_EventLogs_Timestamp] 
    ON [dbo].[EventLogs]([Timestamp] DESC);

-- Index for filtering by Level
CREATE NONCLUSTERED INDEX [IX_EventLogs_Level] 
    ON [dbo].[EventLogs]([Level])
    INCLUDE ([Message], [Timestamp]);

-- Index for partition key lookups
CREATE NONCLUSTERED INDEX [IX_EventLogs_PartitionKey] 
    ON [dbo].[EventLogs]([PartitionKey])
    INCLUDE ([Level], [Timestamp]);
