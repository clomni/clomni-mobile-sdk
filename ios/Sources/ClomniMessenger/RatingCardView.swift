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

/// A rating as the web widget asks it (CM-087), drawn like a form: the bot's question in its bubble, then a card of its
/// own (radius 16, 1 pt border, padding 16) with five faces or five stars, each a 44 pt target. With no comment to
/// write a choice goes at once; otherwise the choice stays lit and the comment field (a form's textarea) and the brand
/// "Göndər" open under it. Sent, the choice stays lit, the others step back and the thanks shows under them.
struct RatingCardView: View {
    let card: RatingCard
    let theme: ClomniTheme
    let bubble: BubbleShape
    let bubbleFill: Color
    /// The time, in the corner of the question (G7).
    let stamp: BubbleStamp
    let rate: (_ score: Int, _ comment: String?) async -> Void
    /// The comment field's key (`FormCardView.fieldKey`) and whether it has the focus.
    let focus: (String, Bool) -> Void
    @State private var chosen: Int?
    @State private var comment = ""
    @State private var sending = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `chosen`: a choice already made, for snapshots of the open field.
    init(card: RatingCard, theme: ClomniTheme, bubble: BubbleShape, bubbleFill: Color, stamp: BubbleStamp,
         rate: @escaping (_ score: Int, _ comment: String?) async -> Void,
         focus: @escaping (String, Bool) -> Void = { _, _ in }, chosen: Int? = nil) {
        self.card = card
        self.theme = theme
        self.bubble = bubble
        self.bubbleFill = bubbleFill
        self.stamp = stamp
        self.rate = rate
        self.focus = focus
        _chosen = State(initialValue: chosen)
    }

    private var isOpen: Bool { card.state == .open }

    /// The face or star lit: the score sent, else the choice being made.
    private var lit: Int? {
        if case .sent(let score, _) = card.state { return score }
        return chosen
    }

    private var fieldKey: String { FormCardView.fieldKey(card.messageId, "comment") }

    private var canSend: Bool {
        card.commentField?.required != true || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.s)) {
            StampedText(text: attributedText(card.text), size: ClomniTheme.FontSize.text, stamp: stamp, theme: theme)
                .lineSpacing(3)
                .foregroundStyle(theme.colors.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, CGFloat(ClomniTheme.Space.s))
                .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
                .background(bubble.fill(bubbleFill))
            VStack(alignment: .leading, spacing: 12) {
                if isOpen {
                    HStack(spacing: 0) {
                        ForEach(card.options) { option in
                            Button { choose(option.score) } label: { symbol(option) }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(sending)
                                .accessibilityLabel(Text(option.accessibilityLabel))
                                .accessibilityAddTraits(lit == option.score ? .isSelected : [])
                                .accessibilityIdentifier("clomni.rating.\(option.score)")
                        }
                    }
                    if chosen != nil, let field = card.commentField {
                        commentArea(field)
                            .transition(.opacity)
                    }
                } else {
                    // Sent: one element that says what was given, the comment and the thanks.
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 0) {
                            ForEach(card.options) { symbol($0) }
                        }
                        if case .sent(_?, let comment) = card.state {
                            sentNote(comment)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(card.sentAccessibilityLabel ?? ""))
                    .accessibilityHidden(card.sentAccessibilityLabel == nil)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.colors.background.color))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.colors.border.color, lineWidth: 1))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: chosen)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isOpen)
        }
        .onChange(of: isOpen) { open in
            // It failed: back to how it was before it went (with no comment to write, nothing chosen).
            guard open else { return }
            sending = false
            if card.commentField == nil { chosen = nil }
        }
    }

    /// A face on a soft brand circle when lit, the others fading once one is; or a star, filled up to the score.
    @ViewBuilder
    private func symbol(_ option: RatingCard.Option) -> some View {
        Group {
            if let face = option.face {
                let isLit = lit == option.score
                Text(verbatim: face)
                    .font(.system(size: 28))
                    .scaleEffect(isLit ? 1.08 : 1)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(isLit ? theme.colors.primarySoft.color : .clear))
                    .opacity(lit == nil || isLit ? 1 : 0.4)
            } else {
                let filled = (lit ?? 0) >= option.score
                Image(systemName: filled ? "star.fill" : "star")
                    .font(.system(size: 26))
                    .foregroundStyle(filled ? theme.colors.primary.color : theme.colors.textSecondary.color.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, minHeight: CGFloat(ClomniTheme.Size.touchTarget))
        .contentShape(Rectangle())
    }

    private func commentArea(_ field: FormCard.Field) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FormFieldView(field: field, value: $comment, error: nil, disabled: sending, theme: theme) {
                focus(fieldKey, $0)
            }
            // What the list scrolls to over the keyboard: the field and 12 under it (G4).
            .padding(.bottom, 12)
            .id(fieldKey)
            .padding(.bottom, -12)
            Button {
                if let chosen { send(chosen) }
            } label: {
                Text(card.submitTitle)
                    .clomniFont(15, .semibold)
                    .foregroundStyle(theme.colors.onPrimary.color)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.colors.primary.color))
            }
            .buttonStyle(PressShapeStyle(shape: RoundedRectangle(cornerRadius: 10, style: .continuous)))
            .disabled(sending || !canSend)
            .opacity(sending || !canSend ? 0.6 : 1)
            .accessibilityIdentifier("clomni.rating.submit")
        }
    }

    /// The comment as sent, then a small ✓ and the thanks.
    private func sentNote(_ comment: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let comment {
                Text(verbatim: comment)
                    .clomniFont(ClomniTheme.FontSize.text)
                    .foregroundStyle(theme.colors.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                Text(card.thanks)
                    .clomniFont(13, .medium, relativeTo: .caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(theme.colors.textSecondary.color)
        }
    }

    private func choose(_ score: Int) {
        Haptics.light()
        if card.commentField == nil {
            send(score)
        } else {
            chosen = score
        }
    }

    private func send(_ score: Int) {
        chosen = score
        sending = true
        let text = card.commentField == nil ? nil : comment
        // The field goes with the open card: the list stops keeping it over the keyboard.
        focus(fieldKey, false)
        Task { @MainActor in
            await rate(score, text)
            sending = false
        }
    }
}
#endif
