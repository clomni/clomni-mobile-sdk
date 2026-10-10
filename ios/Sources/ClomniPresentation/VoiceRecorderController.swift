import Foundation

/// The microphone as `VoiceRecorderController` uses it: AVAudioRecorder in the SDK, a double in tests.
package protocol MicInput: AnyObject {
    /// Starts recording AAC (m4a) into `file`; false when the microphone cannot be had.
    func start(_ file: URL) -> Bool
    /// The loudness now, 0–1.
    func level() -> Double
    /// Stops; the recording's length in ms, or nil when nothing usable was written (the file is then gone).
    func stop() -> Int?
    /// Stops and deletes what was written.
    func cancel()
}

/// A finished recording: the m4a, its length and its waveform (0–100 each).
package struct VoiceClip: Sendable, Equatable {
    package let file: URL
    package let durationMs: Int
    package let waveform: [Int]

    package init(file: URL, durationMs: Int, waveform: [Int]) {
        self.file = file
        self.durationMs = durationMs
        self.waveform = waveform
    }
}

/// Runs `VoiceRecording` against the microphone: starts and stops it, reads the clock and the loudness every
/// `tickMs` for the timer and the live waveform, and hands a finished recording to `send`. The view reads `state`,
/// `levels`, `hint` and `review` after each `onChange`, and drops the microphone into the bin each time `discards`
/// grows. On the main queue; the same as the Android SDK's VoiceRecorderController.
package final class VoiceRecorderController {
    /// What the capsule over the button says: hold longer; the microphone is refused (with the way to the settings);
    /// the recording reached the limit and stopped.
    package enum Hint: Sendable, Equatable, CaseIterable {
        case hold, denied, limit
    }

    /// The haptic ticks: recording started, locked, thrown away.
    package enum Feedback: Sendable, Equatable {
        case start, lock, cancel
    }

    /// 20 a second: the timer and the live waveform.
    package static let tickMs = 50
    package static let holdHintMs = 2_000
    package static let deniedHintMs = 6_000

    /// Called after anything the view shows changed.
    package var onChange: (() -> Void)?
    package private(set) var hint: Hint?
    /// Stopped and waiting: what Send sends and the preview plays.
    package private(set) var review: VoiceClip?
    /// Grows with each recording thrown away by a slide or Delete: the view's cue for the bin.
    package private(set) var discards = 0
    package let maxMs: Int

    private var machine: VoiceRecording
    private let mic: MicInput
    private let permission: () -> VoiceRecording.Permission
    private let askPermission: () -> Void
    private let newFile: () -> URL
    private let scheduler: VoiceScheduler
    private let now: () -> Int
    private let send: (VoiceClip) -> Void
    private let feedback: (Feedback) -> Void
    private var file: URL?
    private var recording = false
    private var startedAt = 0
    private var cancelTick: (() -> Void)?
    private var cancelHint: (() -> Void)?

    /// `now`: milliseconds on a clock that only goes forward.
    package init(mic: MicInput, permission: @escaping () -> VoiceRecording.Permission, askPermission: @escaping () -> Void,
                 newFile: @escaping () -> URL, scheduler: VoiceScheduler, now: @escaping () -> Int, maxMs: Int,
                 send: @escaping (VoiceClip) -> Void, feedback: @escaping (Feedback) -> Void = { _ in }) {
        self.mic = mic
        self.permission = permission
        self.askPermission = askPermission
        self.newFile = newFile
        self.scheduler = scheduler
        self.now = now
        self.maxMs = maxMs
        self.send = send
        self.feedback = feedback
        machine = VoiceRecording(maxMs: maxMs)
    }

    package var state: VoiceRecording.State { machine.state }
    /// The loudness so far, a level a tick.
    package var levels: [Double] { machine.levels }

    package func press() { run(machine.press(permission())) }
    package func pressLocked() { run(machine.pressLocked(permission())) }
    /// `dx`, `dy`: points from where the finger went down.
    package func drag(dx: Double, dy: Double) { run(machine.drag(dx: dx, dy: dy)) }
    package func release() { run(machine.release()) }
    package func stop() { run(machine.stop()) }
    package func delete() { run(machine.delete()) }
    package func sendNow() { run(machine.send()) }

    package func dismissHint() {
        setHint(nil)
        onChange?()
    }

    /// The screen goes away: a recording in progress or waiting is thrown away.
    package func close() {
        _ = machine.fail()
        discard(animated: false)
        setHint(nil)
    }

    private func run(_ effects: [VoiceRecording.Effect]) {
        effects.forEach(apply)
        onChange?()
    }

    private func apply(_ effect: VoiceRecording.Effect) {
        switch effect {
        case .start: start()
        case .send(let waveform): finish(waveform)
        case .stop: stopForReview()
        case .discard(let animated): discard(animated: animated)
        case .holdHint: setHint(.hold)
        case .locked: feedback(.lock)
        case .askPermission: askPermission()
        case .permissionDenied: setHint(.denied)
        }
    }

    private func start() {
        setHint(nil)
        let target = newFile()
        guard mic.start(target) else {
            _ = machine.fail()
            return
        }
        file = target
        recording = true
        startedAt = now()
        feedback(.start)
        scheduleTick()
    }

    private func scheduleTick() {
        cancelTick = scheduler.after(Self.tickMs) { [weak self] in self?.tick() }
    }

    private func tick() {
        guard recording else { return }
        let effects = machine.tick(elapsedMs: now() - startedAt, level: mic.level())
        if effects.contains(.stop) { setHint(.limit) }
        run(effects)
        if recording { scheduleTick() }
    }

    /// The recording's length, or nil when the recorder had nothing.
    private func stopMic() -> Int? {
        cancelTick?()
        cancelTick = nil
        recording = false
        return mic.stop()
    }

    private func finish(_ waveform: [Int]) {
        var clip: VoiceClip?
        if recording {
            if let duration = stopMic(), let file { clip = VoiceClip(file: file, durationMs: duration, waveform: waveform) }
        } else if let review {
            clip = VoiceClip(file: review.file, durationMs: review.durationMs, waveform: waveform)
        }
        file = nil
        review = nil
        if let clip { send(clip) }
    }

    private func stopForReview() {
        guard recording else { return }
        guard let duration = stopMic(), let file else {
            _ = machine.fail()
            file = nil
            return
        }
        review = VoiceClip(file: file, durationMs: duration, waveform: machine.waveform)
    }

    private func discard(animated: Bool) {
        if recording {
            cancelTick?()
            cancelTick = nil
            recording = false
            mic.cancel()
        } else if let review {
            try? FileManager.default.removeItem(at: review.file)
        }
        file = nil
        review = nil
        if animated {
            discards += 1
            feedback(.cancel)
        }
    }

    private func setHint(_ next: Hint?) {
        cancelHint?()
        cancelHint = nil
        hint = next
        guard let next else { return }
        cancelHint = scheduler.after(next == .denied ? Self.deniedHintMs : Self.holdHintMs) { [weak self] in
            self?.hint = nil
            self?.onChange?()
        }
    }
}
