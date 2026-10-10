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

private struct VoicePlaybackKey: EnvironmentKey {
    static let defaultValue: VoicePlayback? = nil
}

extension EnvironmentValues {
    /// The conversation's player (`ChatModel.playback`); none in previews and snapshots.
    var clomniVoicePlayback: VoicePlayback? {
        get { self[VoicePlaybackKey.self] }
        set { self[VoicePlaybackKey.self] = newValue }
    }
}

/// `VoicePlayer` for SwiftUI: `version` moves with every change, so the bubbles reading it redraw.
final class VoicePlayback: ObservableObject {
    let player: VoicePlayer
    @Published private(set) var version = 0

    init(player: VoicePlayer) {
        self.player = player
        player.onChange = { [weak self] in self?.version += 1 }
    }

    /// One player for the conversation's screen: AVAudioPlayer, files fetched once into the caches.
    static func live() -> VoicePlayback {
        VoicePlayback(player: VoicePlayer(files: CachedVoiceFiles.shared, output: AVVoiceOutput(), scheduler: MainQueueVoiceScheduler()))
    }
}

/// A voice message in its bubble, as WhatsApp draws one: the round play button (a spinner in it while the file comes
/// or the user's recording uploads), the waveform filling as it plays (tap or drag it to move), under it the length,
/// or what is left while it plays, and the bubble's time and ticks (`meta`) at its bottom end; while it plays, the
/// speed (1× → 1.5× → 2×). Only the content: the caller gives the bubble's shape and colour.
struct VoiceMessageBubble<Meta: View>: View {
    let note: VoiceNote
    @ObservedObject var playback: VoicePlayback
    let theme: ClomniTheme
    let strings: ClomniStrings
    @ViewBuilder let meta: () -> Meta

    var body: some View {
        let player = playback.player
        VoiceMessageContent(note: note, track: player.track(note.id), speed: player.speed, theme: theme, strings: strings,
                            toggle: { player.toggle(note.id, source: note.source, knownDurationMs: note.durationMs) },
                            seek: { player.seek(note.id, to: $0, knownDurationMs: note.durationMs) },
                            cycleSpeed: { player.cycleSpeed() }, meta: meta)
            .onAppear {
                // A length the message does not say comes from the file: fetched once, before the first play.
                if note.durationMs == nil, case .remote(let url) = note.source { player.prefetch(note.id, url: url) }
            }
    }
}

/// `VoiceMessageBubble` for a given `track` and `speed`: what the snapshots draw.
struct VoiceMessageContent<Meta: View>: View {
    let note: VoiceNote
    let track: VoicePlayer.Track
    let speed: VoicePlayer.Speed
    let theme: ClomniTheme
    let strings: ClomniStrings
    let toggle: () -> Void
    let seek: (Double) -> Void
    let cycleSpeed: () -> Void
    @ViewBuilder let meta: () -> Meta
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var started: Bool { track.phase == .playing || (track.phase == .paused && track.positionMs > 0) }

