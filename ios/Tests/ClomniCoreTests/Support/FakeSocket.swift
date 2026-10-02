import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ClomniProtocol
@testable import ClomniCore

/// Hands out fake connections and remembers the URLs they were opened with.
final class FakeSocket: WebSocketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var opened: [(url: URL, connection: FakeConnection)] = []

    func connect(_ url: URL) -> WebSocketConnection {
        let connection = FakeConnection()
        lock.lock()
        opened.append((url, connection))
        lock.unlock()
        return connection
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return opened.map(\.url)
    }

    var connections: [FakeConnection] {
        lock.lock()
        defer { lock.unlock() }
        return opened.map(\.connection)
    }

    /// The newest connection, if it is still open.
    var live: FakeConnection? {
        connections.last.flatMap { $0.isClosed ? nil : $0 }
    }

    /// Puts a frame on the open connection; dropped when there is none (like a real server's).
    func push(_ frame: String) {
        live?.push(frame)
    }

    func ready(heartbeat: Int = 25) {
        push(FakeServer.frame("ready", ["user_id": "usr_1", "heartbeat_sec": .number(Double(heartbeat))]))
    }
}

final class FakeConnection: WebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private let frames: AsyncThrowingStream<String, Error>
    private let input: AsyncThrowingStream<String, Error>.Continuation
    private var iterator: AsyncThrowingStream<String, Error>.AsyncIterator
    private var _sent: [String] = []
    private var _closed = false

    init() {
        var input: AsyncThrowingStream<String, Error>.Continuation!
        frames = AsyncThrowingStream { input = $0 }
        self.input = input
        iterator = frames.makeAsyncIterator()
    }

    var sent: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _sent
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _closed
    }

    func push(_ frame: String) {
        input.yield(frame)
    }

    func receive() async throws -> String {
        guard let frame = try await iterator.next() else { throw URLError(.networkConnectionLost) }
        return frame
    }

    func send(_ text: String) async throws {
        record(text)
    }

    private func record(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        _sent.append(text)
    }

    func close() {
        lock.lock()
        _closed = true
        lock.unlock()
        input.finish(throwing: URLError(.networkConnectionLost))
    }
}
