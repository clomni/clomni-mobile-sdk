import Foundation

/// What the microphone button is doing, WhatsApp's way. Held, it records; let go, it sends. Slid left past
/// `cancelDistance` it throws the recording away; slid up past `lockDistance` it locks, and the hand can go: then
/// Stop, Delete and Send, and after Stop the recording can be heard before it goes. A press shorter than `minMs` sends
/// nothing and asks to hold ("Yazmaq üçün basıb saxlayın"). At `maxMs` (the config's voice_seconds) it stops by itself
/// and waits for Send or Delete.
///
/// Only the rules: the view feeds it touches and the recorder's ticks and carries out what it answers (`Effect`). The
/// same machine as the Android SDK's VoiceRecording.
package struct VoiceRecording: Sendable {
    package enum State: Sendable, Equatable {
        case idle
        /// The finger is down: `cancel` and `lock` are how far it has gone towards each, 0–1.
        case holding(elapsedMs: Int, cancel: Double, lock: Double)
        /// Recording with no hand on the button: Stop, Delete, Send.
        case locked(elapsedMs: Int)
        /// Stopped: heard before it goes, or deleted.
        case review(durationMs: Int)
    }

    package enum Effect: Sendable, Equatable {
        /// Start the microphone (and the light haptic tick).
        case start
        /// Stop the microphone if it runs, and send the recording with `waveform`.
        case send(waveform: [Int])
        /// Stop the microphone and keep the recording for listening.
        case stop
        /// Stop the microphone if it runs and delete the recording; `animated`: the microphone falls into the bin.
        case discard(animated: Bool)
        /// The press was too short: "Yazmaq üçün basıb saxlayın".
        case holdHint
        /// The lock closed: a haptic tick, and VoiceOver says "Yazma kilidləndi".
        case locked
        /// The first press: ask for the microphone; the next press records.
        case askPermission
        /// Refused for good: say why nothing happens, with the way to the settings.
        case permissionDenied
    }

    package enum Permission: Sendable, Equatable {
        case granted, undecided, denied
    }

    /// Shorter is a slip of the finger, not a message.
    package static let minMs = 700
    /// How far left (pt) cancels.
    package static let cancelDistance = 120.0
    /// How far up (pt) locks.
    package static let lockDistance = 90.0

    package private(set) var state: State = .idle
    /// The loudness so far, 0–1 a tick: the live waveform, and the message's once it goes.
    package private(set) var levels: [Double] = []
    private let maxMs: Int

    package init(maxMs: Int) {
        self.maxMs = maxMs
    }

    package var isActive: Bool { state != .idle }

    /// The finger went down on the microphone.
    package mutating func press(_ permission: Permission) -> [Effect] {
        guard state == .idle else { return [] }
        switch permission {
        case .granted:
            levels = []
            state = .holding(elapsedMs: 0, cancel: 0, lock: 0)
            return [.start]
        case .undecided: return [.askPermission]
        case .denied: return [.permissionDenied]
        }
    }

    /// VoiceOver's double tap: there is no holding with it, so it records locked, with Stop, Delete and Send.
    package mutating func pressLocked(_ permission: Permission) -> [Effect] {
        let effects = press(permission)
        if case .holding = state { state = .locked(elapsedMs: 0) }
        return effects
    }

    /// The finger moved `dx`, `dy` points from where it went down; left and up are negative.
    package mutating func drag(dx: Double, dy: Double) -> [Effect] {
        guard case .holding(let elapsed, _, _) = state else { return [] }
        let cancel = min(1, max(0, -dx / Self.cancelDistance))
        let lock = min(1, max(0, -dy / Self.lockDistance))
        if cancel >= 1 {
            state = .idle
            return [.discard(animated: true)]
        }
        if lock >= 1 {
            state = .locked(elapsedMs: elapsed)
            return [.locked]
        }
        state = .holding(elapsedMs: elapsed, cancel: cancel, lock: lock)
        return []
    }

    /// The finger came up: sent, or too short to be a message.
    package mutating func release() -> [Effect] {
        guard case .holding(let elapsed, _, _) = state else { return [] }
        state = .idle
        return elapsed < Self.minMs ? [.discard(animated: false), .holdHint] : [.send(waveform: waveform)]
    }

    /// The time since the finger went down, and the loudness since the last tick: nil while the microphone is still
    /// starting and has recorded nothing (CM-131).
    package mutating func tick(elapsedMs: Int, level: Double?) -> [Effect] {
        switch state {
        case let .holding(_, cancel, lock): state = .holding(elapsedMs: elapsedMs, cancel: cancel, lock: lock)
        case .locked: state = .locked(elapsedMs: elapsedMs)
        default: return []
        }
        if let level { levels.append(min(1, max(0, level))) }
        guard elapsedMs >= maxMs else { return [] }
        state = .review(durationMs: elapsedMs)
        return [.stop]
    }

    /// "Dayandır" while locked.
    package mutating func stop() -> [Effect] {
        guard case .locked(let elapsed) = state else { return [] }
        state = .review(durationMs: elapsed)
        return [.stop]
    }

    /// "Sil" while locked or listening.
    package mutating func delete() -> [Effect] {
        guard isLockedOrReview else { return [] }
        state = .idle
        return [.discard(animated: true)]
    }

    /// "Göndər" while locked or listening.
    package mutating func send() -> [Effect] {
        guard isLockedOrReview else { return [] }
        state = .idle
        return [.send(waveform: waveform)]
    }

    /// The recorder could not start or lost the microphone: nothing goes.
    package mutating func fail() -> [Effect] {
        guard state != .idle else { return [] }
        state = .idle
        return [.discard(animated: false)]
    }

    /// What goes with the message: `Waveform.points` levels of 0–100.
    package var waveform: [Int] { Waveform.encode(levels) }

    private var isLockedOrReview: Bool {
        switch state {
        case .locked, .review: return true
        default: return false
        }
    }
}
