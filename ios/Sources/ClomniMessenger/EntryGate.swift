#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// A screen's `ScreenEntry` for SwiftUI (CM-346 § 5.1). UIKitMessenger makes one per screen it shows and starts it
/// again when a tab's list comes back into view.
@MainActor
final class ScreenEntryModel: ObservableObject {
    @Published private(set) var waited = false
    private let entry: ScreenEntry

    init(minimum: TimeInterval = ScreenEntry.minimum) {
        entry = ScreenEntry(minimum: minimum)
        entry.onChange = { [weak self] in
            guard let self else { return }
            self.waited = self.entry.waited
        }
    }

    func restart() {
        entry.start()
    }
}

private struct ScreenEntryKey: EnvironmentKey {
    static let defaultValue: ScreenEntryModel? = nil
}

extension EnvironmentValues {
    /// The entry of the screen this view is on; nil where there is none (the UI tests' demo screens, snapshots): the
    /// content shows at once.
    var clomniScreenEntry: ScreenEntryModel? {
        get { self[ScreenEntryKey.self] }
        set { self[ScreenEntryKey.self] = newValue }
    }
}

extension View {
    /// The screen's content behind its entry (CM-346 § 5.1): until the minimum has passed and `ready`, the page's own
    /// `background` with the spinner in the middle; then the content, fading in over 150 ms (at once with Reduce
    /// Motion). The content stays built behind it, so a tab keeps its place and its data.
    func entryGate(ready: Bool, background: Color, theme: ClomniTheme, label: String) -> some View {
        modifier(EntryGate(ready: ready, background: background, theme: theme, label: label))
    }
}

private struct EntryGate: ViewModifier {
    let ready: Bool
    let background: Color
    let theme: ClomniTheme
    let label: String
    @Environment(\.clomniScreenEntry) private var entry

    @ViewBuilder
    func body(content: Content) -> some View {
        if let entry {
            Gated(entry: entry, ready: ready, background: background, theme: theme, label: label, content: content)
        } else {
            content
        }
    }
}

private struct Gated<Content: View>: View {
    @ObservedObject var entry: ScreenEntryModel
    let ready: Bool
    let background: Color
    let theme: ClomniTheme
    let label: String
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = entry.waited && ready
        ZStack {
            background.ignoresSafeArea()
            content
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(shown)
                .accessibilityHidden(!shown)
            if !shown {
                ScreenSpinner(theme: theme, label: label)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.identity)
            }
        }
        // Only coming in fades; going (a tab chosen again) is at once, so nothing of the screen shows over the spinner.
        .animation(shown && !reduceMotion ? .easeOut(duration: ScreenEntry.fadeIn) : nil, value: shown)
    }
}

/// The system's spinner at its own size in the brand's colour, no text (VoiceOver reads "Yüklənir").
private struct ScreenSpinner: View {
    let theme: ClomniTheme
    let label: String

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                ProgressView().progressViewStyle(.circular).tint(theme.colors.primary.color)
            } else {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: theme.colors.primary.color))
            }
        }
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier("clomni.loading")
    }
}
#endif
