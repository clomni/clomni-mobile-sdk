import Foundation

/// When the loading indicator shows (DESIGN-PASS 5): only once loading has lasted 300 ms, so a quick load does not
/// flash it; once shown, for at least 400 ms, so it does not blink away. Time is measured by `sleep`, which tests
/// replace with a clock of their own.
@MainActor
package final class SpinnerTiming {
    package static let delay: TimeInterval = 0.3
    package static let minimum: TimeInterval = 0.4

    package private(set) var visible = false
    /// Called when `visible` changed.
    package var onChange: (() -> Void)?
    /// The wait now running (to show it, or to let it go), for tests to await.
    package private(set) var waiting: Task<Void, Never>?

    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var loading = false
    private var minimumPassed = false

    package init(sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }) {
        self.sleep = sleep
    }

    package func set(loading: Bool) {
        guard loading != self.loading else { return }
        self.loading = loading
        if loading {
            // Already showing: it stays. Otherwise it shows after the delay, if still loading then.
            guard !visible else { return }
            wait(Self.delay) { timing in
                guard timing.loading else { return }
                timing.show()
            }
        } else if !visible {
            // Done before the delay: nothing was shown, nothing will be.
            waiting?.cancel()
            waiting = nil
        } else if minimumPassed {
            hide()
        }
        // Else the minimum's wait hides it when it ends.
    }

    private func show() {
        visible = true
        minimumPassed = false
        onChange?()
        wait(Self.minimum) { timing in
            timing.minimumPassed = true
            if !timing.loading { timing.hide() }
        }
    }

    private func hide() {
        visible = false
        onChange?()
    }

    private func wait(_ seconds: TimeInterval, then: @escaping @MainActor (SpinnerTiming) -> Void) {
        waiting?.cancel()
        let sleep = sleep
        waiting = Task { [weak self] in
            do {
                try await sleep(seconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            then(self)
        }
    }
}
