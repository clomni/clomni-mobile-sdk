#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// The live step's buttons: right-aligned pills, one under another (vertical) or side by side wrapping (chips), then
/// a grey "← Geri". A tap fades them out; the choice stays as the user's message.
struct QuickRepliesView: View {
    let block: QuickReplyBlock
    let theme: ClomniTheme
    let tap: (String) -> Void
    @State private var chosen = false

    var body: some View {
        layout
            .frame(maxWidth: 240, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, CGFloat(ClomniTheme.Space.s))
            .opacity(chosen ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: chosen)
            .allowsHitTesting(!chosen)
    }

    @ViewBuilder
    private var layout: some View {
        if block.layout == .chips {
            if #available(iOS 16.0, *) {
                WrapLayout(spacing: CGFloat(ClomniTheme.Space.xs)) { pills }
            } else {
                VStack(alignment: .trailing, spacing: CGFloat(ClomniTheme.Space.xs)) { pills }
            }
        } else {
            VStack(alignment: .trailing, spacing: CGFloat(ClomniTheme.Space.xs)) { pills }
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

/// background, 1 pt primarySoft border, primary text 14/500, radius 18, padding 7×13; up to two lines, then "…".
/// The tap target reaches 44 pt even where the pill is smaller.
struct PillButton: View {
    let title: String
    let accessibilityLabel: String
    let isBack: Bool
    let theme: ClomniTheme
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.pill), style: .continuous)
        Button(action: action) {
            Text(title)
                .clomniFont(ClomniTheme.FontSize.text, isBack ? .regular : .medium)
                .foregroundStyle(isBack ? theme.colors.textSecondary.color : theme.colors.primary.color)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.vertical, 7)
                .padding(.horizontal, 13)
                .background(shape.fill(theme.colors.background.color))
                .overlay(shape.stroke(isBack ? theme.colors.border.color : theme.colors.primarySoft.color, lineWidth: 1))
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .padding(.vertical, -6)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

/// Rows of children, right-aligned, wrapping when a row is full.
@available(iOS 16.0, *)
struct WrapLayout: Layout {
    var spacing: CGFloat

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
            var x = bounds.maxX - row.width
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
