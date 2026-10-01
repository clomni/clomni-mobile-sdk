#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// White strip with the top hairline above the safe area: the field (surface, radius 20, 38 high, up to 5 lines),
/// emoji and attach icons while it is empty, and the primary send button (34) once there is text. A step waiting
/// for a button locks it; a closed conversation offers a new one, and writing anyway reopens it.
struct ComposerView: View {
    let composer: ChatComposer
    let theme: ClomniTheme
    @Binding var text: String
    @Binding var writeAnyway: Bool
    let send: () -> Void
    let attach: () -> Void
    let startNew: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        content
            .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
            .padding(.vertical, CGFloat(ClomniTheme.Space.s))
            .background(theme.colors.background.color.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle().fill(theme.colors.border.color).frame(height: 1)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch composer.mode {
        case .locked(let hint):
            Text(hint)
                .clomniFont(13, relativeTo: .footnote)
                .foregroundStyle(theme.colors.textSecondary.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.input), style: .continuous)
                    .fill(theme.colors.surface.color))
        case .closed(let closed, let action) where !writeAnyway:
            HStack(spacing: CGFloat(ClomniTheme.Space.xs)) {
                Button {
                    writeAnyway = true
                    focused = true
                } label: {
                    Text(closed)
                        .foregroundStyle(theme.colors.textSecondary.color)
                        .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
                }
                Text(verbatim: "·").foregroundStyle(theme.colors.textSecondary.color).accessibilityHidden(true)
                Button(action: startNew) {
                    Text(action)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.colors.primary.color)
                        .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
                }
            }
            .clomniFont(13, relativeTo: .footnote)
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity)
        default:
            field
        }
    }

    private var canSend: Bool {
        ChatPresenter.canSend(text, limit: composer.limit)
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: CGFloat(ClomniTheme.Space.s)) {
            HStack(alignment: .center, spacing: CGFloat(ClomniTheme.Space.m)) {
                input
                if text.isEmpty {
                    if composer.showsEmoji {
                        iconButton("face.smiling", label: composer.emojiLabel) { focused = true }
                    }
                    if composer.showsAttach {
                        iconButton("paperclip", label: composer.attachLabel, action: attach)
                    }
                }
            }
            .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
            .padding(.vertical, CGFloat(ClomniTheme.Space.s))
            .frame(minHeight: 38)
            .background(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.input), style: .continuous)
                .fill(theme.colors.surface.color))
            if canSend {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.colors.onPrimary.color)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(theme.colors.primary.color))
                        .padding(5)
                        .contentShape(Rectangle())
                        .padding(-5)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(Text(composer.sendLabel))
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: canSend)
    }

    @ViewBuilder
    private var input: some View {
        if #available(iOS 16.0, *) {
            TextField(composer.placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .clomniFont(ClomniTheme.FontSize.text)
                .focused($focused)
        } else {
            TextField(composer.placeholder, text: $text)
                .clomniFont(ClomniTheme.FontSize.text)
                .focused($focused)
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19))
                .foregroundStyle(theme.colors.textSecondary.color)
                .padding(12)
                .contentShape(Rectangle())
                .padding(-12)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

/// The photo library (PHPicker: no permission prompt); hands back the picked image or nil.
struct PhotoPicker: UIViewControllerRepresentable {
    let pick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(pick: pick)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let pick: (UIImage?) -> Void

        init(pick: @escaping (UIImage?) -> Void) {
            self.pick = pick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                return pick(nil)
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let image = object as? UIImage
                DispatchQueue.main.async { self.pick(image) }
            }
        }
    }
}

enum ImagePreparation {
    /// JPEG with the longer side at most 2048 px (brief 8 · 5.5).
    static func jpeg(_ image: UIImage) -> Data? {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let target = Media.uploadSize(width: Double(pixels.width), height: Double(pixels.height))
        let size = CGSize(width: target.width, height: target.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
#endif
