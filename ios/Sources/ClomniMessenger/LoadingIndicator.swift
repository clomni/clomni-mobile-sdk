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

/// The system's spinner (DESIGN-PASS 5), 24 pt in the brand's colour (grey without a config: the neutral theme's
/// primary), shown only while `loading` lasts past 300 ms and then for at least 400 ms. Its place is kept either way,
/// so nothing moves when it appears.
struct LoadingIndicator: View {
    let loading: Bool
    let label: String
    let theme: ClomniTheme
    var size: CGFloat = 24
    @StateObject private var timing = SpinnerModel()

    var body: some View {
        ZStack {
            if timing.visible {
                spinner
                    // The system spinner is 20 pt.
                    .scaleEffect(size / 20)
                    .accessibilityLabel(Text(label))
            }
        }
        .frame(width: size, height: size)
        .onAppear { timing.set(loading: loading) }
        .onChange(of: loading) { timing.set(loading: $0) }
    }

    @ViewBuilder
    private var spinner: some View {
        if #available(iOS 16.0, *) {
            ProgressView().progressViewStyle(.circular).tint(theme.colors.primary.color)
        } else {
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: theme.colors.primary.color))
        }
    }
}

@MainActor
final class SpinnerModel: ObservableObject {
    @Published private(set) var visible = false
    private let timing = SpinnerTiming()

    init() {
        timing.onChange = { [weak self] in
            guard let self else { return }
            visible = timing.visible
        }
    }

    func set(loading: Bool) {
        timing.set(loading: loading)
    }
}
#endif
