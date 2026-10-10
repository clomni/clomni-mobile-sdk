// Snapshots need UIKit: they run on the iOS Simulator (CI's xcodebuild test step), not in swift test on Linux or macOS.
#if canImport(UIKit) && canImport(SwiftUI)
import Foundation
import SwiftUI
import UIKit
import XCTest
import ClomniProtocol
import ClomniPresentation
@testable import ClomniMessenger

/// Voice messages (CM-130), light and dark: the bubble in each of its states on both sides (and at accessibility3),
/// the recorder held (the big microphone under the finger, the lock over it), locked, stopped for listening, the bin
/// and the capsules, and the composer's round button. A microphone double stands in for the real one (CI has none).
@MainActor
final class VoiceSnapshotTests: XCTestCase {
    private let strings = ClomniStrings(language: "az")
    private let audio = MessageContent.Audio(url: URL(string: "https://app.clomni.ai/f/voice-7d1c.m4a")!, mime: "audio/mp4",
                                             size: 96_412, durationMs: 14_260, waveform: VoiceSnapshotTests.waveform)
    private let operatorAudio = MessageContent.Audio(url: URL(string: "https://app.clomni.ai/f/cavab.mp3")!, mime: "audio/mpeg",
                                                     size: 381_220)
    private let time = StepTime()

    private func theme(_ dark: Bool) -> ClomniTheme {
        let data = try? Data(contentsOf: fixtures.appendingPathComponent("42-config-example.json"))
        return ClomniTheme.make(brand: data.flatMap(ProtocolJSON.parseConfig)?.brand, dark: dark)
    }

    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("protocol/fixtures")
    }

    private func snap<Content: View>(_ name: String, dark: Bool, size: DynamicTypeSize = .large, _ content: (ClomniTheme) -> Content) throws {
        let theme = theme(dark)
        let scene = content(theme)
            .padding(16)
            .frame(width: 390)
            .background(theme.colors.background.color)
            .environment(\.colorScheme, dark ? .dark : .light)
            .dynamicTypeSize(size)
        let image = Snapshot.render(scene, width: 390, dark: dark)
        XCTAssertFalse(Snapshot.isBlank(image), name)
        try Snapshot.assert(image, named: name)
    }

    func testBubbles() throws {
        for dark in [false, true] {
            try snap("voice-bubbles" + (dark ? "-dark" : "-light"), dark: dark) { bubbles($0) }
        }
        try snap("voice-bubbles-light-ax3", dark: false, size: .accessibility3) { bubbles($0, short: true) }
    }

    func testRecorderHeld() throws {
        let strings = self.strings
        for dark in [false, true] {
            let recorder = recorder()
            recorder.controller.press()
            time.advance(4_200)
            recorder.controller.drag(dx: -36, dy: -30)
            guard case let .holding(_, cancel, lock) = recorder.state else { return XCTFail("not holding") }
            try snap("voice-recorder-held" + (dark ? "-dark" : "-light"), dark: dark) { theme in
                ZStack(alignment: .bottomTrailing) {
                    Color.clear.frame(height: 330)
                    composer(theme) { VoiceRecordingBar(recorder: recorder, playback: playback(), theme: theme, strings: strings, animated: false) }
                    // The overlay as the button draws it: centred on the round button at the composer's end.
                    VoiceHoldOverlay(cancel: cancel, lock: lock, level: 0.6, theme: theme, animated: false)
                        .frame(width: 48, height: 48)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    func testRecorderLockedStoppedBinAndCapsules() throws {
        let strings = self.strings
        for dark in [false, true] {
            let locked = recorder()
            locked.controller.pressLocked()
            time.advance(12_300)
            let stopped = recorder()
            stopped.controller.pressLocked()
            time.advance(9_000)
            stopped.controller.stop()
            try snap("voice-recorder-states" + (dark ? "-dark" : "-light"), dark: dark) { theme in
                VStack(spacing: 20) {
                    composer(theme) { VoiceRecordingBar(recorder: locked, playback: playback(), theme: theme, strings: strings, animated: false) }
                    composer(theme) { VoiceRecordingBar(recorder: stopped, playback: playback(), theme: theme, strings: strings, animated: false) }
                    composer(theme) {
                        HStack { BinDrop(theme: theme, frozenAt: 0.5) {}; Spacer() }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 20).fill(theme.colors.surface.color))
                    }
                    ForEach([VoiceRecorderController.Hint.hold, .denied, .limit], id: \.self) { hint in
                        HStack { Spacer(); VoiceHintCapsule(hint: hint, theme: theme, strings: strings, maxSeconds: 300, openSettings: {}) }
                    }
                }
            }
        }
    }

    /// The composer's new end (operator, 2026-10-09): the field with the paper clip in it, right of it the round button:
    /// the microphone while empty, the arrow with text; without a microphone, the arrow dimmed.
    func testComposerButton() throws {
        let strings = self.strings
        for dark in [false, true] {
            let recorder = recorder()
            try snap("voice-composer" + (dark ? "-dark" : "-light"), dark: dark) { theme in
                VStack(spacing: 12) {
                    ForEach(0..<3) { row in
                        HStack(spacing: 8) {
                            HStack {
                                Text(row == 1 ? "Salam" : strings[.composerPlaceholder])
                                    .clomniFont(ClomniTheme.FontSize.text)
                                    .foregroundStyle((row == 1 ? theme.colors.textPrimary : theme.colors.textSecondary).color)
                                Spacer()
                                Image(systemName: "paperclip").font(.system(size: 20)).foregroundStyle(theme.colors.textSecondary.color)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 20).fill(theme.colors.surface.color))
                            ComposerSendButton(canSend: row == 1, recorder: row == 2 ? nil : recorder, theme: theme, strings: strings, send: {})
                        }
                    }
                }
            }
        }
    }

    // MARK: - Scenes

    /// Both sides, every state: ready, playing at 1.5×, paused half-heard, without a waveform, loading, uploading, broken.
    private func bubbles(_ theme: ClomniTheme, short: Bool = false) -> some View {
        let strings = self.strings
        let mine = VoiceNote(id: "msg_f100", audio: audio, outgoing: true)
        let theirs = VoiceNote(id: "msg_f101", audio: operatorAudio, outgoing: false)
        let heard = VoiceNote(id: "msg_f102", audio: audio, outgoing: false)
        let sending = VoiceNote.sending(clientId: "client-1", file: URL(fileURLWithPath: "/tmp/v.m4a"), durationMs: 3_400,
                                        waveform: Self.waveform, uploading: true)
        var rows: [(VoiceNote, VoicePlayer.Track, VoicePlayer.Speed)] = [
            (mine, .init(), .normal),
            (mine, .init(phase: .playing, positionMs: 5_800, durationMs: 14_260), .fast),
            (heard, .init(phase: .paused, positionMs: 8_900, durationMs: 14_260), .fast),
            (theirs, .init(durationMs: 61_000), .normal),
            (theirs, .init(phase: .loading, durationMs: 61_000), .normal),
            (sending, .init(), .normal),
            (theirs, .init(phase: .failed), .normal),
        ]
        if short { rows = Array(rows.prefix(3)) }
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                let (note, track, speed) = item.element
                HStack {
                    if note.outgoing { Spacer(minLength: 0) }
                    VoiceMessageContent(note: note, track: track, speed: speed, theme: theme, strings: strings,
                                        toggle: {}, seek: { _ in }, cycleSpeed: {}) {
                        HStack(spacing: 3) {
                            Text("10:31").clomniFont(11, relativeTo: .caption2)
                            if note.outgoing { Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)) }
                        }
                        .foregroundStyle((note.outgoing ? theme.colors.onPrimary : theme.colors.textSecondary).color.opacity(0.75))
                    }
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill((note.outgoing ? theme.colors.primary : theme.colors.surface).color))
                    if !note.outgoing { Spacer(minLength: 0) }
                }
            }
        }
    }

    /// The composer's row as the conversation draws it: the bar where the field is, the 48 pt slot at the end.
    private func composer<Bar: View>(_ theme: ClomniTheme, @ViewBuilder bar: () -> Bar) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            bar()
            Color.clear.frame(width: 48, height: 48)
        }
        .padding(.vertical, 8)
    }

    private func recorder() -> VoiceRecorder {
        let folder = FileManager.default.temporaryDirectory
        return VoiceRecorder(controller: VoiceRecorderController(
            mic: SteadyMic(time: time), permission: { .granted }, askPermission: {},
            newFile: { folder.appendingPathComponent("voice-\(UUID().uuidString).m4a") }, scheduler: time, now: { [time] in time.now },
            maxMs: 300_000, send: { _ in }))
    }

    private func playback() -> VoicePlayback {
        VoicePlayback(player: VoicePlayer(files: NoFiles(), output: SilentOutput(), scheduler: StepTime()))
    }

    /// The 64 levels of fixtures 100 and 102.
    static let waveform = [
        8, 28, 21, 37, 35, 45, 47, 49, 54, 47, 54, 39, 47, 28, 35, 19, 21, 13, 12, 12, 9, 19, 15, 34, 29, 54, 53, 74, 76, 89, 92,
        94, 97, 88, 91, 72, 75, 50, 53, 33, 32, 19, 16, 13, 8, 14, 9, 23, 15, 35, 29, 46, 43, 52, 51, 52, 52, 44, 47, 31, 38, 18,
        28, 13,
    ]
}

