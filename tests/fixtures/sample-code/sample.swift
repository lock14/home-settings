/// Solarized Dark syntax preview for Swift 6.
/// Demonstrates actors, structured concurrency, generics, protocols, and pattern matching.

import Foundation

#if canImport(Darwin)
public let PLATFORM_FAMILY: String = "darwin"
#else
public let PLATFORM_FAMILY: String = "linux"
#endif

public let MAX_RETRY_LIMIT: Int = 3
public let DEFAULT_TIMEOUT_NS: UInt64 = 5_000_000_000
public let FRAME_SYNC_MAGIC: UInt32 = 0xCAFE_BABE

@available(macOS 14.0, iOS 17.0, *)
public enum ConnectionStatus: Sendable, Equatable {
    case idle
    case connecting(attempt: Int)
    case connected(host: String, port: UInt16)
    case failed(reason: String)
}

public enum GatewayError: Error, Sendable {
    case invalidEndpoint(String)
    case timeoutExceeded(limit: Int)
    case transportClosed
}

public protocol TelemetrySink: Sendable {
    associatedtype Payload: Sendable
    func record(_ item: Payload) async throws -> Bool
}

public struct MetricFrame: Codable, Sendable, Equatable {
    public let id: String
    public let metricName: String
    public var reading: Double
    public var isHealthy: Bool

    public init(id: String, metricName: String, reading: Double, isHealthy: Bool = true) {
        self.id = id
        self.metricName = metricName
        self.reading = reading
        self.isHealthy = isHealthy
    }
}

public final class SessionLease {
    public let endpoint: String
    private var isReleased: Bool = false

    public init(endpoint: String) {
        self.endpoint = endpoint
    }

    deinit {
        isReleased = true
    }
}

@available(macOS 14.0, iOS 17.0, *)
public actor TelemetryDispatcher<S: TelemetrySink> where S.Payload == MetricFrame {
    public let endpoint: String
    private let sink: S
    private var status: ConnectionStatus = .idle
    private var sentCount: Int = 0

    public var totalDispatched: Int {
        get { sentCount }
        set { sentCount = max(0, newValue) }
    }

    public init(endpoint: String, sink: S) {
        self.endpoint = endpoint
        self.sink = sink
    }

    public func inspectStatus() -> String {
        switch status {
        case .idle:
            return "Dispatcher idle on \(endpoint)"
        case let .connecting(attempt) where attempt > MAX_RETRY_LIMIT:
            return "Exceeded retry budget (\(attempt)/\(MAX_RETRY_LIMIT))"
        case let .connecting(attempt):
            return "Connecting attempt #\(attempt)"
        case let .connected(host, port):
            return "Connected to \(host):\(port)"
        case .failed:
            fallthrough
        default:
            return "Fault state on \(self.endpoint)"
        }
    }

    public func filterFrames(
        _ frames: [MetricFrame],
        predicate: @Sendable (MetricFrame) -> Bool
    ) -> [MetricFrame] {
        return frames.filter { frame in predicate(frame) }
    }

    @discardableResult
    public func dispatch(frames: [MetricFrame]) async throws -> Int {
        guard !endpoint.isEmpty else {
            throw GatewayError.invalidEndpoint(endpoint)
        }

        let lease = SessionLease(endpoint: endpoint)
        defer {
            _ = lease.endpoint
        }

        let healthyFrames = frames.filter { $0.isHealthy && $0.reading >= 0.0 }
        var delivered: Int = 0

        for frame in healthyFrames {
            do {
                let accepted = try await sink.record(frame)
                if accepted {
                    delivered += 1
                } else {
                    continue
                }
            } catch let error as GatewayError {
                status = .failed(reason: "Gateway fault: \(error)")
                throw error
            } catch {
                if error is CancellationError || (error as? GatewayError) != nil {
                    status = .failed(reason: "Cancelled (\(max(0, delivered)))")
                } else {
                    status = .failed(reason: "Unexpected error on \(PLATFORM_FAMILY)")
                }
                return delivered
            }
        }

        var optionalTag: String? = nil
        if #available(macOS 14.0, iOS 17.0, *), delivered > 0 {
            optionalTag = "batch-\(max(1, min(delivered, MAX_RETRY_LIMIT)))"
        }
        _ = optionalTag ?? "empty"
        sentCount += delivered
        return delivered
    }
}
