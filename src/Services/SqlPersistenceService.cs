using System;
using System.Collections.Generic;
using System.Data;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace MetricSysPoC.Services;

/// <summary>
/// SQL persistence service for writing events to Azure SQL Database.
/// Used for bottleneck testing to measure throughput impact of persistence layer.
/// </summary>
public interface ISqlPersistenceService
{
    Task<int> InsertEventsAsync(List<EventLogEntry> events, CancellationToken cancellationToken = default);
    Task<int> BulkInsertEventsAsync(List<EventLogEntry> events, CancellationToken cancellationToken = default);
}

public class EventLogEntry
{
    public string? Source { get; set; }
    public string? Level { get; set; }
    public string? Message { get; set; }
    public string? PartitionKey { get; set; }
    public DateTime Timestamp { get; set; }
}

public class SqlPersistenceService : ISqlPersistenceService
{
    private readonly string _connectionString;
    private readonly ILogger<SqlPersistenceService> _logger;

    public SqlPersistenceService(IConfiguration configuration, ILogger<SqlPersistenceService> logger)
    {
        _connectionString = configuration.GetConnectionString("SqlDatabase") ?? string.Empty;
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));

        if (string.IsNullOrEmpty(_connectionString))
        {
            throw new InvalidOperationException("SqlDatabase connection string not configured in appsettings.json");
        }
    }

    /// <summary>
    /// Insert events one at a time (slower, for testing baseline).
    /// </summary>
    public async Task<int> InsertEventsAsync(List<EventLogEntry> events, CancellationToken cancellationToken = default)
    {
        if (events == null || events.Count == 0)
            return 0;

        int rowsInserted = 0;

        try
        {
            using (var connection = new SqlConnection(_connectionString))
            {
                await connection.OpenAsync(cancellationToken);

                foreach (var evt in events)
                {
                    const string sql = @"
                        INSERT INTO [dbo].[EventLogs] 
                            ([Source], [Level], [Message], [PartitionKey], [Timestamp])
                        VALUES 
                            (@source, @level, @message, @partitionKey, @timestamp)";

                    using (var command = new SqlCommand(sql, connection))
                    {
                        command.CommandTimeout = 30;
                        command.Parameters.AddWithValue("@source", (object?)evt.Source ?? DBNull.Value);
                        command.Parameters.AddWithValue("@level", (object?)evt.Level ?? "INFO");
                        command.Parameters.AddWithValue("@message", (object?)evt.Message ?? DBNull.Value);
                        command.Parameters.AddWithValue("@partitionKey", (object?)evt.PartitionKey ?? DBNull.Value);
                        command.Parameters.AddWithValue("@timestamp", evt.Timestamp);

                        await command.ExecuteNonQueryAsync(cancellationToken);
                        rowsInserted++;
                    }
                }
            }

            _logger.LogDebug("Inserted {RowCount} events into SQL Database", rowsInserted);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to insert {EventCount} events into SQL Database", events.Count);
            throw;
        }

        return rowsInserted;
    }

    /// <summary>
    /// Bulk insert events for better performance and throughput.
    /// Uses SqlBulkCopy for optimal performance.
    /// </summary>
    public async Task<int> BulkInsertEventsAsync(List<EventLogEntry> events, CancellationToken cancellationToken = default)
    {
        if (events == null || events.Count == 0)
            return 0;

        try
        {
            using (var connection = new SqlConnection(_connectionString))
            {
                await connection.OpenAsync(cancellationToken);

                var table = new DataTable();
                table.Columns.Add("Source", typeof(string));
                table.Columns.Add("Level", typeof(string));
                table.Columns.Add("Message", typeof(string));
                table.Columns.Add("PartitionKey", typeof(string));
                table.Columns.Add("Timestamp", typeof(DateTime));

                foreach (var evt in events)
                {
                    table.Rows.Add(
                        evt.Source ?? "",
                        evt.Level ?? "INFO",
                        evt.Message ?? "",
                        evt.PartitionKey ?? (object)DBNull.Value,
                        evt.Timestamp
                    );
                }

                using (var bulkCopy = new SqlBulkCopy(connection, SqlBulkCopyOptions.Default, null))
                {
                    bulkCopy.DestinationTableName = "[dbo].[EventLogs]";
                    bulkCopy.ColumnMappings.Add("Source", "Source");
                    bulkCopy.ColumnMappings.Add("Level", "Level");
                    bulkCopy.ColumnMappings.Add("Message", "Message");
                    bulkCopy.ColumnMappings.Add("PartitionKey", "PartitionKey");
                    bulkCopy.ColumnMappings.Add("Timestamp", "Timestamp");
                    bulkCopy.BatchSize = 1000;
                    bulkCopy.BulkCopyTimeout = 300; // 5 minutes

                    await bulkCopy.WriteToServerAsync(table, cancellationToken);
                }

                _logger.LogDebug("Bulk inserted {RowCount} events into SQL Database", events.Count);
                return events.Count;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to bulk insert {EventCount} events into SQL Database", events.Count);
            throw;
        }
    }
}
