import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore

final class RealtimeTests: XCTestCase {
    private let socket = FakeSocket()
    private let time = TestTime()
    private let received = Received()
    private var realtime: RealtimeClient!
    private let address = URL(string: "wss://app.clomni.ai/v1/realtime?token=st_1&protocol=v1")!

    final class Received: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [RealtimeEvent] = []

        func append(_ event: RealtimeEvent) {
            lock.lock()
            defer { lock.unlock() }
            events.append(event)
        }

        var names: [String] {
            lock.lock()
            defer { lock.unlock() }
            return events.map(\.event)
        }
    }

    override func setUp() async throws {
        let address = address
        realtime = RealtimeClient(transport: socket, time: time, address: { address })
        let received = received
        await realtime.setHandler { received.append($0) }
    }

    override func tearDown() async throws {
        await realtime.stop()
    }

    private func waitForConnection(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        let opened = await eventually { self.socket.connections.count >= count }
        XCTAssertTrue(opened, "expected \(count) connections, have \(socket.connections.count)", file: file, line: line)
    }

    /// Waits until the client sits in its reconnect wait (the heartbeat watch is gone by then) and returns the delay.
    private func backoff(file: StaticString = #filePath, line: UInt = #line) async -> Double? {
        var delay: Double?
        let waiting = await eventually {
            guard case .waiting(let seconds) = await self.realtime.state, self.time.sleeping == 1 else { return false }
            delay = seconds
            return true
        }
        XCTAssertTrue(waiting, "expected a reconnect wait", file: file, line: line)
        return delay
    }

    func testFramesReachTheHandlerInOrder() async throws {
        await realtime.start()
        await waitForConnection(1)
        XCTAssertEqual(socket.urls, [address])
        socket.ready()
        socket.push(String(decoding: try Data(contentsOf: fixture("34-event-message-created.json")), as: UTF8.self))
        socket.push(String(decoding: try Data(contentsOf: fixture("41-event-unknown.json")), as: UTF8.self))
        socket.push("not json")
        await expect { self.received.names.count == 3 }
        XCTAssertEqual(received.names, ["ready", "message.created", "conversation.rated"])
        let state = await realtime.state
        XCTAssertEqual(state, .connected)
    }

    func testReconnectsAfter1248Upto30Seconds() async throws {
        await realtime.start()
        var delays: [Double?] = []
        for attempt in 1...8 {
            await waitForConnection(attempt)
            socket.connections[attempt - 1].close()
            delays.append(await backoff())
            time.advance(by: 30)
        }
        await waitForConnection(9)
        XCTAssertEqual(delays, [1, 2, 4, 8, 16, 30, 30, 30])
        XCTAssertEqual(socket.urls.count, 9)
    }

    /// CM-087: the network is back while the socket waits out a long backoff: it connects now, and the next wait
    /// starts again from 1 s.
    func testTheNetworkComingBackReconnectsAtOnce() async throws {
        await realtime.start()
        for attempt in 1...4 {
            await waitForConnection(attempt)
            socket.connections[attempt - 1].close()
            _ = await backoff()
            if attempt < 4 { time.advance(by: 30) }
        }
        let long = await realtime.state
        XCTAssertEqual(long, .waiting(8))
        await realtime.reconnectNow()
        await waitForConnection(5)
        socket.connections[4].close()
        let next = await backoff()
        XCTAssertEqual(next, 1, "the backoff starts over")
        // Connected or connecting, there is nothing to hurry.
        time.advance(by: 1)
        await waitForConnection(6)
        await realtime.reconnectNow()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(socket.connections.count, 6)
    }

    func testReadyResetsTheBackoff() async throws {
        await realtime.start()
        await waitForConnection(1)
        socket.connections[0].close()
        let first = await backoff()
        XCTAssertEqual(first, 1)
        time.advance(by: 1)
        await waitForConnection(2)
        socket.connections[1].close()
        let second = await backoff()
        XCTAssertEqual(second, 2)
        time.advance(by: 2)
        await waitForConnection(3)
        socket.ready()
        await expect { self.received.names == ["ready"] }
        socket.connections[2].close()
        let afterReady = await backoff()
        XCTAssertEqual(afterReady, 1, "a connection that got ready starts the backoff over")
    }

    func testTwoMissedHeartbeatsReconnect() async throws {
        await realtime.start()
        await waitForConnection(1)
        socket.ready(heartbeat: 20)
        await expect { self.received.names == ["ready"] }
        await expect { self.time.sleeping == 1 }
        // The watch started before `ready` with the default 25 s; 25 s of silence is under two of the server's 20 s.
        time.advance(by: 25)
        await expect { self.time.sleeping == 1 }
        XCTAssertFalse(socket.connections[0].isClosed, "one quiet heartbeat is fine")
        time.advance(by: 20)
        await expect("two are not") { self.socket.connections[0].isClosed }
        let delay = await backoff()
        XCTAssertEqual(delay, 1)
        time.advance(by: 1)
        await waitForConnection(2)
    }

    func testFramesKeepTheConnectionAlive() async throws {
        await realtime.start()
        await waitForConnection(1)
        for round in 1...4 {
            await expect { self.time.sleeping == 1 }
            socket.push(FakeServer.frame("unread.changed", ["total": 1]))
            await expect { self.received.names.count == round }
            time.advance(by: 25)
        }
        XCTAssertFalse(socket.connections[0].isClosed)
        XCTAssertEqual(socket.connections.count, 1)
    }

    func testPingIsAnsweredWithPong() async throws {
        await realtime.start()
        await waitForConnection(1)
        socket.push(#"{"event":"ping","ts":"2026-10-01T10:30:01Z"}"#)
        socket.push(#"{"event":"pong","ts":"2026-10-01T10:30:01Z"}"#)
        await expect { !self.socket.connections[0].sent.isEmpty }
        let pong = try XCTUnwrap(ProtocolJSON.decode(Data(socket.connections[0].sent[0].utf8)))
        XCTAssertEqual(pong["event"], "pong")
        XCTAssertNotNil(pong["ts"]?.stringValue)
        XCTAssertTrue(received.names.isEmpty)
    }

    func testStopClosesAndStaysClosed() async throws {
        await realtime.start()
        await realtime.start()
        await waitForConnection(1)
        await realtime.stop()
        XCTAssertTrue(socket.connections[0].isClosed)
        time.advance(by: 60)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(socket.connections.count, 1)
        let state = await realtime.state
        XCTAssertEqual(state, .stopped)
        await realtime.start()
        await waitForConnection(2)
    }

    func testNoSessionWaitsAndTriesAgain() async throws {
        let attempts = Counter()
        let address = address
        let realtime = RealtimeClient(transport: socket, time: time, address: {
            if attempts.next() == 1 { throw ClomniError.notLoggedIn }
            return address
        })
        await realtime.start()
        await expect { self.time.sleeping == 1 }
        let state = await realtime.state
        XCTAssertEqual(state, .waiting(1))
        XCTAssertTrue(socket.connections.isEmpty)
        time.advance(by: 1)
        await waitForConnection(1)
        await realtime.stop()
    }

    func testDelays() {
        XCTAssertEqual((0..<8).map(RealtimeClient.delay), [1, 2, 4, 8, 16, 30, 30, 30])
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("protocol/fixtures/\(name)")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
