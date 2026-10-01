import Foundation
import XCTest
@testable import ClomniCore

/// Time that moves only when a test says so. With `instant`, every sleep returns at once (and moves the clock).
/// `waits` records every requested sleep, which is how backoff and Retry-After are checked.
final class TestTime: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private let instant: Bool
    private var current = Date(timeIntervalSince1970: 1_790_850_600)
    private var sleepers: [(id: UUID, deadline: Date, continuation: CheckedContinuation<Void, Error>)] = []
    private var _waits: [Double] = []

    init(instant: Bool = false) {
        self.instant = instant
    }

    var waits: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return _waits
    }

    var sleeping: Int {
        lock.lock()
        defer { lock.unlock() }
        return sleepers.count
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func sleep(seconds: Double) async throws {
        if instant {
            pass(seconds)
            try Task.checkCancellation()
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                defer { lock.unlock() }
                guard !Task.isCancelled else { return continuation.resume(throwing: CancellationError()) }
                _waits.append(seconds)
                sleepers.append((id, current.addingTimeInterval(seconds), continuation))
            }
        } onCancel: {
            lock.lock()
            let sleeper = sleepers.first { $0.id == id }
            sleepers.removeAll { $0.id == id }
            lock.unlock()
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    private func pass(_ seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        _waits.append(seconds)
        current += seconds
    }

    func advance(by seconds: Double) {
        lock.lock()
        current += seconds
        let due = sleepers.filter { $0.deadline <= current }
        sleepers.removeAll { $0.deadline <= current }
        lock.unlock()
        due.forEach { $0.continuation.resume() }
    }
}

/// Waits (in real time, briefly) for work running in other tasks to reach a state.
func eventually(_ timeout: Double = 5, _ condition: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    return await condition()
}

/// Fails the test when `condition` does not come true in time.
func expect(_ message: String = "", timeout: Double = 5, file: StaticString = #filePath, line: UInt = #line,
            _ condition: () async -> Bool) async {
    let met = await eventually(timeout, condition)
    XCTAssertTrue(met, message.isEmpty ? "condition not met in time" : message, file: file, line: line)
}

/// Moves test time on in `step`s until `condition` holds, letting other tasks run in between.
func drive(_ time: TestTime, step: Double = 0.5, limit: Int = 400, until condition: () async -> Bool) async -> Bool {
    for _ in 0..<limit {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
        time.advance(by: step)
    }
    return await condition()
}

final class LogLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
    }

    func contains(_ text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return lines.contains { $0.contains(text) }
    }
}
