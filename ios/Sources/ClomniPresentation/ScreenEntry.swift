import Foundation

/// How a screen comes into view, a tab or a push (CM-346 § 5.1, TestFlight #21): the old screen is gone at once and the
/// new one shows only its own background with the spinner in its middle, for at least `minimum` and until its data is
/// there; then its content fades in over `fadeIn` (at once with Reduce Motion). Also when the data is cached: the
/// operator wants this short loading every time, not two screens showing through each other in a cross-fade. A tab
/// keeps its content behind the spinner, so it comes back loaded and scrolled as it was left.
@MainActor
package final class ScreenEntry {
    package nonisolated static let minimum: TimeInterval = 0.35
    package nonisolated static let fadeIn: TimeInterval = 0.15

    /// The minimum has passed since the screen came into view.
    package private(set) var waited = false
    /// Called when `waited` changed.
    package var onChange: (() -> Void)?
    /// The wait now running, for tests to await.
    package private(set) var waiting: Task<Void, Never>?

    private let seconds: TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    /// Starts at once: a screen's entry is made as it comes into view.
    package init(minimum: TimeInterval = ScreenEntry.minimum,
                 sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
                     try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                 }) {
        seconds = minimum
        self.sleep = sleep
        start()
    }

    /// The screen came into view again (its tab chosen): the spinner, and the wait starts over.
    package func start() {
        waiting?.cancel()
        if waited {
            waited = false
            onChange?()
        }
        let (sleep, seconds) = (sleep, seconds)
        waiting = Task { [weak self] in
            do {
                try await sleep(seconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            waited = true
            onChange?()
        }
    }

    /// The content shows once the minimum has passed and its data (`ready`) is there; the spinner until then.
    package func showsContent(ready: Bool) -> Bool {
        waited && ready
    }
}
