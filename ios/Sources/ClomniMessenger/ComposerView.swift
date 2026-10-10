#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// A file picked for the next message, shown over the composer until it goes (or its × removes it).
struct StagedFile: Equatable {
    let data: Data
    let fileName: String
    let mime: String
    /// A picture's own small copy; nil shows the file icon.
    let preview: UIImage?
}

/// White, with a 1 pt line on top (DESIGN-PASS-2 11): the field (surface, radius 20, at least 44 high, up to 5 lines
/// then it scrolls) with the paper clip (24, pressed as a 40 pt circle) inside it, and right of it the round button
/// (CM-130, operator 2026-10-09, WhatsApp's layout; the emoji button went, the keyboard has emoji): the microphone
/// while there is nothing to send, the arrow once there is (`ComposerSendButton`). While a voice message is recorded
/// its bar takes the field's place (`VoiceRecordingBar`). A closed conversation offers a new one, and writing anyway
/// reopens it. A picked file waits above it as a 64 pt square with its ×. (While a flow waits for a choice the
/// conversation shows no composer at all.)
struct ComposerView: View {
    let composer: ChatComposer
    let theme: ClomniTheme
    @Binding var text: String
    @Binding var writeAnyway: Bool
    @Binding var staged: StagedFile?
    let send: () -> Void
    let attach: () -> Void
    let startNew: () -> Void
    /// The ✕ on the quote over the field.
    var cancelQuote: () -> Void = {}
    /// Voice messages (CM-130); no recorder: the app does not explain the microphone, the button is only the arrow.
    var recorder: VoiceRecorder?
    var playback: VoicePlayback?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.s)) {
            // The message being answered, over the field; it comes and goes by growing and fading.
            if let quote = composer.quote {
                QuoteStrip(quote: quote, cancelLabel: composer.cancelQuoteLabel, theme: theme, cancel: cancelQuote)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            if let staged, composer.mode == .open || writeAnyway {
                StagedPreview(file: staged, removeLabel: composer.removeAttachmentLabel, theme: theme) {
                    self.staged = nil
                }
            }
            content
        }
        .padding(.horizontal, CGFloat(ClomniTheme.Size.barEdge))
        .padding(.vertical, CGFloat(ClomniTheme.Space.s))
        .background(theme.colors.background.color.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.colors.border.color).frame(height: 1)
        }
        // The bar as a whole, for the UI tests that measure what stands over it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clomni.composer")
        .animation(reduceMotion ? nil : Motion.decelerate(0.22), value: composer.quote)
        // Answering puts the cursor in the field.
        .onChange(of: composer.quote?.messageId) { id in if id != nil { focused = true } }
    }

    @ViewBuilder
    private var content: some View {
        switch composer.mode {
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

    /// Text that may go, or a picked file.
    private var canSend: Bool {
        staged != nil || ChatPresenter.canSend(text, limit: composer.limit)
    }

    @ViewBuilder
    private var field: some View {
        if let recorder, let playback {
            VoiceComposerRow(recorder: recorder, playback: playback, theme: theme, strings: composer.texts, canSend: canSend,
                             send: send) { textField }
        } else {
            HStack(alignment: .bottom, spacing: CGFloat(ClomniTheme.Space.s)) {
                textField
                ComposerSendButton(canSend: canSend, recorder: nil, theme: theme, strings: composer.texts, send: send)
                    .accessibilityIdentifier("clomni.composer.send")
            }
        }
    }

    private var textField: some View {
        HStack(alignment: .center, spacing: CGFloat(ClomniTheme.Space.s)) {
            input
            if composer.showsAttach {
                iconButton("paperclip", label: composer.attachLabel, action: attach)
            }
        }
        .padding(.leading, CGFloat(ClomniTheme.Space.xl))
        .padding(.trailing, composer.showsAttach ? CGFloat(ClomniTheme.Space.xxs) : CGFloat(ClomniTheme.Space.xl))
        .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
        .background(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.input), style: .continuous)
            .fill(theme.colors.surface.color))
    }

    @ViewBuilder
    private var input: some View {
        // The placeholder is gone once something is written; the label stays.
        if #available(iOS 16.0, *) {
            TextField(composer.placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .clomniFont(ClomniTheme.FontSize.text)
                .focused($focused)
                .padding(.vertical, CGFloat(ClomniTheme.Space.s))
                .accessibilityLabel(Text(composer.placeholder))
                .accessibilityIdentifier("clomni.composer.field")
        } else {
            TextField(composer.placeholder, text: $text)
                .clomniFont(ClomniTheme.FontSize.text)
                .focused($focused)
                .padding(.vertical, CGFloat(ClomniTheme.Space.s))
                .accessibilityLabel(Text(composer.placeholder))
                .accessibilityIdentifier("clomni.composer.field")
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 24, height: 24)
                .foregroundStyle(theme.colors.textSecondary.color)
                .frame(width: 40, height: 40)
        }
        // The press is a 40 pt circle; the tap area stays 44.
        .buttonStyle(PressShapeStyle(shape: Circle()))
        .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
        .contentShape(Rectangle())
        .accessibilityLabel(Text(label))
    }
}

