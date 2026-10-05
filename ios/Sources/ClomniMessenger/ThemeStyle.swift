// The UI is iOS only; Linux has neither SwiftUI nor UIKit, and the macOS test run skips these files.
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

extension RGBColor {
    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

/// The app's font family (`Clomni.setTypeface`); nil is the system font.
private struct TypefaceKey: EnvironmentKey {
    static let defaultValue: Typeface? = nil
}

/// The loading indicator's VoiceOver label in the screen's language, for views that do not get the screen.
private struct LoadingLabelKey: EnvironmentKey {
    static let defaultValue = ClomniStrings(language: nil)[.loading]
}

/// The screen's width, for widths given as a share of it (a bubble's 78%).
private struct ScreenWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 390
}

/// The app's `Clomni.setTheme` colour and mode.
private struct ThemeOverrideKey: EnvironmentKey {
    static let defaultValue = ThemeOverride()
}

extension EnvironmentValues {
    var clomniThemeOverride: ThemeOverride {
        get { self[ThemeOverrideKey.self] }
        set { self[ThemeOverrideKey.self] = newValue }
    }

    var clomniLoadingLabel: String {
        get { self[LoadingLabelKey.self] }
        set { self[LoadingLabelKey.self] = newValue }
    }

    var clomniScreenWidth: CGFloat {
        get { self[ScreenWidthKey.self] }
        set { self[ScreenWidthKey.self] = newValue }
    }

    var clomniTypeface: Typeface? {
        get { self[TypefaceKey.self] }
        set { self[TypefaceKey.self] = newValue }
    }
}

extension Typeface {
    /// The family's faces as installed in the app; nil when it has none.
    static func installed(_ family: String) -> Typeface? {
        let faces = UIFont.fontNames(forFamilyName: family).compactMap { name -> Face? in
            guard let font = UIFont(name: name, size: 17),
                  !font.fontDescriptor.symbolicTraits.contains(.traitItalic) else { return nil }
            let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
            let trait = (traits?[.weight] as? NSNumber)?.doubleValue
            return Face(name: name, weight: Typeface.weight(name: name, trait: trait))
        }
        return Typeface(family: family, faces: faces)
    }
}

extension Font.Weight {
    /// 100 … 900, to find the family's face.
    var css: Int {
        if self == .ultraLight { return 100 }
        if self == .thin { return 200 }
        if self == .light { return 300 }
        if self == .medium { return 500 }
        if self == .semibold { return 600 }
        if self == .bold { return 700 }
        if self == .heavy { return 800 }
        if self == .black { return 900 }
        return 400
    }
}

/// A font of a fixed size that still follows Dynamic Type, scaled like `style`: the app's family when it set one,
/// else the system font.
struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let base: CGFloat
    private let weight: Font.Weight
    private let style: Font.TextStyle
    @Environment(\.clomniTypeface) private var typeface

    init(size: Double, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: CGFloat(size), relativeTo: style)
        base = CGFloat(size)
        self.weight = weight
        self.style = style
    }

    func body(content: Content) -> some View {
        // Font.custom(relativeTo:) scales with Dynamic Type by itself, from the unscaled size.
        content.font(typeface.map { Font.custom($0.face(for: weight.css), size: base, relativeTo: style) }
            ?? .system(size: size, weight: weight))
    }
}

/// Text inside a shape of a fixed size (an avatar's initial, the launcher's count): the family, not scaled.
struct FixedFont: ViewModifier {
    let size: Double
    let weight: Font.Weight
    @Environment(\.clomniTypeface) private var typeface

    func body(content: Content) -> some View {
        content.font(typeface.map { Font.custom($0.face(for: weight.css), fixedSize: CGFloat(size)) }
            ?? .system(size: CGFloat(size), weight: weight))
    }
}

extension View {
    func clomniFont(_ size: Double, _ weight: Font.Weight = .regular,
                    relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size: size, weight: weight, relativeTo: style))
    }

    func clomniFixedFont(_ size: Double, _ weight: Font.Weight) -> some View {
        modifier(FixedFont(size: size, weight: weight))
    }

    /// A new appearance from the panel (config.changed) fades in over 250 ms on the open screen.
    func configCrossfade(_ config: MessengerConfig?) -> some View {
        animation(.easeInOut(duration: 0.25), value: config)
    }

    /// A Home card (DESIGN-PASS-2 5): white (the surface grey in dark mode), radius 16, padding 20, a shadow one
    /// barely sees, no border.
    func clomniCard(_ theme: ClomniTheme) -> some View {
        modifier(CardStyle(theme: theme))
    }
}

