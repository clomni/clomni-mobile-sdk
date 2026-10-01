import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore

/// One phone: an engine with its own Keychain, cache directory and socket, talking to the shared fake server.
final class Device {
    let socket = FakeSocket()
    let vault: MemorySecureStore
    let cache: DiskCache
    let engine: ClomniEngine
    let changes = Changes()

    init(_ server: FakeServer, time: TestTime, cache: DiskCache? = nil, vault: MemorySecureStore? = nil) async {
        self.vault = vault ?? MemorySecureStore()
        self.cache = cache ?? DiskCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("clomni-test-\(UUID().uuidString)"))
        engine = ClomniEngine(configuration: ApiConfiguration(appId: FakeServer.appId, apiKey: FakeServer.apiKey),
                              transport: server, socket: socket, vault: self.vault, cache: self.cache, time: time)
        let changes = changes
        await engine.observe { changes.append($0) }
    }

    /// Opens the socket and lets the server say `ready`.
    func online(file: StaticString = #filePath, line: UInt = #line) async {
        let connections = socket.connections.count
        await engine.connect()
        await expect("socket opens", file: file, line: line) { self.socket.connections.count > connections }
        socket.ready()
    }

    func messages(_ conversationId: String) async -> [Message] {
        await engine.messages(in: conversationId)
    }

    func pending(_ conversationId: String) async -> [PendingMessage] {
        await engine.pending(in: conversationId)
    }
}

/// Every server frame goes to every device's open socket.
final class SocketHub: @unchecked Sendable {
    private let lock = NSLock()
    private var sockets: [FakeSocket] = []

    func add(_ socket: FakeSocket) {
        lock.lock()
        defer { lock.unlock() }
        sockets.append(socket)
    }

    func push(_ frame: String) {
        lock.lock()
        let sockets = sockets
        lock.unlock()
        sockets.forEach { $0.push(frame) }
    }
}

final class Changes: @unchecked Sendable {
    private let lock = NSLock()
    private var changes: [ClomniChange] = []

    func append(_ change: ClomniChange) {
        lock.lock()
        defer { lock.unlock() }
        changes.append(change)
    }

    var all: [ClomniChange] {
        lock.lock()
        defer { lock.unlock() }
        return changes
    }
}
