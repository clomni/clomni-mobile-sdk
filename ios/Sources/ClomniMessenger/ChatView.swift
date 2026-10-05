#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// Hands the controller's screen to SwiftUI.
@MainActor
final class ChatModel: ObservableObject {
    @Published private(set) var screen: ChatScreen
    @Published private(set) var config: MessengerConfig?
    let controller: ChatController

    init(controller: ChatController) {
        self.controller = controller
        screen = controller.screen
        config = controller.config
        controller.onChange = { [weak self] in self?.sync() }
        controller.playSound = { MessageSounds.play($0) }
    }

    convenience init(engine: ClomniEngine, conversationId: String, language: String?, known: [String: String] = [:]) {
        self.init(controller: ChatController(source: engine, conversationId: conversationId, language: language,
                                             known: known))
    }

    private func sync() {
        screen = controller.screen
        config = controller.config
    }
}

/// The conversation (brief 8 · 7.4): header, the transcript scrolled to its end, the composer.
struct ChatView: View {
    @ObservedObject var model: ChatModel
    let back: () -> Void
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clomniThemeOverride) private var themeOverride
    @State private var draft = ""
    @State private var writeAnyway = false
    @State private var choosingAttachment = false
    @State private var pickingPhoto = false
    @State private var showingPhotos = false
    @State private var pickingCamera = false
    @State private var pickingFile = false
    @State private var staged: StagedFile?
    @State private var screenWidth: CGFloat = 390
    private var composerShown: Bool {
        if case .hidden = model.screen.composer.mode { return false }
        return true
    }

    /// The transcript has moved under the bar: its line shows.
    @State private var scrolled = false
    /// The transcript has been scrolled to its end once.
    @State private var atBottom = false
    @State private var fullScreenImage: ImageURL?
    @State private var refusal: String?
    @State private var announced: String?
    @State private var hasOlder = true
    @State private var loadingOlder = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ClomniTheme {
        ClomniTheme.make(config: model.config, systemIsDark: colorScheme == .dark, override: themeOverride)
    }

    private var actions: ChatActions {
        let controller = model.controller
        return ChatActions(
            tap: { buttonId, messageId in Task { @MainActor in await controller.tap(buttonId, in: messageId) } },
            submit: { messageId, values in await controller.submit(messageId, values: values) },
            retry: { clientId in Task { @MainActor in await controller.retrySending(clientId) } },
            openImage: { url in fullScreenImage = ImageURL(url: url) })
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(header: model.screen.header, theme: theme, showsDivider: scrolled, back: back, close: close)
            if let offline = model.screen.offline {
                OfflineStrip(text: offline, theme: theme)
            }
            transcript
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // While a flow waits for a choice there is no composer at all (operator, 2026-10-04): the choices stand at
            // the end of the conversation. It comes back, sliding up and fading in over 200 ms, when the flow takes
            // text, ends, or an operator joins.
            if composerShown {
                ComposerView(composer: model.screen.composer, theme: theme, text: $draft, writeAnyway: $writeAnyway,
                             staged: $staged, send: send, attach: { choosingAttachment = true }, startNew: startNew)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(theme.colors.background.color.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: composerShown)
        .environment(\.clomniLoadingLabel, model.screen.loadingLabel)
        .environment(\.clomniScreenWidth, screenWidth)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { screenWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { screenWidth = $0 }
        })
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .configCrossfade(model.config)
        .task { await model.controller.load() }
        .onDisappear { Task { await model.controller.stop() } }
        .onChange(of: draft) { text in Task { await model.controller.textChanged(text) } }
        .onChange(of: model.screen.announcement) { announcement in announce(announcement) }
        .sheet(isPresented: $choosingAttachment) {
            attachmentSheet
        }
        .modifier(MediaPicker(isPresented: $showingPhotos, staged: $staged))
        .sheet(isPresented: $pickingPhoto) {
            PhotoPicker { image in
                pickingPhoto = false
                staged = image.flatMap(ImagePreparation.staged)
            }
        }
        .fullScreenCover(isPresented: $pickingCamera) {
            CameraPicker { image in
                pickingCamera = false
                staged = image.flatMap(ImagePreparation.staged)
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            stageFile(at: url)
        }
        .fullScreenCover(item: $fullScreenImage) { image in
            FullScreenImage(url: image.url, closeLabel: model.screen.header.closeLabel, theme: theme) {
                fullScreenImage = nil
            }
        }
        .alert(refusal ?? "", isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var transcript: some View {
        switch model.screen.phase {
        case .loading:
            // Nothing cached: the spinner in the middle, once the load takes a while.
            LoadingIndicator(loading: true, label: model.screen.loadingLabel, theme: theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack {
                if let failure = model.screen.failure {
                    FailureView(failure: failure, theme: theme) {
                        Task { @MainActor in await model.controller.retry() }
                    }
                }
                Spacer()
            }
            .padding(CGFloat(ClomniTheme.Space.xl))
        case .ready:
            ScrollViewReader { proxy in
                ScrollView {
                    // Older messages on their way: a small spinner at the top of the list.
                    if loadingOlder {
                        LoadingIndicator(loading: loadingOlder, label: model.screen.loadingLabel, theme: theme, size: 20)
                            .padding(.top, CGFloat(ClomniTheme.Space.s))
                    }
                    GeometryReader { proxy in
                        Color.clear.preference(key: ScrollTopOffset.self,
                                               value: proxy.frame(in: .named(ScrollTopOffset.space)).minY)
                    }
                    .frame(height: 0)
                    ChatTranscript(items: model.screen.items, theme: theme, actions: actions, reachedTop: loadOlder)
                        .onAppear {
                            if let last = model.screen.items.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                            // Shown once it stands at its end: the first frame is the bottom, nothing slides.
                            DispatchQueue.main.async { atBottom = true }
                        }
                }
                .coordinateSpace(name: ScrollTopOffset.space)
                .onPreferenceChange(ScrollTopOffset.self) { top in scrolled = top < -1 }
                .opacity(atBottom ? 1 : 0)
                .onChange(of: model.screen.items.last?.id) { last in
                    guard let last else { return }
                    // Reduce Motion: the transcript jumps to the new message instead of sliding.
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    /// The attachment sheet at its rows' height; iOS 15 shows it at its full height.
    @ViewBuilder
    private var attachmentSheet: some View {
        let camera = AttachmentSource.cameraAvailable
        let sheet = AttachmentSheet(composer: model.screen.composer, theme: theme, cameraAvailable: camera) { source in
            choosingAttachment = false
            // The next sheet once this one is gone.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                switch source {
                case .media:
                    if #available(iOS 16.0, *) { showingPhotos = true } else { pickingPhoto = true }
                case .camera: pickingCamera = true
                case .file: pickingFile = true
                }
            }
        }
        if #available(iOS 16.0, *) {
            sheet
                .presentationDetents([.height(AttachmentSheet.height(rows: camera ? 3 : 2))])
                .presentationDragIndicator(.visible)
        } else {
            sheet
        }
    }

    /// The text, or a picked file with the text as its caption.
    private func send() {
        let text = draft
        if let file = staged {
            let caption = text.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                refusal = await model.controller.sendFile(file.data, fileName: file.fileName, mime: file.mime,
                                                          caption: caption.isEmpty ? nil : caption)
                if refusal == nil {
                    staged = nil
                    if draft == text { draft = "" }
                }
            }
            return
        }
        Task { @MainActor in
            if await model.controller.send(text), draft == text { draft = "" }
        }
    }

    /// Scrolling to the top fetches the page before it, until the beginning.
    private func loadOlder() {
        guard hasOlder, !loadingOlder else { return }
        loadingOlder = true
        Task { @MainActor in
            hasOlder = await model.controller.loadOlder()
            loadingOlder = false
        }
    }

    private func startNew() {
        writeAnyway = false
        Task { @MainActor in
            await model.controller.startNewConversation()
        }
    }

    private func stageFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let preview = mime.hasPrefix("image/") ? UIImage(data: data) : nil
        staged = StagedFile(data: data, fileName: url.lastPathComponent, mime: mime, preview: preview)
    }

    /// VoiceOver reads a new incoming message; the ones there when the screen opened are not news.
    private func announce(_ announcement: Announcement?) {
        guard let announcement else { return }
        defer { announced = announcement.id }
        guard announced != nil, announced != announcement.id else { return }
        UIAccessibility.post(notification: .announcement, argument: announcement.text)
    }
}

struct ImageURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The conversation's bar, one fixed height whatever it shows (DESIGN-PASS-2 10): back, the avatar (32), the name
/// 17 semibold with the subtitle 13 under it (its line kept even when empty), and ✕ as on every screen. Nothing in it
/// changes size when the subtitle, typing or loading changes, so the transcript under it does not move.
struct ChatHeaderView: View {
    let header: ChatHeader
    let theme: ClomniTheme
    var showsDivider = false
    let back: () -> Void
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScreenBar(closeLabel: header.closeLabel, theme: theme, close: close) {
            HStack(spacing: CGFloat(ClomniTheme.Space.s)) {
                CircleBackButton(label: header.backLabel, theme: theme, action: back)
                // The company until an operator joins, then the operator: a 200 ms crossfade between the two.
                ZStack {
                    who
                        .id(whoKey)
                        .transition(.opacity)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: whoKey)
            }
        }
        .background(theme.colors.background.color.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            // The line only once the transcript has scrolled under the bar.
            Rectangle().fill(theme.colors.border.color).frame(height: 1).opacity(showsDivider ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.15), value: showsDivider)
    }

    private var whoKey: String {
        if case .person = header.lead { return "person \(header.title)" }
        return "brand"
    }

    private var who: some View {
            HStack(spacing: CGFloat(ClomniTheme.Space.s)) {
                lead
                    .frame(width: CGFloat(ClomniTheme.Size.headerLead), height: CGFloat(ClomniTheme.Size.headerLead))
                VStack(alignment: .leading, spacing: 0) {
                    Text(header.title)
                        .clomniFont(ClomniTheme.FontSize.brand, .semibold, relativeTo: .headline)
                        .foregroundStyle(theme.colors.textPrimary.color)
                        .lineLimit(1)
                    Text(header.subtitle.isEmpty ? " " : header.subtitle)
                        .clomniFont(13, relativeTo: .footnote)
                        .foregroundStyle(theme.colors.textSecondary.color)
                        .lineLimit(1)
                }
                // Both lines' place, at the text size the user chose, never more or less.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
    }

    /// The team's avatars, or the operator with the green dot: both in the same 32 pt.
    @ViewBuilder
    private var lead: some View {
        switch header.lead {
        case .brand(let logo):
            ChatAvatarView(avatar: logo, size: ClomniTheme.Size.headerLead, theme: theme)
                .accessibilityHidden(true)
        case .person(let avatar, let online):
            ChatAvatarView(avatar: avatar, size: ClomniTheme.Size.headerLead, theme: theme)
                .overlay(alignment: .bottomTrailing) {
                    if online {
                        Circle()
                            .fill(theme.colors.online.color)
                            .frame(width: CGFloat(ClomniTheme.Size.tabDot), height: CGFloat(ClomniTheme.Size.tabDot))
                            .overlay(Circle().stroke(theme.colors.background.color, lineWidth: 2))
                            .offset(x: 1, y: 1)
                    }
                }
                .accessibilityHidden(true)
        }
    }
}

/// An image on black, fitted to the screen, with ✕.
struct FullScreenImage: View {
    let url: URL
    let closeLabel: String
    let theme: ClomniTheme
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            // Black until it loads: no spinner (brief 8 · 7.5).
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScreenBar(closeLabel: closeLabel, closeStyle: .onBrand, theme: theme, close: close) { EmptyView() }
        }
    }
}
#endif
