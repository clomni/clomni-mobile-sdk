#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// `VoiceRecorderController` for SwiftUI: `version` moves with every change; `dropping` while the bin's animation runs.
final class VoiceRecorder: ObservableObject {
    let controller: VoiceRecorderController
    @Published private(set) var version = 0
    /// A recording was thrown away: the microphone falls into the bin, the bar still there around it.
    @Published var dropping = false
    private var discards = 0

    init(controller: VoiceRecorderController) {
        self.controller = controller
        controller.onChange = { [weak self] in
            guard let self else { return }
            version += 1
            if self.controller.discards != discards {
                discards = self.controller.discards
                dropping = true
            }
        }
    }

    var state: VoiceRecording.State { controller.state }

    /// The bar takes the field's place: while recording, while listening back, and while the bin closes.
    var showsBar: Bool { state != .idle || dropping }

    /// The conversation's recorder, or nil when the app's Info.plist does not explain the microphone (no microphone
    /// button then). `send` gets each finished recording.
    static func live(maxSeconds: Int, send: @escaping (VoiceClip) -> Void) -> VoiceRecorder? {
        guard MicrophoneAccess.declared else { return nil }
        return VoiceRecorder(controller: VoiceRecorderController(
            mic: AVMicInput(), permission: { MicrophoneAccess.permission }, askPermission: MicrophoneAccess.ask,
            newFile: CachedVoiceFiles.newRecording, scheduler: MainQueueVoiceScheduler(),
            // A clock that only goes forward; not systemUptime, a required-reason API (PrivacyManifestTests).
            now: { Int(DispatchTime.now().uptimeNanoseconds / 1_000_000) }, maxMs: maxSeconds * 1000, send: send,
            feedback: MicrophoneAccess.feedback))
    }
}

/// The round button at the composer's end, right of the field (operator, 2026-10-09: WhatsApp's layout; the emoji
/// button goes, the keyboard has emoji). The microphone while there is nothing to send, the arrow once there is; the one
/// turns into the other on a spring. Tapped as the arrow, it sends. Held as the microphone, it records: the circle grows
/// under the finger and follows it, the lock rises over it (`VoiceHoldOverlay`); left far enough the recording is thrown
/// away, up far enough it locks; a short press asks to hold; with VoiceOver a double tap records, locked. The capsule
/// over it says why nothing happened. Without a `recorder` it is the arrow, dimmed while there is nothing to send.
struct ComposerSendButton: View {
    let canSend: Bool
    let recorder: VoiceRecorder?
    let theme: ClomniTheme
    let strings: ClomniStrings
    let send: () -> Void

    var body: some View {
        if let recorder {
            MicSendButton(canSend: canSend, recorder: recorder, theme: theme, strings: strings, send: send)
        } else {
            Button(action: send) {
                SendCircle(mic: false, enabled: canSend, theme: theme)
            }
            .buttonStyle(PressShapeStyle(shape: Circle()))
            .disabled(!canSend)
            .accessibilityLabel(Text(strings[.send]))
        }
    }
}

/// The 44 pt circle (the field's height) with the microphone or the arrow, turning into each other.
private struct SendCircle: View {
    let mic: Bool
    let enabled: Bool
    let theme: ClomniTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ink = (enabled ? theme.colors.onPrimary : theme.colors.textSecondary).color
        ZStack {
            Circle().fill((enabled ? theme.colors.primary : theme.colors.surface).color).frame(width: 44, height: 44)
            Image(systemName: "mic.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(ink)
                .opacity(mic ? 1 : 0)
                .scaleEffect(mic ? 1 : 0.6)
                .rotationEffect(.degrees(mic ? 0 : -90))
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(ink)
                .opacity(mic ? 0 : 1)
                .scaleEffect(mic ? 0.6 : 1)
                .rotationEffect(.degrees(mic ? 90 : 0))
        }
        .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
        .contentShape(Circle())
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.6), value: mic)
    }
}

private struct MicSendButton: View {
    let canSend: Bool
    @ObservedObject var recorder: VoiceRecorder
    let theme: ClomniTheme
    let strings: ClomniStrings
    let send: () -> Void
    @State private var pressed = false

