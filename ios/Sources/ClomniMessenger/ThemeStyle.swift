// The UI is iOS only; Linux has neither SwiftUI nor UIKit, and the macOS test run skips these files.
#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

extension RGBColor {
    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

/// A system font of a fixed size that still follows Dynamic Type, scaled like `style`.
struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: Double, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: CGFloat(size), relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func clomniFont(_ size: Double, _ weight: Font.Weight = .regular,
                    relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size: size, weight: weight, relativeTo: style))
    }

    /// A Home card: background, radius 12, padding 12×14, soft shadow (a 1 pt border in dark mode).
    func clomniCard(_ theme: ClomniTheme) -> some View {
        modifier(CardStyle(theme: theme))
    }
}

struct CardStyle: ViewModifier {
    let theme: ClomniTheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.card), style: .continuous)
        let shadows: [ClomniTheme.Shadow] = theme.isDark ? [] : ClomniTheme.Shadow.card
        return content
            .padding(.vertical, CGFloat(ClomniTheme.Space.l))
            .padding(.horizontal, CGFloat(ClomniTheme.Space.xl))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape
                    .fill(theme.colors.background.color)
                    .shadow(color: Color.black.opacity(shadows.first?.opacity ?? 0),
                            radius: CGFloat(shadows.first?.radius ?? 0) / 2, x: 0, y: CGFloat(shadows.first?.y ?? 0))
                    .shadow(color: Color.black.opacity(shadows.last?.opacity ?? 0),
                            radius: CGFloat(shadows.last?.radius ?? 0) / 2, x: 0, y: CGFloat(shadows.last?.y ?? 0))
            )
            .overlay(shape.stroke(theme.isDark ? theme.colors.border.color : Color.clear, lineWidth: 1))
    }
}

/// A round avatar: the picture when it loads, the initial on grey until then (or without one).
struct AvatarView: View {
    let url: URL?
    let initial: String
    let size: Double
    let theme: ClomniTheme

    var body: some View {
        ZStack {
            Circle().fill(theme.colors.textSecondary.color)
            Text(initial)
                .font(.system(size: CGFloat(size * 0.41), weight: .semibold))
                .foregroundStyle(Color.white)
            if let url = url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(width: CGFloat(size), height: CGFloat(size))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// A grey block standing in for content while the first load runs (brief 8 · 7.5: no spinner).
struct SkeletonBlock: View {
    let height: Double
    let theme: ClomniTheme

    var body: some View {
        RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.card), style: .continuous)
            .fill(theme.colors.surface.color)
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(height))
            .accessibilityHidden(true)
    }
}

/// The thin yellow strip: "İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq".
struct OfflineStrip: View {
    let text: String
    let theme: ClomniTheme

    var body: some View {
        Text(text)
            .clomniFont(ClomniTheme.FontSize.label, relativeTo: .caption)
            .foregroundStyle(theme.colors.onWarning.color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, CGFloat(ClomniTheme.Space.xs))
            .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
            .background(theme.colors.warning.color)
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
