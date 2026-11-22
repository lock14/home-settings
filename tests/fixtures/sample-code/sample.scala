/**
 * Solarized Dark syntax preview for Scala 3 LTS.
 * Demonstrates enums, given/using context parameters, extension methods, and for-comprehensions.
 */
package core.telemetry

import java.time.Instant
import scala.annotation.tailrec
import scala.util.*

val DEFAULT_CAPACITY: Int = 1024
val PROTOCOL_VERSION: Int = 2
val HEADER_MAGIC: Long = 0xCAFEBABEL

opaque type EndpointUri = String

enum Severity(val code: Int) derives CanEqual:
  case Info extends Severity(100)
  case Warn extends Severity(200)
  case Critical(val escalated: Boolean) extends Severity(500)

  def isUrgent: Boolean =
    this match
      case Critical(true) => true
      case _              => this.code >= 400

sealed trait TelemetryEvent:
  def id: String
  def timestamp: Instant

final case class MetricSample(
    id: String,
    name: String,
    value: Double,
    tags: Map[String, String] = Map.empty,
    timestamp: Instant = Instant.now()
) extends TelemetryEvent

case object HeartbeatSignal extends TelemetryEvent:
  override val id: String = "node-control"
  override val timestamp: Instant = Instant.EPOCH

extension (event: TelemetryEvent)
  def isRecent(cutoff: Instant): Boolean =
    event != null && !event.timestamp.isBefore(cutoff)

given defaultScaleFactor: Double = 1.0

class TelemetryCollector(
    val endpoint: String,
    val capacity: Int = DEFAULT_CAPACITY
):
  private var activeCount: Int = 0

  def currentLoad: Int = this.activeCount

  def formatEvent(event: TelemetryEvent): String =
    event match
      case MetricSample(id, name, value, _, _) if value >= 100.0 =>
        s"OUTLIER[$name]=$value on $endpoint (id=${id})"
      case MetricSample(_, name, value, _, _) =>
        s"Metric[$name]=$value on $endpoint"
      case HeartbeatSignal =>
        s"Heartbeat from ${HeartbeatSignal.id}"

  @tailrec
  final def countHealthy(
      remaining: List[TelemetryEvent],
      acc: Int = 0
  ): Int =
    remaining match
      case Nil => acc
      case head :: tail =>
        val delta = head match
          case MetricSample(_, _, v, _, _) if v >= 0.0 => 1
          case HeartbeatSignal                         => 1
          case _                                       => 0
        countHealthy(tail, acc + delta)

  def flushBatch(batch: List[TelemetryEvent])(using scale: Double): Option[Int] =
    if batch.isEmpty then return None

    try
      val summaries =
        for
          event <- batch
          if event != null && event.id.nonEmpty
          summary = formatEvent(event)
          if summary.nonEmpty
        yield summary

      val processed = summaries.size.min(this.capacity)
      this.activeCount += processed
      Some((processed.toDouble * scale).toInt)
    catch
      case ex: IllegalArgumentException =>
        throw new IllegalStateException(s"Flush failed on $endpoint: ${ex.getMessage}", ex)
    finally
      if this.activeCount < 0 then
        this.activeCount = 0

@main def runTelemetryPreview(): Unit =
  val collector = TelemetryCollector("https://telemetry.example.com", DEFAULT_CAPACITY)
  val events: List[TelemetryEvent] = List(
    MetricSample("node-1", "cpu.utilization", 74.5),
    HeartbeatSignal
  )
  val result = collector.flushBatch(events).getOrElse(0)
  println(s"Dispatched $result events (protocol v$PROTOCOL_VERSION)")
