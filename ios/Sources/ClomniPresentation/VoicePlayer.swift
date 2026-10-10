import Foundation

/// Runs an action after `milliseconds` on the main queue; the closure it returns cancels it. Tests move a clock by hand.
package protocol VoiceScheduler: AnyObject {
    func after(_ milliseconds: Int, _ action: @escaping () -> Void) -> () -> Void
}

/// `VoiceScheduler` on the main dispatch queue.
package final class MainQueueVoiceScheduler: VoiceScheduler {
    package init() {}

    package func after(_ milliseconds: Int, _ action: @escaping () -> Void) -> () -> Void {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: item)
        return { item.cancel() }
    }
}

/// What happens to the file an `AudioOutput` opened last; a callback for an earlier file never comes.
package protocol AudioOutputListener: AnyObject {
    func ready(durationMs: Int)
    func failed()
    func finished()
    /// A call or another app took the sound: it is paused.
    func interrupted()
}

/// The speaker as `VoicePlayer` uses it: AVAudioPlayer in the SDK, a fake in tests. One file at a time.
package protocol AudioOutput: AnyObject {
    /// Opens `file`, closing the one before it; `listener` hears when it can play.
    func open(_ file: URL, listener: AudioOutputListener)
    func play(rate: Double)
    func pause()
    func seek(to positionMs: Int)
    /// Changes the speed of what plays; a paused file keeps it for its next `play`.
    func setRate(_ rate: Double)
    var positionMs: Int { get }
    /// Lets the file and the sound go.
    func close()
    /// `file`'s length without playing it, or nil when it is not a recording the platform reads.
    func duration(of file: URL) -> Int?
}

/// Fetches a recording once, then answers from the cache; `done` runs on the main queue, with nil on a failure.
package protocol VoiceFiles: AnyObject {
    func fetch(_ url: URL, done: @escaping (URL?) -> Void)
}

