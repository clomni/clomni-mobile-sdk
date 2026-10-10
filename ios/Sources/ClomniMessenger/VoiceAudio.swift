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
/// (it plays with the silent switch on, as in WhatsApp) and play-and-record while one is recorded, and comes back after.
enum VoiceSession {
    private static var saved: (category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)?

    @discardableResult
    static func begin(recording: Bool) -> Bool {
        let session = AVAudioSession.sharedInstance()
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
            return true
        } catch {
            ClomniLog.warning("voice message: the audio session would not start: \(error.localizedDescription)")
            return false
        }
    }

    static func end() {
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
final class AVMicInput: MicInput {
    private var recorder: AVAudioRecorder?

    func start(_ file: URL) -> Bool {
        guard VoiceSession.begin(recording: true) else { return false }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let recorder = try AVAudioRecorder(url: file, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            self.recorder = recorder
            return true
        } catch {
            ClomniLog.warning("the microphone did not start: \(error.localizedDescription)")
            VoiceSession.end()
            return false
        }
    }

    func level() -> Double {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        return Waveform.level(decibels: Double(recorder.averagePower(forChannel: 0)))
    }

    func stop() -> Int? {
        guard let recorder else { return nil }
        let duration = Int(recorder.currentTime * 1000)
        recorder.stop()
        self.recorder = nil
        VoiceSession.end()
        guard duration > 0 else {
            recorder.deleteRecording()
            return nil
        }
        return duration
    }

    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        self.recorder = nil
        VoiceSession.end()
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
        VoiceSession.begin(recording: false)
        player.rate = Float(rate)
        player.play()
    }

    func pause() {
        player?.pause()
        VoiceSession.end()
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
        VoiceSession.end()
    }

    func duration(of file: URL) -> Int? {
        guard let player = try? AVAudioPlayer(contentsOf: file) else { return nil }
        let duration = Int(player.duration * 1000)
        return duration > 0 ? duration : nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        VoiceSession.end()
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
