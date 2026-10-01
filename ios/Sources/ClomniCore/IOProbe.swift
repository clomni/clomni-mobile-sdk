import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// Notes on which thread the SDK reads and writes the disk and the keychain, for the test that keeps `initialize` off
/// them on the main thread. Records nothing unless a test starts it.
enum IOProbe {
    struct Access: Equatable, Sendable {
        let what: String
        let onMainThread: Bool
    }

    private static let accesses = Locked<[Access]?>(nil)

    static func start() {
        accesses.write { $0 = [] }
    }

    /// What was recorded since `start`; recording stops.
    static func stop() -> [Access] {
        accesses.write { recorded in
            defer { recorded = nil }
            return recorded ?? []
        }
    }

    static func note(_ what: @autoclosure () -> String) {
        accesses.write { recorded in
            guard recorded != nil else { return }
            recorded?.append(Access(what: what(), onMainThread: Thread.isMainThread))
        }
    }
}