/// The field and the round button right of it; while a voice message is made, its bar in the field's place. Locked or
/// stopped, the bar has its own Send and the button goes; while the finger holds it stays, under the finger.
private struct VoiceComposerRow<Field: View>: View {
    @ObservedObject var recorder: VoiceRecorder
    let playback: VoicePlayback
    let theme: ClomniTheme
    let strings: ClomniStrings
    let canSend: Bool
    let send: () -> Void
    @ViewBuilder let field: () -> Field

    var body: some View {
        let state = recorder.state
        HStack(alignment: state.isHolding ? .top : .bottom, spacing: CGFloat(ClomniTheme.Space.s)) {
            if recorder.showsBar {
                VoiceRecordingBar(recorder: recorder, playback: playback, theme: theme, strings: strings)
            } else {
                field()
            }
            if !state.isLockedOrReview && !recorder.dropping {
                ComposerSendButton(canSend: canSend, recorder: recorder, theme: theme, strings: strings, send: send)
                    .accessibilityIdentifier(canSend ? "clomni.composer.send" : "clomni.composer.voice")
            }
        }
    }
}

private extension VoiceRecording.State {
    var isHolding: Bool {
        if case .holding = self { return true }
        return false
    }

    var isLockedOrReview: Bool {
        switch self {
        case .locked, .review: return true
        default: return false
        }
    }
}

/// The picked file before it goes: a 64 pt square (the picture, or the file icon on grey) with × on its corner.
struct StagedPreview: View {
    let file: StagedFile
    let removeLabel: String
    let theme: ClomniTheme
    let remove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let preview = file.preview {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 24))
                        .foregroundStyle(theme.colors.textSecondary.color)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.colors.surface.color)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.card), style: .continuous))
            .accessibilityLabel(Text(file.fileName))
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .offset(x: 14, y: -14)
            .accessibilityLabel(Text(removeLabel))
        }
        .padding(.top, CGFloat(ClomniTheme.Space.s))
    }
}

/// The attachment sheet (DESIGN-PASS-2 12): rows 56 high, a 24 pt icon and the text 16: the photo library, the
/// camera (only when the app may use it), any file. A grabber on top, no cancel: it is swiped down.
struct AttachmentSheet: View {
    let composer: ChatComposer
    let theme: ClomniTheme
    let cameraAvailable: Bool
    let pick: (AttachmentSource) -> Void

    var body: some View {
        VStack(spacing: 0) {
            row("photo.on.rectangle", composer.mediaLabel) { pick(.media) }
            if cameraAvailable {
                row("camera", composer.cameraLabel) { pick(.camera) }
            }
            row("doc", composer.fileLabel) { pick(.file) }
        }
        .padding(.top, CGFloat(ClomniTheme.Space.xxl))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background.color.ignoresSafeArea())
    }

    /// The sheet's height for its rows.
    static func height(rows: Int) -> CGFloat {
        CGFloat(rows) * 56 + CGFloat(ClomniTheme.Space.xxl) * 2
    }

    private func row(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CGFloat(ClomniTheme.Space.xl)) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .frame(width: 24, height: 24)
                Text(title)
                    .clomniFont(16, relativeTo: .body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.colors.textPrimary.color)
            .padding(.horizontal, CGFloat(ClomniTheme.Size.barEdge + 4))
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

enum AttachmentSource {
    case media, camera, file

    /// The camera, when the device has one and the app declared why it uses it (NSCameraUsageDescription); without
    /// that, the log says so (CameraOption).
    @MainActor
    static var cameraAvailable: Bool {
        CameraOption.offered(deviceHasCamera: UIImagePickerController.isSourceTypeAvailable(.camera),
                             usageDescription: Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription"))
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

/// The system's photo picker (PhotosPicker, iOS 16): a photo or a video, staged for the next message. On iOS 15 the
/// same picker comes as PHPicker (PhotoPicker), photos only.
struct MediaPicker: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var staged: StagedFile?

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.modifier(PhotosPickerModifier(isPresented: $isPresented, staged: $staged))
        } else {
            content
        }
    }
}

@available(iOS 16.0, *)
private struct PhotosPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var staged: StagedFile?
    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $item, matching: .any(of: [.images, .videos]))
            .onChange(of: item) { picked in
                guard let picked else { return }
                item = nil
                Task { @MainActor in
                    guard let data = try? await picked.loadTransferable(type: Data.self) else { return }
                    let type = picked.supportedContentTypes.first
                    if type?.conforms(to: .image) ?? true, let image = UIImage(data: data) {
                        staged = ImagePreparation.staged(image)
                    } else {
                        let ext = type?.preferredFilenameExtension ?? "mov"
                        staged = StagedFile(data: data, fileName: "video.\(ext)",
                                            mime: type?.preferredMIMEType ?? "video/quicktime", preview: nil)
                    }
                }
            }
    }
}

/// The camera (UIImagePickerController), for a photo; hands back the photo or nil.
struct CameraPicker: UIViewControllerRepresentable {
    let pick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(pick: pick)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let pick: (UIImage?) -> Void

        init(pick: @escaping (UIImage?) -> Void) {
            self.pick = pick
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            pick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            pick(nil)
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

    /// A picked picture as the file that goes, with its small copy for the composer.
    static func staged(_ image: UIImage) -> StagedFile? {
        guard let data = jpeg(image) else { return nil }
        return StagedFile(data: data, fileName: "image.jpg", mime: "image/jpeg", preview: image)
    }
}
#endif
