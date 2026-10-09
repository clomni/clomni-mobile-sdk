import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// One open socket. `receive` throws once the socket is closed, from either side.
protocol WebSocketConnection: Sendable {
    func receive() async throws -> String
    func send(_ text: String) async throws
    func close()
}

protocol WebSocketTransport: Sendable {
    func connect(_ url: URL) -> WebSocketConnection
}

final class URLSessionWebSocketTransport: WebSocketTransport, @unchecked Sendable {
    private let session = URLSession(configuration: .default)

    func connect(_ url: URL) -> WebSocketConnection {
        let task = session.webSocketTask(with: url)
        task.resume()
        return URLSessionWebSocketConnection(task: task)
    }
}

final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            task.receive { result in
                switch result {
                case .success(.string(let text)): continuation.resume(returning: text)
                case .success(.data(let data)): continuation.resume(returning: String(decoding: data, as: UTF8.self))
                case .success: continuation.resume(returning: "")
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    func send(_ text: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.send(.string(text)) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

/// The realtime socket (`ws_url?token=…&protocol=v1`). It reconnects after 1, 2, 4, 8 … 30 s, treats two missed
/// heartbeats as a dead connection, answers the server's `ping` and hands every other frame, parsed, to `handler`.
actor RealtimeClient {
    enum State: Equatable {
        case stopped
        case connecting
        /// `ready` has arrived.
        case connected
        /// Waiting this many seconds before the next attempt.
        case waiting(Double)
    }

    typealias Handler = @Sendable (RealtimeEvent) async -> Void

    static let defaultHeartbeat: Double = 25

    private let transport: WebSocketTransport
    private let time: TimeSource
    /// The socket URL with a fresh token; throws when there is no session.
    private let address: @Sendable () async throws -> URL
    private var handler: Handler?
    private var loop: Task<Void, Never>?
    private var connection: WebSocketConnection?
    private var heartbeat = defaultHeartbeat
    private var lastFrame = Date.distantPast
    private var failures = 0
    /// Bumped by every start and stop, so a loop that was stopped cannot touch its successor's state.
    private var generation = 0
    private(set) var state = State.stopped

    init(transport: WebSocketTransport, time: TimeSource, address: @escaping @Sendable () async throws -> URL) {
        self.transport = transport
        self.time = time
        self.address = address
    }

    func setHandler(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func start() {
        guard loop == nil else { return }
        generation += 1
        let generation = generation
        loop = Task { await self.run(generation) }
    }

    func stop() {
        generation += 1
        loop?.cancel()
        loop = nil
        connection?.close()
        connection = nil
        state = .stopped
    }

    /// The network is back: a socket waiting out its backoff (up to 30 s) connects now.
    func reconnectNow() {
        guard case .waiting = state else { return }
        stop()
        failures = 0
        start()
    }

    /// 1, 2, 4, 8, 16, 30, 30 … seconds.
    static func delay(afterFailures failures: Int) -> Double {
        min(30, pow(2, Double(min(failures, 5))))
    }

    private func run(_ generation: Int) async {
        while !Task.isCancelled {
            var opened: WebSocketConnection?
            do {
                state = .connecting
                let url = try await address()
                guard generation == self.generation else { return }
                let connection = transport.connect(url)
                opened = connection
                self.connection = connection
                lastFrame = time.now()
                try await receive(from: connection)
            } catch {
                if !Task.isCancelled { ClomniLog.debug("socket closed: \(error)") }
            }
            opened?.close()
            guard !Task.isCancelled, generation == self.generation else { return }
            connection = nil
            let delay = Self.delay(afterFailures: failures)
            failures += 1
            state = .waiting(delay)
            try? await time.sleep(seconds: delay)
        }
    }

    private func receive(from connection: WebSocketConnection) async throws {
        let watchdog = Task { await self.watch(connection) }
        defer { watchdog.cancel() }
        while !Task.isCancelled {
            let text = try await connection.receive()
            await handle(text, from: connection)
        }
    }

    /// Closes a connection that has been silent for two heartbeats; `receive` then throws and the loop reconnects.
    private func watch(_ connection: WebSocketConnection) async {
        while !Task.isCancelled {
            try? await time.sleep(seconds: heartbeat)
            guard !Task.isCancelled else { return }
            if time.now().timeIntervalSince(lastFrame) >= 2 * heartbeat {
                ClomniLog.info("no frame for \(Int(2 * heartbeat)) s; reconnecting")
                connection.close()
                return
            }
        }
    }

    private func handle(_ text: String, from connection: WebSocketConnection) async {
        lastFrame = time.now()
        guard let json = ProtocolJSON.decode(Data(text.utf8)) else {
            return ClomniLog.warning("socket frame is not JSON, ignored")
        }
        switch json["event"]?.stringValue {
        case "ping":
            let pong: JSONValue = ["event": "pong", "ts": .string(time.now().formatted(.iso8601))]
            try? await connection.send(String(decoding: ProtocolJSON.encode(pong), as: UTF8.self))
            return
        case "pong":
            return
        default:
            break
        }
        guard let event = ProtocolJSON.parseEvent(json) else { return }
        if case .ready(_, let heartbeatSec) = event.data {
            heartbeat = Double(max(1, heartbeatSec))
            failures = 0
            state = .connected
        }
        await handler?(event)
    }
}
