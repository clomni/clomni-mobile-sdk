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

/// A form as Intercom draws one: the bot's text in its bubble, then a card of its own under it (radius 16, 1 pt
/// border, padding 16). Labels 13 medium in the muted grey, "(istəyə görə)" after an optional one; fields 44 high on
/// the canvas grey without a border until focused (1.5 pt brand); fields 12 apart; the full-width brand "Göndər",
/// 44 high, 15 semibold. Sent, the card keeps only the values as lines and a small ✓.
struct FormCardView: View {
    let card: FormCard
    let theme: ClomniTheme
    let bubble: BubbleShape
    let bubbleFill: Color
    let submit: ([String: String]) async -> [String: String]
    @State private var values: [String: String] = [:]
    @State private var errors: [String: String] = [:]
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.s)) {
            if let text = card.text {
                Text(attributedText(text))
                    .clomniFont(ClomniTheme.FontSize.text)
                    .lineSpacing(3)
                    .foregroundStyle(theme.colors.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, CGFloat(ClomniTheme.Space.s))
                    .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
                    .background(bubble.fill(bubbleFill))
            }
            VStack(alignment: .leading, spacing: 12) {
                if card.readOnly && !card.submitted.isEmpty {
                    ForEach(card.submitted, id: \.label) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.label)
                                .clomniFont(13, .medium, relativeTo: .caption)
                                .foregroundStyle(theme.colors.textSecondary.color)
                            Text(line.value)
                                .clomniFont(ClomniTheme.FontSize.text)
                                .foregroundStyle(theme.colors.textPrimary.color)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let sent = card.sentLabel {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.colors.textSecondary.color)
                            .accessibilityLabel(Text(sent))
                    }
                } else {
                    ForEach(card.fields) { field in
                        FormFieldView(field: field, value: binding(field.id), error: errors[field.id],
                                      disabled: card.readOnly, theme: theme)
                    }
                    if !card.readOnly {
                        Button(action: send) {
                            Text(card.submitTitle)
                                .clomniFont(15, .semibold)
                                .foregroundStyle(theme.colors.onPrimary.color)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.colors.primary.color))
                        }
                        .buttonStyle(PressShapeStyle(shape: RoundedRectangle(cornerRadius: 10, style: .continuous)))
                        .disabled(sending)
                        .opacity(sending ? 0.6 : 1)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.colors.background.color))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.colors.border.color, lineWidth: 1))
        }
        .onAppear {
            if values.isEmpty {
                values = Dictionary(card.fields.map { ($0.id, $0.initialValue) }, uniquingKeysWith: { first, _ in first })
            }
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { value in
            values[key] = value
            errors[key] = nil
        })
    }

    private func send() {
        sending = true
        Task { @MainActor in
            errors = await submit(values)
            sending = false
            if let first = card.announcement(for: errors) {
                UIAccessibility.post(notification: .announcement, argument: first)
            }
        }
    }
}

/// One field by its type: text, textarea, phone, email, number, select, date.
struct FormFieldView: View {
    let field: FormCard.Field
    @Binding var value: String
    let error: String?
    let disabled: Bool
    let theme: ClomniTheme

    private static let dates: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    @FocusState private var focused: Bool

    private var edge: Color {
        if error != nil { return theme.colors.unread.color }
        return focused ? theme.colors.primary.color : .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.shownLabel)
                .clomniFont(13, .medium, relativeTo: .caption)
                .foregroundStyle(theme.colors.textSecondary.color)
                // The input carries it, with "məcburi" for a required one.
                .accessibilityHidden(true)
            input
                .focused($focused)
                .clomniFont(ClomniTheme.FontSize.text)
                .foregroundStyle(theme.colors.textPrimary.color)
                .padding(.horizontal, CGFloat(ClomniTheme.Space.m))
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.colors.canvas.color))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(edge, lineWidth: 1.5))
                .animation(.easeOut(duration: 0.15), value: focused)
                .accessibilityLabel(Text(field.accessibilityLabel))
                .accessibilityHint(Text(error ?? ""))
            if let error {
                // Read with the input, and announced when the submit comes back.
                Text(error)
                    .clomniFont(ClomniTheme.FontSize.label, relativeTo: .caption)
                    .foregroundStyle(theme.colors.unread.color)
                    .accessibilityHidden(true)
            }
        }
        .disabled(disabled)
    }

    @ViewBuilder
    private var input: some View {
        switch field.type {
        case .textarea:
            TextEditor(text: $value)
                .frame(minHeight: 72)
                .padding(.vertical, CGFloat(ClomniTheme.Space.xs))
        case .select:
            Menu {
                ForEach(field.options, id: \.value) { option in
                    Button(option.label) { value = option.value }
                }
            } label: {
                HStack {
                    Text(field.options.first { $0.value == value }?.label ?? field.placeholder ?? "")
                        .foregroundStyle(value.isEmpty ? theme.colors.textSecondary.color : theme.colors.textPrimary.color)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .foregroundStyle(theme.colors.textSecondary.color)
                }
                .frame(maxWidth: .infinity, minHeight: CGFloat(ClomniTheme.Size.touchTarget))
                .contentShape(Rectangle())
            }
        case .date:
            DatePicker("", selection: Binding(
                get: { Self.dates.date(from: value) ?? Date() },
                set: { value = Self.dates.string(from: $0) }), displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .phone:
            TextField(field.placeholder ?? "", text: $value)
                .keyboardType(.phonePad)
                .disableAutocorrection(true)
                .textContentType(.telephoneNumber)
        case .email:
            TextField(field.placeholder ?? "", text: $value)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        case .number:
            TextField(field.placeholder ?? "", text: $value)
                .keyboardType(.decimalPad)
        case .text:
            TextField(field.placeholder ?? "", text: $value)
                .textContentType(field.id == "name" ? .name : nil)
        }
    }
}
#endif
