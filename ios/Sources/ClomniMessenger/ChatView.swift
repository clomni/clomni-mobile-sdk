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
        NetworkMonitor.shared.follow(controller) { $0.isOffline = $1 }
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
    /// The bubble a tapped quote led to, lit for a second.
    @State private var lit: String?
    /// The form field with the focus (`FormCardView.fieldKey`), kept over the keyboard.
    @State private var focusedField: String?
    /// The transcript's height: when the keyboard takes some of it, the list goes up with the keyboard.
    @State private var viewport: CGFloat = 0
    /// How far the keyboard reaches into the screen (`KeyboardProbe`): the screen ends that much higher (H1).
    @State private var keyboard: CGFloat = 0
    /// Where the end of the list is, from the transcript's top edge; it changes with every scrolled frame, so it is
    /// kept out of the view's state.
    @State private var listEnd = Measure()
    /// The user is within `followWithin` of the end. Decided when the list scrolls, not when it grows: a long message
    /// arriving does not make the user "far" from an end they were at.
    @State private var nearEnd = true
    /// A message came while the user read further up: "Yeni mesaj ↓" shows (H2).
    @State private var unseen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ClomniTheme {
        ClomniTheme.make(config: model.config, systemIsDark: colorScheme == .dark, override: themeOverride)
    }

    private func actions(_ proxy: ScrollViewProxy) -> ChatActions {
        let controller = model.controller
        let items = model.screen.items
        return ChatActions(
            tap: { buttonId, messageId in Task { @MainActor in await controller.tap(buttonId, in: messageId) } },
            submit: { messageId, values in await controller.submit(messageId, values: values) },
            retry: { clientId in Task { @MainActor in await controller.retrySending(clientId) } },
            openImage: { url in fullScreenImage = ImageURL(url: url) },
            reply: { messageId in Task { @MainActor in controller.reply(to: messageId) } },
            jump: { messageId in
                // The quoted message, a third down the screen, lit for a second.
                guard let target = items.first(where: {
                    if case .bubble(let bubble) = $0 { return bubble.messageId == messageId }
                    return false
                })?.id else { return }
                withAnimation(reduceMotion ? nil : Motion.spring) { proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.33)) }
                lit = target
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if lit == target { lit = nil } }
            },
            focus: { key, focused in
                if focused { focusedField = key } else if focusedField == key { focusedField = nil }
            },
            highlighted: lit, replyLabel: model.screen.replyLabel, copyLabel: model.screen.copyLabel)
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(header: model.screen.header, theme: theme, showsDivider: scrolled, back: back, close: close)
                .offlineCapsule(offline: model.screen.offline, connected: model.screen.connected, theme: theme)
            // What is not known yet shows nothing; once it is, all of it comes at once, fading in over 200 ms
            // (DESIGN-PASS-3 C5). From the cache it is there in the first frames.
            ZStack {
                transcript
                    .transition(.opacity)
                    .id(model.screen.phase)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.screen.phase)
            // While a flow waits for a choice there is no composer at all (operator, 2026-10-04): the choices stand at
            // the end of the conversation. It comes back, sliding up and fading in over 200 ms, when the flow takes
            // text, ends, or an operator joins.
            if composerShown {
                ComposerView(composer: model.screen.composer, theme: theme, text: $draft, writeAnyway: $writeAnyway,
                             staged: $staged, send: send, attach: { choosingAttachment = true }, startNew: startNew,
                             cancelQuote: { model.controller.reply(to: nil) })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // H1: the screen ends on the keyboard, moving with it. SwiftUI's own keyboard avoidance is off for it: in the
        // messenger's page sheet it did not happen on an iPhone, and where it does it would lift the screen twice.
        .padding(.bottom, keyboard)
        .background(KeyboardProbe { overlap, animation in
            withAnimation(animation) { keyboard = overlap }
        })
        .background(theme.colors.background.color.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // M7: the composer comes and goes by height and fade, 220 ms.
        .animation(reduceMotion ? nil : Motion.decelerate(0.22), value: composerShown)
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
                    ChatTranscript(items: model.screen.items, theme: theme, actions: actions(proxy), reachedTop: loadOlder)
                        .background(GeometryReader { box in
                            Color.clear.preference(key: ScrollEndOffset.self,
                                                   value: box.frame(in: .named(ScrollTopOffset.space)).maxY)
                        })
                        .onAppear {
                            if let last = model.screen.items.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                            // Shown once it stands at its end: the first frame is the bottom, nothing slides.
                            DispatchQueue.main.async { atBottom = true }
                        }
                }
                .coordinateSpace(name: ScrollTopOffset.space)
                .onPreferenceChange(ScrollEndOffset.self) { end in listEnd.value = end }
                .onPreferenceChange(ScrollTopOffset.self) { top in
                    scrolled = top < -1
                    measureNearEnd()
                }
                // The keyboard came up (or the composer grew): the last message, or the form field being filled,
                // stays in sight over it, moving with it (H1). Measured after the layout that made the room smaller.
                .background(GeometryReader { box in
                    Color.clear
                        .onAppear { viewport = box.size.height }
                        .onChange(of: box.size.height) { height in
                            if height < viewport - 1 { keepInSight(proxy) }
                            viewport = height
                            // The keyboard went down (a drag through the list dismisses it): more of the end shows.
                            measureNearEnd()
                        }
                })
                .onChange(of: focusedField) { key in if key != nil { keepInSight(proxy) } }
                .onChange(of: newest?.id) { _ in arrived(proxy) }
                // The typing bubble shows at the end only to whom is there.
                .onChange(of: model.screen.items.last?.id) { last in
                    guard last == "typing", nearEnd else { return }
                    withAnimation(reduceMotion ? nil : Motion.spring) { proxy.scrollTo("typing", anchor: .bottom) }
                }
                .overlay(alignment: .bottom) {
                    ZStack {
                        if unseen { newMessageCapsule(proxy) }
                    }
                    .animation(reduceMotion ? nil : Motion.capsule, value: unseen)
                }
                .opacity(atBottom ? 1 : 0)
            }
        }
    }

    /// Further than this from the end, the user is reading the history: a new message does not pull the list (H2).
    static let followWithin: CGFloat = 120

    /// Whether the user is near the end now, from where the list stands; "Yeni mesaj" goes once they are.
    private func measureNearEnd() {
        let near = listEnd.value - viewport <= Self.followWithin
        if near != nearEnd { nearEnd = near }
        if near, unseen { unseen = false }
    }

    /// The newest message or step: what decides whether the list follows. Not the typing bubble or a time line.
    private var newest: ChatItem? {
        model.screen.items.last {
            switch $0 {
            case .typing, .time: return false
            default: return true
            }
        }
    }

    /// A new message or step (H2): the list goes to its end, softly, when the user is near the end anyway, sent it,
    /// or it is choices or a form to fill; otherwise it stays where the user reads and "Yeni mesaj ↓" shows.
    private func arrived(_ proxy: ScrollViewProxy) {
        guard let item = newest, let last = model.screen.items.last?.id else { return }
        var follows = nearEnd
        switch item {
        case .bubble(let bubble):
            if bubble.side == .outgoing { follows = true }
            if case .form = bubble.body { follows = true }
        case .replies: follows = true
        default: break
        }
        guard follows else {
            if case .bubble = item { unseen = true }
            return
        }
        unseen = false
        withAnimation(reduceMotion ? nil : Motion.spring) { proxy.scrollTo(last, anchor: .bottom) }
    }

    /// "Yeni mesaj ↓" over the bottom of the transcript: a tap goes to the end.
    private func newMessageCapsule(_ proxy: ScrollViewProxy) -> some View {
        Button {
            unseen = false
            guard let last = model.screen.items.last?.id else { return }
            withAnimation(reduceMotion ? nil : Motion.spring) { proxy.scrollTo(last, anchor: .bottom) }
        } label: {
            HStack(spacing: 6) {
                Text(model.screen.newMessageLabel)
                    .clomniFont(13, .semibold)
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(theme.colors.onPrimary.color)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(Capsule().fill(theme.colors.primary.color))
            .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        }
        .buttonStyle(PressShapeStyle(shape: Capsule()))
        .accessibilityIdentifier("clomni.chat.newMessage")
        .padding(.bottom, CGFloat(ClomniTheme.Space.m))
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    /// The focused form field, else the last item, at the bottom of what the keyboard leaves of the list.
    private func keepInSight(_ proxy: ScrollViewProxy) {
        guard let target = focusedField ?? model.screen.items.last?.id else { return }
        withAnimation(reduceMotion ? nil : Motion.keyboard) { proxy.scrollTo(target, anchor: .bottom) }
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

/// A number a view keeps without redrawing when it changes.
final class Measure {
    var value: CGFloat = 0
}

/// The bottom of the transcript's content, from the top of what shows of it.
struct ScrollEndOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ImageURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The conversation's bar, one fixed height whatever it shows (DESIGN-PASS-2 10): back, 8 after its circle who answers
/// (the company's logo cut to a 32 circle, or the operator's 32 avatar with the green dot while online), the name 16
/// semibold with the subtitle 13 under it (its line kept even when empty), and ✕ as on every screen (DESIGN-PASS-3 B3). Nothing in it
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
            // Who answers starts 8 after back's circle, whose target reaches 2 past it, and cuts with "…" before ✕.
            HStack(spacing: CGFloat(ClomniTheme.Space.s) - ScreenBar<EmptyView>.overhang) {
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
            // M9: half a point.
            Rectangle().fill(theme.colors.border.color).frame(height: 0.5).opacity(showsDivider ? 1 : 0)
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
                        .clomniFont(16, .semibold, relativeTo: .headline)
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