    var body: some View {
        let colors = theme.colors
        let fill = note.outgoing ? colors.primary : colors.surface
        let ink = note.outgoing ? colors.onPrimary : colors.textPrimary
        let failed = track.phase == .failed
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                playButton
                WaveformBar(waveform: note.waveform, progress: track.progress,
                            played: (note.outgoing ? colors.onPrimary : colors.primary).color,
                            unplayed: (note.outgoing ? colors.onPrimary : colors.textSecondary).color.opacity(0.42),
                            playhead: started, label: note.accessibilityLabel(track, strings: strings), value: note.time(track),
                            seek: seek)
                    .frame(height: 32)
                if started {
                    Button(action: cycleSpeed) {
                        Text(speed.label)
                            .clomniFont(12, .semibold, relativeTo: .caption)
                            .foregroundStyle(ink.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(ink.over(fill, opacity: 0.16).color))
                            .frame(minWidth: CGFloat(ClomniTheme.Size.touchTarget), minHeight: CGFloat(ClomniTheme.Size.touchTarget))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(strings[.voiceSpeed]) \(speed.label)"))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            HStack(alignment: .bottom, spacing: 4) {
                Text(failed ? strings[.voiceUnavailable] : note.time(track))
                    .monospacedDigit()
                    .clomniFont(12, relativeTo: .caption)
                    .foregroundStyle((failed ? ink : ink.over(fill, opacity: 0.75)).color)
                    .lineLimit(1)
                    .accessibilityHidden(true)
                Spacer(minLength: 4)
                meta()
            }
            .padding(.leading, 48)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(minWidth: 220, maxWidth: 260, alignment: .leading)
        .animation(reduceMotion ? nil : Motion.press, value: started)
    }

    /// The 40 pt circle: the brand's on the operator's bubble, on_primary on the user's; the icon in the other colour.
    private var playButton: some View {
        let colors = theme.colors
        let circle = note.outgoing ? colors.onPrimary : colors.primary
        let glyph = note.outgoing ? colors.primary : colors.onPrimary
        let playing = track.phase == .playing
        return Button(action: toggle) {
            ZStack {
                Circle().fill(circle.color).frame(width: 40, height: 40)
                if track.phase == .loading || note.sending {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: glyph.color))
                } else {
                    // The triangle's weight sits left of its box: a point to the right centres it.
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(glyph.color)
                        .offset(x: playing ? 0 : 1)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
            .contentShape(Circle())
        }
        .buttonStyle(PressShapeStyle(shape: Circle()))
        .accessibilityLabel(Text(track.phase == .loading ? strings[.loading] : strings[playing ? .voicePause : .voicePlay]))
        .animation(reduceMotion ? nil : Motion.press, value: playing)
    }
}

/// `waveform`'s bars (2.5 pt, 2 apart, rounded), those already heard in `played`, and with `playhead` the dot where it
/// is. A tap or a drag moves it there (`seek`); VoiceOver reads `label` and `value` and moves it by tenths. Shared by
/// the bubble and the recorder's preview.
struct WaveformBar: View {
    let waveform: [Int]?
    let progress: Double
    let played: Color
    let unplayed: Color
    let playhead: Bool
    let label: String
    let value: String
    let seek: (Double) -> Void
    @State private var dragged: Double? = nil

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let heights = Waveform.bars(waveform, count: WaveformBars.count(width))
            let shown = dragged ?? progress
            let heard = heights.indices.filter { (Double($0) + 0.5) / Double(heights.count) <= shown }.count
            ZStack(alignment: .topLeading) {
                WaveformBars(heights: heights, range: 0..<heard).fill(played)
                WaveformBars(heights: heights, range: heard..<heights.count).fill(unplayed)
                if playhead || dragged != nil {
                    Circle().fill(played).frame(width: 10, height: 10)
                        .position(x: (width - WaveformBars.gap) * shown, y: geometry.size.height / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragged = min(1, max(0, $0.location.x / max(1, width))) }
                .onEnded { _ in
                    if let dragged { seek(dragged) }
                    dragged = nil
                })
        }
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seek(min(1, progress + 0.1))
            case .decrement: seek(max(0, progress - 0.1))
            @unknown default: break
            }
        }
    }
}

/// Bars of `heights` (0–1 of the height), centred: those in `range` only, so the heard and the rest take two colours.
struct WaveformBars: Shape {
    static let bar: CGFloat = 2.5
    static let gap: CGFloat = 2

    let heights: [Double]
    let range: Range<Int>

    /// How many bars fit `width`.
    static func count(_ width: CGFloat) -> Int { max(1, Int((width + gap) / (bar + gap))) }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in range where heights.indices.contains(index) {
            let height = max(Self.bar, rect.height * CGFloat(heights[index]))
            let box = CGRect(x: rect.minX + CGFloat(index) * (Self.bar + Self.gap), y: rect.midY - height / 2, width: Self.bar, height: height)
            path.addRoundedRect(in: box, cornerSize: CGSize(width: Self.bar / 2, height: Self.bar / 2))
        }
        return path
    }
}
#endif