    var body: some View {
        let mic = !canSend
        let controller = recorder.controller
        SendCircle(mic: mic, enabled: true, theme: theme)
            .opacity(holding == nil ? 1 : 0)
            .onTapGesture { if !mic { send() } }
            .gesture(hold, including: mic ? .all : .subviews)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(strings[mic ? .voiceRecord : .send]))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if mic { controller.pressLocked() } else { send() }
            }
            .overlay {
                if let holding {
                    VoiceHoldOverlay(cancel: holding.cancel, lock: holding.lock, level: controller.levels.last ?? 0, theme: theme)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let hint = controller.hint {
                    VoiceHintCapsule(hint: hint, theme: theme, strings: strings, maxSeconds: controller.maxMs / 1000,
                                     openSettings: MicrophoneAccess.openSettings)
                        .fixedSize()
                        .offset(y: -56)
                }
            }
    }

    private var holding: (cancel: Double, lock: Double)? {
        if case let .holding(_, cancel, lock) = recorder.state { return (cancel, lock) }
        return nil
    }

    /// The finger down records, its slide cancels or locks, its lifting sends (or asks to hold).
    private var hold: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pressed {
                    pressed = true
                    recorder.controller.press()
                }
                recorder.controller.drag(dx: value.translation.width, dy: value.translation.height)
            }
            .onEnded { _ in
                pressed = false
                recorder.controller.release()
            }
    }
}

/// The overlay's square, centred on the button.
let voiceOverlaySize: CGFloat = 320

/// Under the finger while it holds: the 72 pt circle with the microphone, grown from the button on a spring, following
/// the slide, a soft ring round it breathing with the voice; over it the lock in its capsule, rising as the finger goes
/// up and closing near the top.
struct VoiceHoldOverlay: View {
    let cancel: Double
    let lock: Double
    let level: Double
    let theme: ClomniTheme
    @State private var grown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `animated`: grows from the button; a snapshot draws it grown.
    init(cancel: Double, lock: Double, level: Double, theme: ClomniTheme, animated: Bool = true) {
        self.cancel = cancel
        self.lock = lock
        self.level = level
        self.theme = theme
        _grown = State(initialValue: !animated)
    }

    var body: some View {
        let colors = theme.colors
        ZStack {
            VStack(spacing: 8) {
                Image(systemName: lock > 0.66 ? "lock.fill" : "lock.open.fill").font(.system(size: 16, weight: .semibold))
                Image(systemName: "chevron.up").font(.system(size: 12, weight: .semibold)).opacity(1 - lock)
            }
            .foregroundStyle(colors.textSecondary.color)
            .frame(width: 40, height: 72)
            .background(Capsule().fill(colors.background.color).shadow(color: .black.opacity(0.12), radius: 6, y: 2))
            .overlay(Capsule().stroke(colors.border.color, lineWidth: 1))
            .offset(y: -(84 + 34 * lock))
            .opacity(max(0, 1 - cancel * 1.5))
            ZStack {
                Circle().fill(colors.primary.color.opacity(0.22)).frame(width: 72, height: 72).scaleEffect(1 + 0.4 * level)
                    .animation(.linear(duration: 0.09), value: level)
                Circle().fill(colors.primary.color).frame(width: 72, height: 72)
                Image(systemName: "mic.fill").font(.system(size: 28, weight: .semibold)).foregroundStyle(colors.onPrimary.color)
            }
            .scaleEffect(grown ? 1 : 0.5)
            .offset(x: -cancel * VoiceRecording.cancelDistance, y: -lock * VoiceRecording.lockDistance)
        }
        .frame(width: voiceOverlaySize, height: voiceOverlaySize)
        .accessibilityHidden(true)
        .onAppear {
            guard !grown else { return }
            if reduceMotion { grown = true } else { withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { grown = true } }
        }
    }
}

/// A dark capsule over the button: "Yazmaq üçün basıb saxlayın", the limit, or the refused microphone with its way out.
struct VoiceHintCapsule: View {
    let hint: VoiceRecorderController.Hint
    let theme: ClomniTheme
    let strings: ClomniStrings
    let maxSeconds: Int
    let openSettings: () -> Void

