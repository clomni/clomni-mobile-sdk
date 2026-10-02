import Foundation
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif

/// The engine's changes for one screen: handled on the main actor one at a time, in the order they came. `settled`
/// waits until everything submitted so far is handled, so a test knows when to look instead of guessing a delay.
package final class ChangeQueue: Sendable {
    private struct State {
        var queued: [ClomniChange] = []
        var draining = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Locked(State())
    private let handle: @MainActor @Sendable (ClomniChange) async -> Void

    package init(_ handle: @escaping @MainActor @Sendable (ClomniChange) async -> Void) {
        self.handle = handle
    }

    /// From any thread (the engine's observers run on its actor).
    package func submit(_ change: ClomniChange) {
        let start = state.write { state -> Bool in
            state.queued.append(change)
            defer { state.draining = true }
            return !state.draining
        }
        if start {
            Task { @MainActor in await self.drain() }
        }
    }

    package func settled() async {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let idle = state.write { state -> Bool in
                if !state.draining { return true }
                state.waiters.append(waiter)
                return false
            }
            if idle { waiter.resume() }
        }
    }

    @MainActor
    private func drain() async {
        while let change = next() {
            await handle(change)
        }
    }

    private func next() -> ClomniChange? {
        let (change, done) = state.write { state -> (ClomniChange?, [CheckedContinuation<Void, Never>]) in
            guard !state.queued.isEmpty else {
                state.draining = false
                defer { state.waiters = [] }
                return (nil, state.waiters)
            }
            return (state.queued.removeFirst(), [])
        }
        done.forEach { $0.resume() }
        return change
    }
}
