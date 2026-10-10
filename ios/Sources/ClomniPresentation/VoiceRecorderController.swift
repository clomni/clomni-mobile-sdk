import Foundation

/// The microphone as `VoiceRecorderController` uses it: AVAudioRecorder in the SDK, a double in tests.
package protocol MicInput: AnyObject {
    /// Starts recording AAC (m4a) into `file`, off the main thread: getting the microphone can take a second on a
    /// device, longer with a Bluetooth headset. `ready` comes on the main queue: true once it records, false when the
    /// microphone cannot be had; never when `cancel()` came first.
    func start(_ file: URL, ready: @escaping (Bool) -> Void)
    /// The loudness now, 0–1.
    func level() -> Double
    /// Stops; the recording's length in ms, or nil when nothing usable was written (the file is then gone).
    func stop() -> Int?
    /// Stops and deletes what was written; a start still on its way records nothing.
    func cancel()
    /// The conversation closed: the audio is let go now, not a few seconds later.
    func close()
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
///
/// The press shows at once and the clock runs from the touch (CM-131): the overlay, the haptic tick and the timer do not
/// wait for the microphone, which may come a second later, and a press is long or short by the finger, not by the
/// microphone. Let go before the microphone came, nothing was recorded: the hint asks to hold.
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
    /// A recording is under way: the microphone is coming or records.
    private var recording = false
    /// The microphone's start came back: it records.
    private var micOn = false
    /// When the finger went down.
    private var pressedAt = 0
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
        mic.close()
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
        file = target
        recording = true
        micOn = false
        pressedAt = now()
        feedback(.start)
        scheduleTick()
        mic.start(target) { [weak self] ok in self?.micReady(ok, target) }
    }

    private func micReady(_ ok: Bool, _ target: URL) {
        guard recording, file == target else { return }
        guard ok else {
            stopTicking()
            recording = false
            file = nil
            run(machine.fail())
            return
        }
        micOn = true
        onChange?()
    }

    private func scheduleTick() {
        cancelTick = scheduler.after(Self.tickMs) { [weak self] in self?.tick() }
    }

    private func stopTicking() {
        cancelTick?()
        cancelTick = nil
    }

    private func tick() {
        guard recording else { return }
        let effects = machine.tick(elapsedMs: now() - pressedAt, level: micOn ? mic.level() : nil)
        if effects.contains(.stop) { setHint(.limit) }
        run(effects)
        if recording { scheduleTick() }
    }

    /// The recording's length, or nil when the recorder had nothing (or had not come yet).
    private func stopMic() -> Int? {
        stopTicking()
        recording = false
        guard micOn else {
            mic.cancel()
            return nil
        }
        micOn = false
        return mic.stop()
    }

    private func finish(_ waveform: [Int]) {
        var clip: VoiceClip?
        if recording {
            let early = !micOn
            if let duration = stopMic(), let file {
                clip = VoiceClip(file: file, durationMs: duration, waveform: waveform)
            } else if early {
                setHint(.hold)
            }
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
            stopTicking()
            recording = false
            micOn = false
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
