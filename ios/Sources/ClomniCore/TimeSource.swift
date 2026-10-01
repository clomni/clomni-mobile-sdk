import Foundation

/// The clock and the waits (retry backoff, reconnect, heartbeat); tests replace it to control time.
protocol TimeSource: Sendable {
    func now() -> Date
    func sleep(seconds: Double) async throws
}

struct SystemTime: TimeSource {
    func now() -> Date { Date() }

    func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}