/// Plays voice messages, one at a time: starting one pauses the other where it was. Each bubble reads its own `track`;
/// the speed (1×, 1.5×, 2×) is one for all, the last one chosen, as in WhatsApp. A file comes from `files` (once, then
/// from the cache) or, for the user's own recording, from the disk. On the main queue; the same as the Android SDK's
/// VoicePlayer.
package final class VoicePlayer {
    package enum Phase: Sendable, Equatable {
        case idle, loading, playing, paused, failed
    }

    /// `durationMs` is nil until known: from the message, or from the file once it is here.
    package struct Track: Sendable, Equatable {
        package var phase: Phase = .idle
        package var positionMs = 0
        package var durationMs: Int?

        package init(phase: Phase = .idle, positionMs: Int = 0, durationMs: Int? = nil) {
            self.phase = phase
            self.positionMs = positionMs
            self.durationMs = durationMs
        }

        /// How far it has played, 0–1.
        package var progress: Double {
            guard let durationMs, durationMs > 0 else { return 0 }
            return min(1, max(0, Double(positionMs) / Double(durationMs)))
        }
    }

    package enum Speed: Double, CaseIterable, Sendable {
        case normal = 1, fast = 1.5, fastest = 2

        package var label: String {
            switch self {
            case .normal: return "1×"
            case .fast: return "1.5×"
            case .fastest: return "2×"
            }
        }

        package var next: Speed {
            let all = Speed.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    /// Where a recording is: the server's, fetched once; or a file on the device (being sent, or being reviewed).
    package enum Source: Sendable, Equatable {
        case remote(URL)
        case local(URL)
    }

    /// The waveform fills smoothly: 20 times a second.
    package static let tickMs = 50

    package private(set) var speed: Speed = .normal
    /// Called after any track or the speed changed.
    package var onChange: (() -> Void)?

    private let files: VoiceFiles
    private let output: AudioOutput
    private let scheduler: VoiceScheduler
    private var tracks: [String: Track] = [:]
    private var probed: Set<String> = []
    /// The message open in `output`.
    private var current: String?
    /// Bumped with each open: an answer for an earlier one is dropped.
    private var generation = 0
    private var cancelTick: (() -> Void)?

    package init(files: VoiceFiles, output: AudioOutput, scheduler: VoiceScheduler) {
        self.files = files
        self.output = output
        self.scheduler = scheduler
    }

    package func track(_ id: String) -> Track { tracks[id] ?? Track() }

    /// The play/pause button of message `id`; `knownDurationMs` is the message's own.
    package func toggle(_ id: String, source: Source, knownDurationMs: Int?) {
        var track = self.track(id)
        if id == current {
            switch track.phase {
            case .playing: return pauseCurrent()
            case .paused:
                output.play(rate: speed.rawValue)
                track.phase = .playing
                set(id, track)
                return tick()
            case .loading:
                generation += 1
                current = nil
                track.phase = .idle
                return set(id, track)
            default: break
            }
        }
        leaveCurrent()
        generation += 1
        let opening = generation
        current = id
        track.phase = .loading
        track.durationMs = track.durationMs ?? knownDurationMs
        set(id, track)
        switch source {
        case .local(let file): open(id, file, opening)
        case .remote(let url):
            files.fetch(url) { [weak self] file in
                guard let self, opening == self.generation else { return }
                if let file { self.open(id, file, opening) } else { self.fail(id) }
            }
        }
    }

    /// Moves message `id` to `fraction` of its length (a tap or a drag on its waveform): where it plays, or where it
    /// starts next. Nothing for a length not known yet.
    package func seek(_ id: String, to fraction: Double, knownDurationMs: Int?) {
        var track = self.track(id)
        guard let duration = track.durationMs ?? knownDurationMs else { return }
        let position = Int(Double(duration) * min(1, max(0, fraction)))
        if id == current, track.phase == .playing || track.phase == .paused { output.seek(to: position) }
        if track.phase == .idle || track.phase == .failed { track.phase = .paused }
        track.positionMs = position
        track.durationMs = duration
        set(id, track)
    }

    /// 1× → 1.5× → 2× → 1×.
    package func cycleSpeed() {
        speed = speed.next
        if let current, track(current).phase == .playing { output.setRate(speed.rawValue) }
        onChange?()
    }

    /// Learns the length of a recording whose message does not say it (the panel's MP3), by fetching the file; asked
    /// once per message.
    package func prefetch(_ id: String, url: URL) {
        guard track(id).durationMs == nil, probed.insert(id).inserted else { return }
        files.fetch(url) { [weak self] file in
            guard let self, let file, let duration = self.output.duration(of: file), self.track(id).durationMs == nil else { return }
            var track = self.track(id)
            track.durationMs = duration
            self.set(id, track)
        }
    }

    /// A recording starts, or the screen goes: what plays pauses where it is.
    package func pause() { pauseCurrent() }

    /// The screen is gone: the file and the sound are let go.
    package func release() {
        pauseCurrent()
        generation += 1
        current = nil
        output.close()
    }

    private func open(_ id: String, _ file: URL, _ opening: Int) {
        output.open(file, listener: Listener(player: self, id: id, opening: opening))
    }

    /// The output's answers for one open; those for an earlier one are dropped.
    private final class Listener: AudioOutputListener {
        weak var player: VoicePlayer?
        let id: String
        let opening: Int

        init(player: VoicePlayer, id: String, opening: Int) {
            self.player = player
            self.id = id
            self.opening = opening
        }

        private var live: VoicePlayer? {
            guard let player, player.generation == opening else { return nil }
            return player
        }

        func ready(durationMs: Int) { live?.ready(id, durationMs) }
        func failed() { live?.fail(id) }

        func finished() {
            guard let player = live else { return }
            player.stopTicking()
            player.current = nil
            var track = player.track(id)
            track.phase = .idle
            track.positionMs = 0
            player.set(id, track)
        }

        func interrupted() { live?.pauseCurrent() }
    }

    private func ready(_ id: String, _ durationMs: Int) {
        var track = self.track(id)
        let duration = durationMs > 0 ? durationMs : track.durationMs
        let start = duration.map { track.positionMs < $0 ? track.positionMs : 0 } ?? track.positionMs
        if start > 0 { output.seek(to: start) }
        output.play(rate: speed.rawValue)
        track.phase = .playing
        track.positionMs = start
        track.durationMs = duration
        set(id, track)
        tick()
    }

    private func fail(_ id: String) {
        stopTicking()
        if current == id { current = nil }
        var track = self.track(id)
        track.phase = .failed
        set(id, track)
    }

    /// Another message is about to play: this one pauses, or stops loading.
    private func leaveCurrent() {
        guard let id = current else { return }
        var track = self.track(id)
        if track.phase == .loading {
            track.phase = .idle
            set(id, track)
        } else {
            pauseCurrent()
        }
    }

    private func pauseCurrent() {
        guard let id = current else { return }
        var track = self.track(id)
        guard track.phase == .playing else { return }
        output.pause()
        stopTicking()
        track.phase = .paused
        track.positionMs = output.positionMs
        set(id, track)
    }

    /// While one plays, its position every `tickMs`.
    private func tick() {
        stopTicking()
        guard let id = current else { return }
        var track = self.track(id)
        guard track.phase == .playing else { return }
        track.positionMs = min(output.positionMs, track.durationMs ?? Int.max)
        set(id, track)
        cancelTick = scheduler.after(Self.tickMs) { [weak self] in self?.tick() }
    }

    private func stopTicking() {
        cancelTick?()
        cancelTick = nil
    }

    private func set(_ id: String, _ track: Track) {
        tracks[id] = track
        onChange?()
    }
}
