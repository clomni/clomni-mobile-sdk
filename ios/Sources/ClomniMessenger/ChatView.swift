#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
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
    @State private var pickingFile = false
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
            ChatHeaderView(header: model.screen.header, theme: theme, back: back, close: close)
            if let offline = model.screen.offline {
                OfflineStrip(text: offline, theme: theme)
            }
            transcript
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ComposerView(composer: model.screen.composer, theme: theme, text: $draft, writeAnyway: $writeAnyway,
                         send: send, attach: { choosingAttachment = true }, startNew: startNew)
        }
        .background(theme.colors.background.color.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .configCrossfade(model.config)
        .task { await model.controller.load() }
        .onDisappear { Task { await model.controller.stop() } }
        .onChange(of: draft) { text in Task { await model.controller.textChanged(text) } }
        .onChange(of: model.screen.announcement) { announcement in announce(announcement) }
        .confirmationDialog(model.screen.composer.attachLabel, isPresented: $choosingAttachment) {
            Button(model.screen.composer.imageLabel) { pickingPhoto = true }
            Button(model.screen.composer.fileLabel) { pickingFile = true }
        }
        .sheet(isPresented: $pickingPhoto) {
            PhotoPicker { image in
                pickingPhoto = false
                guard let image, let data = ImagePreparation.jpeg(image) else { return }
                Task { @MainActor in
                    refusal = await model.controller.sendFile(data, fileName: "image.jpg", mime: "image/jpeg")
                }
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            sendFile(at: url)
        }
        .fullScreenCover(item: $fullScreenImage) { image in
            FullScreenImage(url: image.url, closeLabel: model.screen.header.closeLabel) { fullScreenImage = nil }
        }
        .alert(refusal ?? "", isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var transcript: some View {
        switch model.screen.phase {
        case .loading:
            VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.s)) {
                SkeletonBlock(height: 38, theme: theme).frame(width: 200)
                SkeletonBlock(height: 58, theme: theme).frame(width: 222)
                SkeletonBlock(height: 38, theme: theme).frame(width: 160)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Spacer()
            }
            .padding(CGFloat(ClomniTheme.Space.xl))
            .loadingElement(model.screen.loadingLabel)
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
                    ChatTranscript(items: model.screen.items, theme: theme, actions: actions, reachedTop: loadOlder)
                        .onAppear {
                            if let last = model.screen.items.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                        }
                }
                .onChange(of: model.screen.items.last?.id) { last in
                    guard let last else { return }
                    // Reduce Motion: the transcript jumps to the new message instead of sliding.
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func send() {
        let text = draft
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

    private func sendFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let name = url.lastPathComponent
        Task { @MainActor in
            refusal = await model.controller.sendFile(data, fileName: name, mime: mime)
        }
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

/// White bar with the bottom hairline: the brand-coloured back arrow, who answers (team avatars 24, or the operator
/// 28 with the green dot), title 14.5/600 and the grey line 12 under it, ✕.
struct ChatHeaderView: View {
    let header: ChatHeader
    let theme: ClomniTheme
    let back: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: CGFloat(ClomniTheme.Space.m)) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.primary.color)
                    .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, -14)
            .padding(.trailing, -10)
            .accessibilityLabel(Text(header.backLabel))
            lead
            VStack(alignment: .leading, spacing: 0) {
                Text(header.title)
                    .clomniFont(ClomniTheme.FontSize.title, .semibold, relativeTo: .headline)
                    .foregroundStyle(theme.colors.textPrimary.color)
                    .lineLimit(1)
                Text(header.subtitle)
                    .clomniFont(ClomniTheme.FontSize.label, relativeTo: .caption)
                    .foregroundStyle(theme.colors.textSecondary.color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            CloseButton(label: header.closeLabel, color: theme.colors.textSecondary, edge: CGFloat(ClomniTheme.Space.xl),
                        action: close)
        }
        .padding(.horizontal, CGFloat(ClomniTheme.Space.xl))
        .padding(.bottom, CGFloat(ClomniTheme.Space.m))
        .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
        .background(theme.colors.background.color.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.border.color).frame(height: 1)
        }
    }

    @ViewBuilder
    private var lead: some View {
        switch header.lead {
        case .team(let urls):
            TeamAvatars(urls: urls, ring: theme.colors.background, theme: theme)
        case .person(let avatar, let online):
            ChatAvatarView(avatar: avatar, size: ClomniTheme.Size.avatar, theme: theme)
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
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
            CloseButton(label: closeLabel, color: .white, action: close)
        }
    }
}
#endif
