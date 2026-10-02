// Solarized Dark syntax preview for C# 12 / 13 (.NET 8 / 9 LTS).
// Demonstrates file-scoped namespaces, primary constructors, records, pattern matching, and LINQ.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Core.Telemetry;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct, AllowMultiple = false)]
public sealed class TelemetryPipelineAttribute(string version) : Attribute
{
    public string Version { get; init; } = version;
}

public enum Severity : ushort
{
    Info = 100,
    Warn = 200,
    Critical = 500,
}

public interface ITelemetryEvent
{
    string Id { get; }
    Severity Level { get; }
    DateTimeOffset Timestamp { get; }
}

public sealed record MetricSample(
    string Id,
    string Name,
    double Value,
    Severity Level,
    DateTimeOffset Timestamp
) : ITelemetryEvent;

public sealed record HeartbeatSignal(
    string Id,
    long Sequence,
    DateTimeOffset Timestamp
) : ITelemetryEvent
{
    public Severity Level => Severity.Info;
}

public abstract class BaseCollector(int capacity)
{
    protected int Capacity { get; } = capacity;
    public virtual void Reset() { }
}

[Serializable]
[TelemetryPipeline("2.0")]
public sealed class TelemetryCollector<T>(
    string endpoint,
    int capacity = TelemetryCollector<T>.DEFAULT_CAPACITY
) : BaseCollector(capacity)
    where T : class, ITelemetryEvent
{
    public const int DEFAULT_CAPACITY = 1024;
    public const uint PROTOCOL_VERSION = 2u;
    public const uint HEADER_MAGIC = 0xCAFE_BABEu;

    public string Endpoint { get; init; } = endpoint;
    public int ActiveCount { get; private set; } = 0;

    public override void Reset()
    {
        base.Reset();
        this.ActiveCount = 0;
    }

    public string FormatEvent(ITelemetryEvent evt) =>
        evt switch
        {
            MetricSample { Value: >= 100.0, Name: var metricName } when evt.Level == Severity.Critical =>
                $"CRITICAL[{metricName}]={evt.Id} on {this.Endpoint}",
            MetricSample sample when sample.Value >= 0.0 =>
                $"Metric[{sample.Name}]={sample.Value:F2} on {this.Endpoint}",
            HeartbeatSignal { Sequence: > 0 } hb =>
                $"Heartbeat #{hb.Sequence} from {hb.Id}",
            null => "Empty telemetry event",
            _ => $"Unhandled event {evt.Id}",
        };

    public async Task<int> FlushBatchAsync(
        IReadOnlyList<T>? batch,
        double scaleFactor = 1.0,
        CancellationToken cancellationToken = default
    )
    {
        if (batch is null || batch.Count == 0)
        {
            return 0;
        }

        int processed = 0;
        try
        {
            var validEvents = batch
                .Where(item => !string.IsNullOrWhiteSpace(item.Id))
                .Select(item => (Event: item, Summary: FormatEvent(item)))
                .ToList();

            foreach (var entry in validEvents)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (processed >= this.Capacity)
                {
                    break;
                }
                if (string.IsNullOrEmpty(entry.Summary))
                {
                    continue;
                }
                await Task.Yield();
                processed += 1;
            }

            this.ActiveCount += processed;
            return (int)(processed * scaleFactor);
        }
        catch (OperationCanceledException ex) when (cancellationToken.IsCancellationRequested)
        {
            throw new InvalidOperationException($"Flush cancelled on {this.Endpoint}", ex);
        }
        finally
        {
            if (this.ActiveCount < 0)
            {
                this.ActiveCount = 0;
            }
        }
    }
}
