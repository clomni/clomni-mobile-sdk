// The platform's side of voice messages (CM-130), with nothing but the system's own audio: AVAudioRecorder writes AAC
// in MP4 (.m4a, mono, 22.05 kHz, 32 kbit/s: about 240 KB a minute), AVAudioPlayer plays, URLSession fetches into the
// cache. iOS only; Linux has no AVFoundation.
#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import CryptoKit
import Foundation
import UIKit
#if canImport(ClomniCore)
import ClomniProtocol
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// The audio session while a voice message plays or records. An app's own category (a call, its own player) is left
/// as it is; the default one, or the ambient one of the message sounds, becomes playback while a voice message plays
/// (it plays with the silent switch on, as in WhatsApp) and play-and-record while one is recorded, and comes back once
/// neither the player nor the microphone holds it. The microphone begins it on its own queue, the player on the main
/// one; the lock keeps them in turn.
enum VoiceSession {
    enum User: Hashable {
        case microphone, player
    }

    private static let lock = NSLock()
    private static var saved: (category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)?
    private static var users: Set<User> = []

    @discardableResult
    static func begin(_ user: User) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let session = AVAudioSession.sharedInstance()
        let recording = user == .microphone
        let mine: [AVAudioSession.Category] = recording ? [.soloAmbient, .ambient, .playback] : [.soloAmbient, .ambient]
        do {
            if mine.contains(session.category) {
                if saved == nil { saved = (session.category, session.mode, session.categoryOptions) }
                if recording {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                } else {
                    try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                }
            }
            try session.setActive(true)
            users.insert(user)
            return true
        } catch {
            ClomniLog.warning("voice message: the audio session would not start: \(error.localizedDescription)")
            if users.isEmpty { restore() }
            return false
        }
    }

    /// `user` is done with it; the last one out lets the session go and gives the app its category back.
    static func end(_ user: User) {
        lock.lock()
        defer { lock.unlock() }
        users.remove(user)
        if users.isEmpty { restore() }
    }

    private static func restore() {
        guard let saved else { return }
        self.saved = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(saved.category, mode: saved.mode, options: saved.options)
    }
}

/// The microphone: whether the app may ask for it at all, whether it was given, asking, and the way to the settings.
enum MicrophoneAccess {
    private static var loggedUndeclared = false

    /// The app's Info.plist explains the microphone (NSMicrophoneUsageDescription); iOS ends an app that asks without
    /// it. Without it there is no microphone button, and the log says why once.
    static var declared: Bool {
        let declared = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
        if !declared && !loggedUndeclared {
            loggedUndeclared = true
            ClomniLog.warning("voice messages are off: the app's Info.plist has no NSMicrophoneUsageDescription")
        }
        return declared
    }

    static var permission: VoiceRecording.Permission {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            default: return .undecided
            }
        }
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undecided
        }
    }

    /// The system's question; the user presses again once it is answered.
    static func ask() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { _ in }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }
    }

    /// "Ayarlara keç": the app's page in Settings, where the microphone is allowed.
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// A light tick when recording starts, a firmer one when it locks, a sharp one when it is thrown away.
    static func feedback(_ feedback: VoiceRecorderController.Feedback) {
        switch feedback {
        case .start: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .lock: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .cancel: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }
}

/// Recordings being made and fetched, in the caches; logout clears them with the pictures.
final class CachedVoiceFiles: VoiceFiles {
    static let shared = CachedVoiceFiles()

    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("clomni_voice", isDirectory: true)
    }

    /// A new file for the next recording.
    static func newRecording() -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("voice-\(UUID().uuidString.lowercased()).m4a")
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    func fetch(_ url: URL, done: @escaping (URL?) -> Void) {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        // The extension tells AVAudioPlayer what it reads.
        let target = Self.directory.appendingPathComponent(url.pathExtension.isEmpty ? name : "\(name).\(url.pathExtension)")
        if FileManager.default.fileExists(atPath: target.path) { return done(target) }
        URLSession.shared.downloadTask(with: url) { temporary, response, error in
            var kept: URL?
            if let temporary, let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) {
                try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: target)
                if (try? FileManager.default.moveItem(at: temporary, to: target)) != nil { kept = target }
            }
            if kept == nil { ClomniLog.warning("voice message not fetched: \(error?.localizedDescription ?? "HTTP error")") }
            DispatchQueue.main.async { done(kept) }
        }.resume()
    }
}

