#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

// DESIGN-PASS-3 F2: answering a message. A swipe to the right or "Cavabla" in the long-press menu quotes it over the
// field; the bubble shows the server's quote at its top, and a tap on it scrolls to the quoted message.

/// Who wrote the quoted message (semibold) over its excerpt, as one text.
private func quoteText(_ quote: Bubble.Quote, excerpt: Color) -> Text {
    let line = Text(quote.excerpt).foregroundColor(excerpt)
    return quote.author.isEmpty ? line : Text(quote.author).fontWeight(.semibold) + Text(verbatim: "\n") + line
}

/// Inside the bubble, at its top: who wrote the quoted message and two lines of it, on the text colour at 6% (radius
/// 10). On the user's brand-coloured bubble the "text" is the colour on it, so its tint is a little stronger there.
struct QuoteBlock: View {
    let quote: Bubble.Quote
    let ink: Color
    let outgoing: Bool
    let jump: (String) -> Void

    var body: some View {
        Button { jump(quote.messageId) } label: {
            quoteText(quote, excerpt: ink.opacity(outgoing ? 0.85 : 0.7))
                .clomniFont(13, relativeTo: .footnote)
                .foregroundStyle(ink)
                .lineLimit(quote.author.isEmpty ? 2 : 3)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 48, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ink.opacity(outgoing ? 0.16 : 0.06)))
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text(verbatim: "\(quote.author): \(quote.excerpt)"))
    }
}

/// Over the field while answering: the brand's 3 pt line, who wrote it (13 semibold), one line of it, and ✕.
struct QuoteStrip: View {
    let quote: Bubble.Quote
    let cancelLabel: String
    let theme: ClomniTheme
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            quoteText(quote, excerpt: theme.colors.textSecondary.color)
                .clomniFont(13, relativeTo: .footnote)
                .foregroundStyle(theme.colors.textPrimary.color)
                .lineLimit(2)
                .padding(.leading, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) { Rectangle().fill(theme.colors.primary.color).frame(width: 3) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(quote.author): \(quote.excerpt)"))
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary.color)
                    .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
            }
            .buttonStyle(PressShapeStyle(shape: Circle()))
            .accessibilityLabel(Text(cancelLabel))
        }
    }
}

/// The reply arrow behind a swiped bubble: it fades and grows in as the drag nears the threshold.
struct ReplyArrow: View {
    let pulled: CGFloat
    let theme: ClomniTheme

    var body: some View {
        let progress = min(max(pulled / SwipeToReply.threshold, 0), 1)
        Image(systemName: "arrowshape.turn.up.left.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.colors.textSecondary.color)
            .frame(width: 28, height: 28)
            .background(Circle().fill(theme.colors.surface.color))
            .scaleEffect(0.6 + 0.4 * progress)
            .opacity(progress)
            .accessibilityHidden(true)
    }
}

/// A drag to the right answers the message: the row follows the finger (with some resistance), a light tick at the
/// threshold, and it springs back. A drag that starts vertical stays the list's.
struct SwipeToReply: ViewModifier {
    let enabled: Bool
    @Binding var pulled: CGFloat
    let reply: () -> Void
    @State private var horizontal: Bool?

    /// How far a bubble is dragged before letting go answers it.
    static let threshold: CGFloat = 56

    func body(content: Content) -> some View {
        content
            .offset(x: pulled)
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged(changed).onEnded { _ in ended() },
                                 including: enabled ? .all : .subviews)
    }

    private func changed(_ value: DragGesture.Value) {
        let move = value.translation
        if horizontal == nil { horizontal = move.width > abs(move.height) }
        guard horizontal == true else { return }
        let before = pulled
        pulled = min(max(move.width * 0.7, 0), Self.threshold + 24)
        if before < Self.threshold, pulled >= Self.threshold { Haptics.light() }
    }

    private func ended() {
        if horizontal == true, pulled >= Self.threshold { reply() }
        horizontal = nil
        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { pulled = 0 }
    }
}

/// A long press: "Cavabla" (while there is a composer) and "Kopyala" (when there is text). VoiceOver has the same
/// two as actions of the bubble.
struct MessageMenu: ViewModifier {
    let bubble: Bubble
    let actions: ChatActions

    private var replyId: String? { bubble.replyable ? bubble.messageId : nil }

    @ViewBuilder
    func body(content: Content) -> some View {
        if replyId == nil && bubble.copyText == nil {
            content
        } else {
            content
                .contextMenu {
                    if let replyId { Button(actions.replyLabel) { actions.reply(replyId) } }
                    if let text = bubble.copyText { Button(actions.copyLabel) { UIPasteboard.general.string = text } }
                }
                .modifier(NamedAction(name: actions.replyLabel, run: replyId.map { id in { actions.reply(id) } }))
                .modifier(NamedAction(name: actions.copyLabel,
                                      run: bubble.copyText.map { text in { UIPasteboard.general.string = text } }))
        }
    }
}

/// A VoiceOver action, when there is one to run.
private struct NamedAction: ViewModifier {
    let name: String
    let run: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let run { content.accessibilityAction(named: Text(name), run) } else { content }
    }
}

/// The light tick of a swipe's threshold and of a choice (M5).
enum Haptics {
    @MainActor static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
#endif
