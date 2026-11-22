/**
 * Solarized Dark syntax preview for Kotlin (2.x).
 * Demonstrates value classes, sealed hierarchies, coroutines, extensions, and smart casts.
 */
@file:JvmName("TelemetryPipelineKt")

package core.telemetry

import java.time.Instant
import kotlin.math.max
import kotlinx.coroutines.*

@JvmInline
value class NodeId(val raw: String) {
    init {
        require(raw.isNotBlank()) { "NodeId must not be blank" }
    }
}

enum class Severity(val code: Int) {
    INFO(100),
    WARN(200),
    CRITICAL(500);

    fun isUrgent(): Boolean = this == CRITICAL || code >= 400
}

sealed interface TelemetryEvent {
    val id: NodeId
    val timestamp: Instant
}

data class MetricSample(
    override val id: NodeId,
    val name: String,
    val value: Double,
    val tags: Map<String, String> = emptyMap(),
    override val timestamp: Instant = Instant.now(),
) : TelemetryEvent

data object HeartbeatSignal : TelemetryEvent {
    override val id: NodeId = NodeId("node-control")
    override val timestamp: Instant = Instant.EPOCH
}

abstract class BaseCollector(protected val capacity: Int) {
    open fun reset() {}
}

class TelemetryCollector<T : TelemetryEvent>(
    private val endpoint: String,
    capacity: Int = DEFAULT_CAPACITY,
) : BaseCollector(capacity) where T : Any {

    companion object {
        const val DEFAULT_CAPACITY: Int = 1024
        const val PROTOCOL_VERSION: UInt = 2u
        const val FLUSH_TIMEOUT_MS: Long = 5_000L
        const val HEADER_MAGIC: UInt = 0xCAFE_BABEu
    }

    var activeCount: Int = 0
        get() = field
        private set(value) {
            field = max(0, value)
        }

    constructor(endpoint: String) : this(endpoint, DEFAULT_CAPACITY)

    override fun reset() {
        super.reset()
        this.activeCount = 0
    }

    fun formatEvent(event: TelemetryEvent): String =
        when (event) {
            is MetricSample -> {
                val status = if (event.value in 0.0..100.0) "NORMAL" else "OUTLIER"
                "Metric[${event.name}]=${event.value} ($status) on $endpoint"
            }
            is HeartbeatSignal -> "Heartbeat from ${event.id.raw.takeIf { it.isNotBlank() } ?: "unknown"}"
        }

    suspend fun flushBatch(batch: List<T>, scaleFactor: Float = 1.0f): Int {
        if (batch.isEmpty()) return 0

        var processed = 0
        try {
            val validEvents = batch.filter { it.id.raw.isNotEmpty() }
            batchLoop@ for (item in validEvents) {
                if (processed >= capacity) break@batchLoop
                val summary = formatEvent(item)
                if (summary.isEmpty()) continue@batchLoop
                processed += 1
            }
            activeCount += processed
            return (processed * scaleFactor).toInt()
        } catch (ex: IllegalArgumentException) {
            val detail: String? = ex.message
            throw IllegalStateException("Flush failed on $endpoint: ${detail ?: "unknown"}", ex)
        } finally {
            if (activeCount < 0) {
                activeCount = 0
            }
        }
    }
}

fun TelemetryEvent.isRecent(cutoff: Instant): Boolean =
    this !is HeartbeatSignal &&
        (this as? MetricSample)?.value !in -1.0..0.0 &&
        !this.timestamp.isBefore(cutoff)