/// A clock moved by hand.
private final class StepTime: VoiceScheduler {
    private(set) var now = 0
    private var timers: [(due: Int, order: Int, action: () -> Void)] = []
    private var order = 0

    func after(_ milliseconds: Int, _ action: @escaping () -> Void) -> () -> Void {
        let mine = order
        order += 1
        timers.append((now + milliseconds, mine, action))
        return { [weak self] in self?.timers.removeAll { $0.order == mine } }
    }

    func advance(_ ms: Int) {
        let end = now + ms
        while let next = timers.filter({ $0.due <= end }).min(by: { ($0.due, $0.order) < ($1.due, $1.order) }) {
            timers.removeAll { $0.order == next.order }
            now = next.due
            next.action()
        }
        now = end
    }
}

/// A voice that goes loud and quiet in turn, measured by the hand-moved clock.
private final class SteadyMic: MicInput {
    private let time: StepTime
    private var startedAt = 0
    private var tick = 0

    init(time: StepTime) { self.time = time }

    func start(_ file: URL, ready: @escaping (Bool) -> Void) {
        startedAt = time.now
        ready(true)
    }

    func level() -> Double {
        tick += 1
        return [0.2, 0.7, 0.9, 0.5, 0.3, 0.8, 0.1][tick % 7]
    }

    func stop() -> Int? { time.now - startedAt }
    func cancel() {}
    func close() {}
}

private final class NoFiles: VoiceFiles {
    func fetch(_ url: URL, done: @escaping (URL?) -> Void) {}
}

private final class SilentOutput: AudioOutput {
    func open(_ file: URL, listener: AudioOutputListener) {}
    func play(rate: Double) {}
    func pause() {}
    func seek(to positionMs: Int) {}
    func setRate(_ rate: Double) {}
    var positionMs: Int { 0 }
    func close() {}
    func duration(of file: URL) -> Int? { nil }
}
#endif
