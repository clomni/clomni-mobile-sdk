#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// The live step's buttons: right-aligned pills side by side, wrapping, then a grey "← Geri" unless the flow has its
/// own restart. A tap fades them out; the choice stays as the user's message.
struct QuickRepliesView: View {
    let block: QuickReplyBlock
    let theme: ClomniTheme
    let tap: (String) -> Void
    @State private var chosen = false

    var body: some View {
        // Right-aligned over the composer, 8 pt apart; the transcript keeps them 16 pt from the screen's edges.
        layout
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, CGFloat(ClomniTheme.Space.l))
            .opacity(chosen ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: chosen)
            .allowsHitTesting(!chosen)
    }

    /// Side by side, each as wide as its text, wrapping onto the next line, right-aligned, 8 apart both ways
    /// (DESIGN-PASS-3 A3). iOS 15 has no custom layout: one under another there.
    @ViewBuilder
    private var layout: some View {
        if #available(iOS 16.0, *) {
            WrapLayout(spacing: CGFloat(ClomniTheme.Space.s)) { pills }
        } else {
            VStack(alignment: .trailing, spacing: CGFloat(ClomniTheme.Space.s)) { pills }
        }
    }

    @ViewBuilder
    private var pills: some View {
        ForEach(block.buttons) { button in
            PillButton(title: button.title, accessibilityLabel: button.accessibilityLabel, isBack: false, theme: theme) {
                choose(button.id)
            }
        }
        if let back = block.back {
            PillButton(title: back.title, accessibilityLabel: back.accessibilityLabel, isBack: true, theme: theme) {
                choose(back.id)
            }
        }
    }

    private func choose(_ id: String) {
        guard !chosen else { return }
        chosen = true
        tap(id)
    }
}

/// A capsule with a clear outline (operator, 2026-10-04): white (surface in dark mode), 1.5 pt border in the text
/// colour at 18% (24% in dark mode), text 16 regular in the text colour that wraps rather than cuts, at least 44
/// high, 20 pt on the sides and 10 on top and bottom; pressed, the text colour at 6%.
struct PillButton: View {
    let title: String
    let accessibilityLabel: String
    let isBack: Bool
    let theme: ClomniTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .clomniFont(16, relativeTo: .body)
                .foregroundStyle(isBack ? theme.colors.textSecondary.color : theme.colors.textPrimary.color)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
                .padding(.horizontal, CGFloat(ClomniTheme.Space.xxl))
                .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
        }
        .buttonStyle(PillStyle(theme: theme))
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

struct PillStyle: ButtonStyle {
    let theme: ClomniTheme

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        let text = theme.colors.textPrimary.color
        return configuration.label
            .background(ZStack {
                shape.fill(theme.isDark ? theme.colors.surface.color : theme.colors.background.color)
                shape.fill(text.opacity(configuration.isPressed ? 0.06 : 0))
            })
            .overlay(shape.strokeBorder(text.opacity(theme.isDark ? 0.24 : 0.18), lineWidth: 1.5))
            .contentShape(shape)
    }
}

/// Rows of children, wrapping when a row is full: right-aligned (pills) or from the leading edge (channel icons).
@available(iOS 16.0, *)
struct WrapLayout: Layout {
    var spacing: CGFloat
    var leading = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = leading ? bounds.minX : bounds.maxX - row.width
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
#endif
