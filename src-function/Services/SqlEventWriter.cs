using System.Data;
using System.Diagnostics;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace EventHubFunction.Services;

/// <summary>
/// Idempotent SQL writer using direct SqlBulkCopy with IGNORE_DUP_KEY index.
///
/// The UX_EventLogs_EventId_Business unique index has IGNORE_DUP_KEY = ON,
/// which means SQL Server silently discards duplicate EventId_Business values
/// during bulk insert instead of throwing an error. This gives us:
///   - Single bulk operation per batch (no staging table, no temp table, no merge)
///   - Automatic deduplication at the database level
///   - Maximum throughput: 1 SQL round-trip instead of 4
///
/// Previous approach used 4 operations per batch:
///   1. CREATE #temp table  2. BulkCopy → #temp  3. DELETE intra-batch dupes  4. INSERT WHERE NOT EXISTS
/// This simplified approach: just BulkCopy → EventLogs directly.
///
/// Connection pooling: ADO.NET pools connections automatically. We open/close per batch
/// which returns the connection to the pool (not a physical disconnect).
/// </summary>
public interface ISqlEventWriter
{
    Task<BatchWriteResult> WriteBatchAsync(IReadOnlyList<EventRecord> events, CancellationToken ct = default);
}

public class SqlEventWriter : ISqlEventWriter
{
    private readonly string _connectionString;
    private readonly ILogger<SqlEventWriter> _logger;
    private readonly string? _accessToken;

    public SqlEventWriter(string connectionString, ILogger<SqlEventWriter> logger, string? accessToken = null)
    {
        _connectionString = connectionString ?? throw new ArgumentNullException(nameof(connectionString));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _accessToken = accessToken;
    }

    public async Task<BatchWriteResult> WriteBatchAsync(IReadOnlyList<EventRecord> events, CancellationToken ct = default)
    {
        if (events.Count == 0)
            return new BatchWriteResult();

        var sw = Stopwatch.StartNew();
        var result = new BatchWriteResult();

        try
        {
            await using var connection = new SqlConnection(_connectionString);
            if (!string.IsNullOrEmpty(_accessToken))
            {
                connection.AccessToken = _accessToken;
            }
            await connection.OpenAsync(ct);

            // Direct bulk copy into EventLogs.
            // IGNORE_DUP_KEY on UX_EventLogs_EventId_Business silently discards duplicates.
            var dataTable = BuildDataTable(events);

            using var bulkCopy = new SqlBulkCopy(connection, SqlBulkCopyOptions.Default, null);
            bulkCopy.DestinationTableName = "[dbo].[EventLogs]";
            bulkCopy.ColumnMappings.Add("EventId_Business", "EventId_Business");
            bulkCopy.ColumnMappings.Add("Source", "Source");
            bulkCopy.ColumnMappings.Add("Level", "Level");
            bulkCopy.ColumnMappings.Add("Message", "Message");
            bulkCopy.ColumnMappings.Add("PartitionKey", "PartitionKey");
            bulkCopy.ColumnMappings.Add("Timestamp", "Timestamp");
            bulkCopy.ColumnMappings.Add("EnqueuedTimeUtc", "EnqueuedTimeUtc");
            bulkCopy.ColumnMappings.Add("SequenceNumber", "SequenceNumber");
            bulkCopy.BatchSize = events.Count; // Single batch — already bounded by maxEventBatchSize
            bulkCopy.BulkCopyTimeout = 120;
            bulkCopy.EnableStreaming = true;

            await bulkCopy.WriteToServerAsync(dataTable, ct);

            // With IGNORE_DUP_KEY, duplicates are silently discarded — no error, no way to
            // distinguish inserted vs skipped. Report batch count as inserted.
            result.InsertedCount = events.Count;

            sw.Stop();
            _logger.LogDebug(
                "SQL write: {Count} events bulk-copied in {DurationMs}ms",
                events.Count, sw.ElapsedMilliseconds);
        }
        catch (SqlException ex) when (ex.Number == 2627 || ex.Number == 2601)
        {
            // Safety net: shouldn't happen with IGNORE_DUP_KEY, but handle gracefully.
            _logger.LogWarning(
                "Unexpected duplicate key during batch write (SqlError={ErrorNumber}). Events: {Count}",
                ex.Number, events.Count);
            result.DuplicateCount = events.Count;
        }
        catch (Exception ex)
        {
            sw.Stop();
            _logger.LogError(ex,
                "SQL batch write failed after {DurationMs}ms for {EventCount} events",
                sw.ElapsedMilliseconds, events.Count);
            throw; // Re-throw to trigger Function retry (no checkpoint = re-delivery)
        }

        return result;
    }

    private static DataTable BuildDataTable(IReadOnlyList<EventRecord> events)
    {
        var dt = new DataTable();
        dt.Columns.Add("EventId_Business", typeof(string));
        dt.Columns.Add("Source", typeof(string));
        dt.Columns.Add("Level", typeof(string));
        dt.Columns.Add("Message", typeof(string));
        dt.Columns.Add("PartitionKey", typeof(string));
        dt.Columns.Add("Timestamp", typeof(DateTime));
        dt.Columns.Add("EnqueuedTimeUtc", typeof(DateTime));
        dt.Columns.Add("SequenceNumber", typeof(long));

        foreach (var e in events)
        {
            dt.Rows.Add(
                e.EventId,
                e.Source,
                e.Level,
                e.Message,
                (object?)e.PartitionKey ?? DBNull.Value,
                e.Timestamp,
                e.EnqueuedTimeUtc,
                e.SequenceNumber);
        }

        return dt;
    }
}
