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

/// A form in a bot bubble: label 12/600, inputs with radius 10, errors in red under their field, a full-width
/// primary "Göndər". Once sent it shows what was sent and "Göndərildi".
struct FormCardView: View {
    let card: FormCard
    let theme: ClomniTheme
    let submit: ([String: String]) async -> [String: String]
    @State private var values: [String: String] = [:]
    @State private var errors: [String: String] = [:]
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.m)) {
            if let text = card.text {
                Text(attributedText(text))
                    .clomniFont(ClomniTheme.FontSize.text)
                    .foregroundStyle(theme.colors.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if card.readOnly && !card.submitted.isEmpty {
                ForEach(card.submitted, id: \.label) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.label)
                            .clomniFont(ClomniTheme.FontSize.label, .semibold, relativeTo: .caption)
                            .foregroundStyle(theme.colors.textSecondary.color)
                        Text(line.value)
                            .clomniFont(ClomniTheme.FontSize.text)
                            .foregroundStyle(theme.colors.textPrimary.color)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let sent = card.sentLabel {
                    Label(sent, systemImage: "checkmark")
                        .clomniFont(ClomniTheme.FontSize.label, relativeTo: .caption)
                        .foregroundStyle(theme.colors.textSecondary.color)
                }
            } else {
                ForEach(card.fields) { field in
                    FormFieldView(field: field, value: binding(field.id), error: errors[field.id],
                                  disabled: card.readOnly, theme: theme)
                }
                if !card.readOnly {
                    Button(action: send) {
                        Text(card.submitTitle)
                            .clomniFont(ClomniTheme.FontSize.text, .semibold)
                            .foregroundStyle(theme.colors.onPrimary.color)
                            .frame(maxWidth: .infinity, minHeight: CGFloat(ClomniTheme.Size.touchTarget))
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(theme.colors.primary.color))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(sending)
                    .opacity(sending ? 0.6 : 1)
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.required ? "\(field.label) *" : field.label)
                .clomniFont(ClomniTheme.FontSize.label, .semibold, relativeTo: .caption)
                .foregroundStyle(theme.colors.textPrimary.color)
            input
                .clomniFont(ClomniTheme.FontSize.text)
                .foregroundStyle(theme.colors.textPrimary.color)
                .padding(.horizontal, CGFloat(ClomniTheme.Space.m))
                .padding(.vertical, CGFloat(ClomniTheme.Space.xs))
                .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.colors.background.color))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(error == nil ? theme.colors.border.color : theme.colors.unread.color, lineWidth: 1))
                .accessibilityLabel(Text(field.label))
            if let error {
                Text(error)
                    .clomniFont(ClomniTheme.FontSize.label, relativeTo: .caption)
                    .foregroundStyle(theme.colors.unread.color)
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
