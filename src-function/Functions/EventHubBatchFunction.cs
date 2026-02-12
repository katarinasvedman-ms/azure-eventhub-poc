using Azure.Messaging.EventHubs;
using EventHubFunction.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Diagnostics;
using System.Text.Json;

namespace EventHubFunction.Functions;

/// <summary>
/// Azure Function triggered by Event Hubs using batch mode.
///
/// Key design decisions:
/// 1. Batch signature (EventData[]) — the runtime delivers up to maxEventBatchSize events
///    and only checkpoints AFTER this method returns successfully.
/// 2. Per-event error handling — one poison event must not kill the entire batch. We catch
///    deserialization failures, log them, and continue. Only infrastructure failures
///    (SQL down, network partitioned) should throw and trigger a retry of the whole batch.
/// 3. Idempotency is enforced at the SQL layer (unique index on EventId). The writer
///    treats duplicate-key errors (2627/2601) as success, so replayed events are harmless.
/// 4. Checkpointing only happens after the function returns successfully. If we throw,
///    the runtime does NOT checkpoint and the batch will be re-delivered.
/// </summary>
public class EventHubBatchFunction
{
    private readonly ISqlEventWriter _sqlWriter;
    private readonly ILogger<EventHubBatchFunction> _logger;

    public EventHubBatchFunction(ISqlEventWriter sqlWriter, ILogger<EventHubBatchFunction> logger)
    {
        _sqlWriter = sqlWriter;
        _logger = logger;
    }

    [Function(nameof(ProcessEventBatch))]
    public async Task ProcessEventBatch(
        [EventHubTrigger("%EventHubName%", Connection = "EventHubConnection",
            ConsumerGroup = "%EventHubConsumerGroup%")]
        EventData[] events,
        FunctionContext context)
    {
        if (events is null || events.Length == 0)
            return;

        var sw = Stopwatch.StartNew();
        var batchSize = events.Length;
        var deserializedEvents = new List<EventRecord>(batchSize);
        var poisonCount = 0;

        // ── Step 1: Deserialize all events, isolating poison messages ──
        foreach (var eventData in events)
        {
            try
            {
                var body = eventData.EventBody.ToString();
                if (string.IsNullOrWhiteSpace(body))
                {
                    poisonCount++;
                    continue;
                }

                var record = DeserializeEvent(body, eventData);
                if (record is not null)
                {
                    deserializedEvents.Add(record);
                }
                else
                {
                    poisonCount++;
                }
            }
            catch (JsonException ex)
            {
                // Poison event — log at Warning (not Error) to avoid alert fatigue.
                // These are non-retryable; skipping is intentional.
                poisonCount++;
                _logger.LogWarning(ex, "Poison event skipped: malformed JSON. SequenceNumber={SeqNo}, Offset={Offset}",
                    eventData.SequenceNumber, eventData.Offset);
            }
        }

        if (poisonCount > 0)
        {
            _logger.LogWarning("Batch contained {PoisonCount} poison events out of {BatchSize}",
                poisonCount, batchSize);
        }

        // ── Step 2: Persist valid events to SQL (idempotent bulk write) ──
        if (deserializedEvents.Count > 0)
        {
            var writeResult = await _sqlWriter.WriteBatchAsync(
                deserializedEvents, context.CancellationToken);

            sw.Stop();

            _logger.LogInformation(
                "Batch processed: Received={Received}, Persisted={Persisted}, Duplicates={Duplicates}, " +
                "Poison={Poison}, Duration={DurationMs}ms",
                batchSize,
                writeResult.InsertedCount,
                writeResult.DuplicateCount,
                poisonCount,
                sw.ElapsedMilliseconds);
        }
        else
        {
            sw.Stop();
            _logger.LogWarning("Entire batch of {BatchSize} events was poison/empty. Duration={DurationMs}ms",
                batchSize, sw.ElapsedMilliseconds);
        }

        // ── Step 3: Checkpoint is automatic ──
        // The Functions runtime checkpoints after this method returns without throwing.
        // If we throw, NO checkpoint is written and the batch will be re-delivered.
        // Because our SQL writes are idempotent, re-delivery is safe.
    }

    /// <summary>
    /// Deserialize a single event body into an <see cref="EventRecord"/>.
    /// Returns null if the event is invalid but not worth throwing for.
    /// </summary>
    private EventRecord? DeserializeEvent(string body, EventData eventData)
    {
        using var doc = JsonDocument.Parse(body);
        var root = doc.RootElement;

        // The event's unique ID is the cornerstone of idempotency.
        // Prefer the "id" field from the payload (set by the producer).
        // Fall back to a deterministic composite: partitionKey + sequenceNumber + offset.
        string eventId;
        if (root.TryGetProperty("id", out var idProp) || root.TryGetProperty("Id", out idProp))
        {
            eventId = idProp.GetString() ?? "";
        }
        else
        {
            // Deterministic fallback: partition + sequence number guarantees uniqueness within a partition
            eventId = $"{eventData.PartitionKey ?? "none"}_{eventData.SequenceNumber}_{eventData.Offset}";
        }

        if (string.IsNullOrWhiteSpace(eventId))
        {
            _logger.LogWarning("Event has empty ID; cannot guarantee idempotency. SeqNo={SeqNo}", eventData.SequenceNumber);
            return null;
        }

        var source = root.TryGetProperty("source", out var s) ? s.GetString()
                   : root.TryGetProperty("Source", out s) ? s.GetString()
                   : "Unknown";

        var level = root.TryGetProperty("level", out var l) ? l.GetString()
                  : root.TryGetProperty("Level", out l) ? l.GetString()
                  : "INFO";

        var message = root.TryGetProperty("message", out var m) ? m.GetString()
                    : root.TryGetProperty("Message", out m) ? m.GetString()
                    : "";

        var partitionKey = root.TryGetProperty("partitionKey", out var pk) ? pk.GetString()
                         : root.TryGetProperty("PartitionKey", out pk) ? pk.GetString()
                         : eventData.PartitionKey;

        DateTime timestamp;
        if (root.TryGetProperty("timestamp", out var ts) || root.TryGetProperty("Timestamp", out ts))
        {
            timestamp = ts.ValueKind == JsonValueKind.String && DateTime.TryParse(ts.GetString(), out var parsed)
                ? parsed
                : DateTime.UtcNow;
        }
        else
        {
            timestamp = DateTime.UtcNow;
        }

        return new EventRecord
        {
            EventId = eventId,
            Source = source ?? "Unknown",
            Level = level ?? "INFO",
            Message = message ?? "",
            PartitionKey = partitionKey,
            Timestamp = timestamp,
            EnqueuedTimeUtc = eventData.EnqueuedTime.UtcDateTime,
            SequenceNumber = eventData.SequenceNumber
        };
    }
}