/// `MicInput` on AVAudioRecorder, with metering for the waveform.
///
/// Getting the microphone means activating the play-and-record session: the route changes (a Bluetooth headset goes to
/// its hands-free profile) and the call blocks, for up to a second or more on a device. So it runs on a queue of its own,
/// and the recorder records the moment the session is up (CM-131). The session is not begun before the press: it stops
/// the music of other apps as it starts, and the message sounds play only in the ambient category. After a recording
/// it stays up for `keepSeconds`, so the next press records at once; the conversation closing lets it go at once.
final class AVMicInput: MicInput {
    /// How long the session stays up after a recording: a second message usually follows within seconds.
    static let keepSeconds = 5.0
    private static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    private let queue = DispatchQueue(label: "ai.clomni.voice.microphone", qos: .userInitiated)
    private var recorder: AVAudioRecorder?
    /// The start on its way; a stop or a cancel before it comes back clears it, and what it began is thrown away.
    private var starting: UUID?
    private var release: DispatchWorkItem?

    func start(_ file: URL, ready: @escaping (Bool) -> Void) {
        release?.cancel()
        release = nil
        let ticket = UUID()
        starting = ticket
        queue.async {
            let recorder = Self.record(into: file)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.starting == ticket else {
                    recorder?.stop()
                    recorder?.deleteRecording()
                    self?.releaseSoon()
                    return
                }
                self.starting = nil
                self.recorder = recorder
                if recorder == nil { self.releaseSoon() }
                ready(recorder != nil)
            }
        }
    }

    /// The session and a recorder that records; nil when the microphone cannot be had. On `queue`.
    private static func record(into file: URL) -> AVAudioRecorder? {
        let began = DispatchTime.now().uptimeNanoseconds
        guard VoiceSession.begin(.microphone) else { return nil }
        do {
            let recorder = try AVAudioRecorder(url: file, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            ClomniLog.debug("voice message: the microphone records \((DispatchTime.now().uptimeNanoseconds - began) / 1_000_000) ms after the press")
            return recorder
        } catch {
            ClomniLog.warning("the microphone did not start: \(error.localizedDescription)")
            return nil
        }
    }

    /// The session goes `keepSeconds` after the last recording, unless another one starts first.
    private func releaseSoon() {
        release?.cancel()
        let work = DispatchWorkItem { [queue] in queue.async { VoiceSession.end(.microphone) } }
        release = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.keepSeconds, execute: work)
    }

    func level() -> Double {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        return Waveform.level(decibels: Double(recorder.averagePower(forChannel: 0)))
    }

    func stop() -> Int? {
        starting = nil
        guard let recorder else { return nil }
        let duration = Int(recorder.currentTime * 1000)
        recorder.stop()
        self.recorder = nil
        releaseSoon()
        guard duration > 0 else {
            recorder.deleteRecording()
            return nil
        }
        return duration
    }

    func cancel() {
        starting = nil
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        self.recorder = nil
        releaseSoon()
    }

    func close() {
        cancel()
        release?.cancel()
        release = nil
        queue.async { VoiceSession.end(.microphone) }
    }
}

/// `AudioOutput` on AVAudioPlayer; a call or another app taking the sound pauses it.
final class AVVoiceOutput: NSObject, AudioOutput, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var listener: AudioOutputListener?
    private var interruptions: NSObjectProtocol?

    override init() {
        super.init()
        interruptions = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                                               queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began, let self, self.player?.isPlaying == true else { return }
            self.player?.pause()
            self.listener?.interrupted()
        }
    }

    deinit {
        if let interruptions { NotificationCenter.default.removeObserver(interruptions) }
    }

    func open(_ file: URL, listener: AudioOutputListener) {
        close()
        do {
            let player = try AVAudioPlayer(contentsOf: file)
            player.enableRate = true
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            self.listener = listener
            listener.ready(durationMs: Int(player.duration * 1000))
        } catch {
            ClomniLog.warning("voice message cannot play: \(error.localizedDescription)")
            listener.failed()
        }
    }

    func play(rate: Double) {
        guard let player else { return }
        VoiceSession.begin(.player)
        player.rate = Float(rate)
        player.play()
    }

    func pause() {
        player?.pause()
        VoiceSession.end(.player)
    }

    func seek(to positionMs: Int) {
        player?.currentTime = Double(positionMs) / 1000
    }

    func setRate(_ rate: Double) {
        player?.rate = Float(rate)
    }

    var positionMs: Int { Int((player?.currentTime ?? 0) * 1000) }

    func close() {
        player?.stop()
        player = nil
        listener = nil
        VoiceSession.end(.player)
    }

    func duration(of file: URL) -> Int? {
        guard let player = try? AVAudioPlayer(contentsOf: file) else { return nil }
        let duration = Int(player.duration * 1000)
        return duration > 0 ? duration : nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        VoiceSession.end(.player)
        if flag { listener?.finished() } else { listener?.failed() }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === self.player else { return }
        let listener = self.listener
        close()
        listener?.failed()
    }
}
#endif
