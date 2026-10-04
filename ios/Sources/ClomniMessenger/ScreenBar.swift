#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// ✕, the same on every screen (DESIGN-PASS-2 6): a 40 pt circle with a 20 pt cross drawn 2 pt thick, in a 44 pt
/// target. Over the brand's colours the circle is white at 55%; on a white screen it is the text colour at 6%.
struct CloseButton: View {
    enum Style {
        case onBrand, onSurface
    }

    let label: String
    var style: Style = .onSurface
    let theme: ClomniTheme
    let action: () -> Void

    private var fill: Color {
        switch style {
        case .onBrand: return Color.white.opacity(0.55)
        case .onSurface: return theme.colors.textPrimary.color.opacity(0.06)
        }
    }

    /// Dark on the white circle over the brand, the text colour on a white screen.
    private var ink: Color {
        switch style {
        case .onBrand: return RGBColor(red: 0.106, green: 0.114, blue: 0.129).color
        case .onSurface: return theme.colors.textPrimary.color
        }
    }

    var body: some View {
        Button(action: action) {
            CrossShape()
                .stroke(ink, style: StrokeStyle(lineWidth: CGFloat(ClomniTheme.Size.closeStroke), lineCap: .round))
                .frame(width: CGFloat(ClomniTheme.Size.closeGlyph), height: CGFloat(ClomniTheme.Size.closeGlyph))
                .frame(width: CGFloat(ClomniTheme.Size.closeCircle), height: CGFloat(ClomniTheme.Size.closeCircle))
                .background(Circle().fill(fill))
                // Where the circle is laid out, for the test that holds every screen's button to one size.
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CloseCircleFrame.self, value: proxy.frame(in: .named(CloseCircleFrame.space)))
                })
                .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

/// The close button's circle as laid out, in the coordinate space named `space` around it.
struct CloseCircleFrame: PreferenceKey {
    static let space = "clomni.closeButton"
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// The cross itself, corner to corner inside its frame, inset by half its line so the caps stay in.
struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = CGFloat(ClomniTheme.Size.closeStroke) / 2 + 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        return path
    }
}

/// "‹", the back button: the system's chevron in a 44 pt target.
struct BackButton: View {
    let label: String
    let color: RGBColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color.color)
                .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

/// "‹" in the close button's circle (40 pt, the text colour at 6%, the chevron 20 in the text colour, 44 pt target):
/// the pair of buttons of a centred bar.
struct CircleBackButton: View {
    let label: String
    let theme: ClomniTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: CGFloat(ClomniTheme.Size.closeGlyph) - 2, weight: .semibold))
                .frame(width: CGFloat(ClomniTheme.Size.closeGlyph), height: CGFloat(ClomniTheme.Size.closeGlyph))
                .foregroundStyle(theme.colors.textPrimary.color)
                .frame(width: CGFloat(ClomniTheme.Size.closeCircle), height: CGFloat(ClomniTheme.Size.closeCircle))
                .background(Circle().fill(theme.colors.textPrimary.color.opacity(0.06)))
                .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

/// Every screen's top bar: `leading` (back, the logo, who answers) and ✕ at the end, the buttons 16 pt from the sides
/// and the 40 pt circle 12 pt under the safe area. The 44 pt targets reach 2 pt past the circle, so the bar's own
/// padding is 2 pt less.
struct ScreenBar<Leading: View>: View {
    let closeLabel: String
    var closeStyle: CloseButton.Style = .onSurface
    let theme: ClomniTheme
    let close: () -> Void
    @ViewBuilder let leading: () -> Leading

    static var overhang: CGFloat {
        CGFloat(ClomniTheme.Size.touchTarget - ClomniTheme.Size.closeCircle) / 2
    }

    var body: some View {
        HStack(alignment: .center, spacing: CGFloat(ClomniTheme.Space.s)) {
            leading()
            // ✕ at the end even when `leading` is empty: a frame on an EmptyView lays out nothing, and the bar then
            // shrank to the button and sat on the leading side (Home without a logo).
            Spacer(minLength: 0)
            CloseButton(label: closeLabel, style: closeStyle, theme: theme, action: close)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, CGFloat(ClomniTheme.Size.barEdge) - Self.overhang)
        .padding(.top, CGFloat(ClomniTheme.Size.barTop) - Self.overhang)
        .padding(.bottom, CGFloat(ClomniTheme.Space.s) - Self.overhang)
    }
}
#endif