struct CardStyle: ViewModifier {
    let theme: ClomniTheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.homeCard), style: .continuous)
        let shadow = ClomniTheme.Shadow.card
        return content
            .padding(CGFloat(ClomniTheme.Space.xxl))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape
                    .fill(theme.isDark ? theme.colors.surface.color : theme.colors.background.color)
                    .shadow(color: Color.black.opacity(theme.isDark ? 0 : shadow.opacity),
                            radius: CGFloat(shadow.radius) / 2, x: 0, y: CGFloat(shadow.y))
            )
    }
}

/// A round avatar: the picture when it loads; until then (or without one) the initial on grey, or primary_soft
/// where there is no initial (the team's avatars).
struct AvatarView: View {
    let url: URL?
    let initial: String
    let size: Double
    let theme: ClomniTheme

    var body: some View {
        ZStack {
            Circle().fill(initial.isEmpty ? theme.colors.primarySoft.color : theme.colors.textSecondary.color)
            Text(initial)
                .clomniFixedFont(size * 0.41, .semibold)
                .foregroundStyle(Color.white)
            if let url = url {
                RemoteImage(url: url, kind: .icon, points: size, theme: theme, placeholder: .clear)
            }
        }
        .frame(width: CGFloat(size), height: CGFloat(size))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// A block in the brand's soft tone standing in for content while the first load runs (brief 8 · 7.5: no spinner).
struct SkeletonBlock: View {
    let height: Double
    let theme: ClomniTheme

    var body: some View {
        // primary_soft, as every placeholder (APPEARANCE-CONTRACT § 4).
        RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.card), style: .continuous)
            .fill(theme.colors.primarySoft.color)
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(height))
            .accessibilityHidden(true)
    }
}

/// The thin strip under the header (DESIGN-PASS-3 C1): 32 high on the text colour at 6%, a small icon and "İnternet
/// yoxdur" in 13 text_muted, opening and closing in 200 ms; the screen under it stays as the cache has it. When the
/// connection is back it says `connected` ("Qoşuldu") for a second, then closes. `below` is room under it while it
/// shows.
struct OfflineStrip: View {
    let offline: String?
    let connected: String
    let theme: ClomniTheme
    var below: CGFloat = 0
    @State private var back = false
    /// Bumped by every change, so an earlier second cannot close a later "Qoşuldu".
    @State private var generation = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: String? { offline ?? (back ? connected : nil) }

    var body: some View {
        VStack(spacing: 0) {
            if let text {
                HStack(spacing: 6) {
                    Image(systemName: offline != nil ? "wifi.slash" : "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(text)
                        .clomniFont(13, relativeTo: .footnote)
                        .lineLimit(1)
                }
                .foregroundStyle(theme.colors.textSecondary.color)
                .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .background(theme.colors.textPrimary.color.opacity(0.06))
                .padding(.bottom, below)
                .accessibilityElement(children: .combine)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: text)
        .onChange(of: offline != nil) { isOffline in
            generation += 1
            back = !isOffline
            if let text { UIAccessibility.post(notification: .announcement, argument: text) }
            guard !isOffline else { return }
            let shown = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if generation == shown { back = false }
            }
        }
    }
}

/// "Nəsə səhv getdi" with "Yenidən cəhd et".
struct FailureView: View {
    let failure: HomeScreen.Failure
    let theme: ClomniTheme
    let retry: () -> Void

    var body: some View {
        VStack(spacing: CGFloat(ClomniTheme.Space.m)) {
            Text(failure.message)
                .clomniFont(ClomniTheme.FontSize.text)
                .foregroundStyle(theme.colors.textPrimary.color)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text(failure.retry)
                    .clomniFont(ClomniTheme.FontSize.text, .semibold)
                    .foregroundStyle(theme.colors.primary.color)
                    .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
                    .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .clomniCard(theme)
    }
}
#endif

#if canImport(SwiftUI) && canImport(UIKit)
/// The press highlight cut to the element's own shape (DESIGN-PASS-3 A5): a capsule, a circle or the card's radius,
/// never a square; the label dims a little as PlainButtonStyle does, and the tap area is the same shape.
struct PressShapeStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0)))
            .clipShape(shape)
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .pressScale(configuration.isPressed)
    }
}
#endif