    var body: some View {
        let capsule = theme.capsule
        VStack(alignment: .leading, spacing: 0) {
            Text(text).clomniFont(ClomniTheme.FontSize.text).foregroundStyle(capsule.text.color)
            if hint == .denied {
                Button(action: openSettings) {
                    Text(strings[.voiceOpenSettings]).clomniFont(ClomniTheme.FontSize.text, .semibold).foregroundStyle(capsule.text.color)
                        .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(capsule.fill.color.opacity(capsule.opacity)))
        .padding(.trailing, 8)
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        switch hint {
        case .hold: return strings[.voiceHoldToRecord]
        case .limit: return strings.format(.voiceMaxLength, max(1, maxSeconds / 60))
        case .denied: return strings[.voiceMicDenied]
        }
    }
}

/// What takes the field's place while a voice message is made, in the field's grey pill. Holding: the red dot
/// blinking, the timer and the live waveform, under them "‹ Ləğv etmək üçün sürüşdürün" going with the finger. Locked:
/// the same over Delete, Stop and Send. Stopped: the recording to listen to over Delete and Send. Thrown away: the
/// microphone falls into the bin, which closes and sinks.
struct VoiceRecordingBar: View {
    @ObservedObject var recorder: VoiceRecorder
    @ObservedObject var playback: VoicePlayback
    let theme: ClomniTheme
    let strings: ClomniStrings
    /// The blinking and the nudge; a snapshot draws them still.
    var animated = true
    @State private var beat = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var recording: Bool {
        switch recorder.state {
        case .holding, .locked: return true
        default: return false
        }
    }

    private var holding: Bool {
        if case .holding = recorder.state { return true }
        return false
    }

    var body: some View {
        let colors = theme.colors
        VStack(spacing: 0) {
            HStack(spacing: 8) { pill }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.input), style: .continuous).fill(colors.surface.color))
            below
        }
        .animation(reduceMotion ? nil : Motion.spring, value: recorder.version)
        .onAppear {
            if recording { playback.player.pause() }
            if animated && !reduceMotion {
                withAnimation(.linear(duration: 0.55).repeatForever(autoreverses: true)) { beat = true }
            }
        }
        .onChange(of: recording) { if $0 { playback.player.pause() } }
    }

    @ViewBuilder
    private var pill: some View {
        let colors = theme.colors
        switch recorder.state {
        case .holding(let elapsed, _, _), .locked(let elapsed):
            Circle().fill(colors.unread.color).frame(width: 10, height: 10).opacity(beat ? 0.2 : 1)
            Text(VoiceTime.clock(elapsed)).monospacedDigit().clomniFont(15, .medium).foregroundStyle(colors.textPrimary.color)
                .frame(minWidth: 40, alignment: .leading)
            GeometryReader { geometry in
                let count = WaveformBars.count(geometry.size.width)
                WaveformBars(heights: Waveform.live(recorder.controller.levels, count: count), range: 0..<count)
                    .fill(colors.textSecondary.color)
            }
            .frame(height: 24)
            // The microphone under the finger covers the pill's end.
            .padding(.trailing, holding ? 36 : 0)
            .accessibilityHidden(true)
        case .review:
            if let clip = recorder.controller.review { review(clip) }
        case .idle:
            if recorder.dropping { BinDrop(theme: theme) { recorder.dropping = false } }
        }
    }

    @ViewBuilder
    private var below: some View {
        let grey = theme.colors.textSecondary.color
        switch recorder.state {
        case .holding(_, let cancel, _):
            Text("‹  " + strings[.voiceSlideToCancel])
                .clomniFont(13, relativeTo: .footnote)
                .foregroundStyle(grey)
                .lineLimit(1)
                .offset(x: -cancel * 60 - (beat ? 6 : 0))
                .opacity(max(0, 1 - cancel * 1.4))
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 2)
        case .locked, .review:
            HStack {
                control("trash", label: strings[.voiceDelete], ink: grey, action: recorder.controller.delete)
                Spacer()
                if case .locked = recorder.state {
                    control("stop.fill", label: strings[.voiceStop], ink: theme.colors.unread.color, ring: theme.colors.unread.color,
                            action: recorder.controller.stop)
                    Spacer()
                }
                control("arrow.up", label: strings[.send], ink: theme.colors.onPrimary.color, fill: theme.colors.primary.color,
                        action: recorder.controller.sendNow)
            }
            .padding(.top, 8)
        case .idle:
            EmptyView()
        }
    }

    /// The stopped recording: play it, see it fill, move in it, its length at the end.
    private func review(_ clip: VoiceClip) -> some View {
        let colors = theme.colors
        let id = "voice-review-\(clip.file.lastPathComponent)"
        let player = playback.player
        let track = player.track(id)
        let playing = track.phase == .playing
        return Group {
            Button { player.toggle(id, source: .local(clip.file), knownDurationMs: clip.durationMs) } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.primary.color)
                    .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -14)
            .accessibilityLabel(Text(strings[playing ? .voicePause : .voicePlay]))
            WaveformBar(waveform: clip.waveform, progress: track.progress, played: colors.primary.color,
                        unplayed: colors.textSecondary.color.opacity(0.45), playhead: track.phase != .idle,
                        label: strings[.voiceMessage], value: VoiceTime.length(clip.durationMs),
                        seek: { player.seek(id, to: $0, knownDurationMs: clip.durationMs) })
                .frame(height: 28)
            Text(track.positionMs > 0 ? VoiceTime.remaining(clip.durationMs - track.positionMs) : VoiceTime.length(clip.durationMs))
                .monospacedDigit()
                .clomniFont(13, relativeTo: .footnote)
                .foregroundStyle(colors.textSecondary.color)
        }
    }

    /// A 48 pt target with `symbol` in `ink`: in a 44 pt circle of `fill`, ringed in `ring`, or bare.
    private func control(_ symbol: String, label: String, ink: Color, fill: Color? = nil, ring: Color? = nil,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: fill == nil && ring == nil ? 20 : 16, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: fill == nil ? 36 : 44, height: fill == nil ? 36 : 44)
                .background(Circle().fill(fill ?? .clear))
                .overlay(Circle().stroke(ring ?? .clear, lineWidth: 2))
                .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
                .contentShape(Circle())
        }
        .buttonStyle(PressShapeStyle(shape: Circle()))
        .accessibilityLabel(Text(label))
    }
}

/// The bin and its lid, as Android draws them (clomni_ic_trash, clomni_ic_trash_lid).
enum VoiceGlyphs {
    static let bin = SVGPath("M6.25,8.5 h11.5 l-0.95,10.9 a1.75,1.75 0 0,1 -1.75,1.6 h-6.1 a1.75,1.75 0 0,1 -1.75,-1.6 z M10,11.75 v5.75 M14,11.75 v5.75")!
    static let lid = SVGPath("M4.5,6.25 h15 M9.5,6.25 v-1.25 a1.25,1.25 0 0,1 1.25,-1.25 h2.5 a1.25,1.25 0 0,1 1.25,1.25 v1.25")!
}

/// The microphone thrown away (WhatsApp's): the bin rises with its lid open, the red microphone jumps and falls in, the
/// lid shuts, the bin sinks. 1 s; with Reduce Motion a fade. `done` when it is over. `frozenAt` holds one moment of it
/// (0–1), for the snapshots.
struct BinDrop: View {
    let theme: ClomniTheme
    var frozenAt: Double?
    let done: () -> Void
    @State private var time: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BinDropFrame(t: frozenAt ?? time, theme: theme, still: reduceMotion && frozenAt == nil)
            .frame(width: 40, height: 44)
            .accessibilityHidden(true)
            .onAppear {
                guard frozenAt == nil else { return }
                let duration = reduceMotion ? 0.2 : 1
                withAnimation(.linear(duration: duration)) { time = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { done() }
            }
    }
}

/// One moment `t` (0–1) of `BinDrop`; animatable, so the moments between are drawn too.
private struct BinDropFrame: View, Animatable {
    var t: Double
    let theme: ClomniTheme
    let still: Bool

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    var body: some View {
        let red = theme.colors.unread.color
        let grey = theme.colors.textSecondary.color
        let line = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        ZStack {
            if still {
                Image(systemName: "mic.fill").foregroundStyle(red).opacity(1 - t)
            } else {
                ZStack {
                    SVGShape(svg: VoiceGlyphs.bin).stroke(grey, style: line)
                    SVGShape(svg: VoiceGlyphs.lid).stroke(grey, style: line)
                        .rotationEffect(.degrees(-40 * (ease((t - 0.12) / 0.13) - ease((t - 0.62) / 0.1))), anchor: UnitPoint(x: 0.19, y: 0.26))
                }
                .frame(width: 24, height: 24)
                .offset(y: 30 * (1 - ease(t / 0.2)) + 30 * ease((t - 0.8) / 0.2))
                .opacity(min(1, (1 - t) * 10))
                if t < 0.6 {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(red)
                        .scaleEffect(1 - 0.5 * ease((t - 0.45) / 0.15))
                        .rotationEffect(.degrees(300 * t))
                        .offset(y: -34 * ease(t / 0.3) + 40 * ease((t - 0.3) / 0.3))
                }
            }
        }
    }

    /// Ease in and out over 0–1; flat before and after.
    private func ease(_ x: Double) -> Double {
        let p = min(1, max(0, x))
        return p * p * (3 - 2 * p)
    }
}
#endif
