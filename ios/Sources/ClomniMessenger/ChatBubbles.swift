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

/// Off in snapshot tests, so pictures from the network cannot make them flaky: placeholders stay.
private struct LoadsRemoteImagesKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var clomniLoadsRemoteImages: Bool {
        get { self[LoadsRemoteImagesKey.self] }
        set { self[LoadsRemoteImagesKey.self] = newValue }
    }
}

/// What the transcript hands back.
struct ChatActions {
    var tap: (_ buttonId: String, _ messageId: String) -> Void = { _, _ in }
    var submit: (_ messageId: String, _ values: [String: String]) async -> [String: String] = { _, _ in [:] }
    var retry: (_ clientId: String) -> Void = { _ in }
    var openImage: (URL) -> Void = { _ in }
}

/// The styled runs as one text: bold and italic through presentation intents, links underlined and tappable.
func attributedText(_ runs: [TextRun]) -> AttributedString {
    var result = AttributedString()
    for run in runs {
        var part = AttributedString(run.text)
        var intent: InlinePresentationIntent = []
        if run.bold { intent.insert(.stronglyEmphasized) }
        if run.italic { intent.insert(.emphasized) }
        if !intent.isEmpty { part.inlinePresentationIntent = intent }
        if let link = run.link {
            part.link = link
            // Named by its scope: UIKit has an underlineStyle attribute too.
            part[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = Text.LineStyle.single
        }
        result += part
    }
    return result
}

/// The messages, separators, buttons and typing, top to bottom (in a ScrollView on screen, bare in snapshots).
struct ChatTranscript: View {
    let items: [ChatItem]
    let theme: ClomniTheme
    let actions: ChatActions
    /// Called when the top of the list comes into view.
    var reachedTop: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.xxs)) {
            Color.clear
                .frame(height: 1)
                .onAppear(perform: reachedTop)
                .accessibilityHidden(true)
            ForEach(items) { item in
                ChatItemView(item: item, theme: theme, actions: actions)
                    .id(item.id)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, CGFloat(ClomniTheme.Space.xl))
        .padding(.top, CGFloat(ClomniTheme.Space.xl))
        .padding(.bottom, CGFloat(ClomniTheme.Space.s))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: items.map(\.id))
    }
}

struct ChatItemView: View {
    let item: ChatItem
    let theme: ClomniTheme
    let actions: ChatActions

    var body: some View {
        switch item {
        case .time(_, let text):
            Text(text)
                .clomniFont(11.5, relativeTo: .caption2)
                .foregroundStyle(theme.colors.textSecondary.color)
                .frame(maxWidth: .infinity)
                .padding(.top, CGFloat(ClomniTheme.Space.xxs))
                .padding(.bottom, CGFloat(ClomniTheme.Space.m))
        case .bubble(let bubble):
            BubbleRow(bubble: bubble, theme: theme, actions: actions)
        case .system(let line):
            SystemLineView(line: line, theme: theme)
        case .replies(let block):
            QuickRepliesView(block: block, theme: theme) { buttonId in actions.tap(buttonId, block.messageId) }
        case .typing(let line):
            TypingRow(line: line, theme: theme)
        }
    }
}

/// A bubble with its avatar slot, meta line and status, on its side of the screen.
struct BubbleRow: View {
    let bubble: Bubble
    let theme: ClomniTheme
    let actions: ChatActions
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.clomniScreenWidth) private var screenWidth

    private var incoming: Bool { bubble.side == .incoming }

    /// DESIGN-PASS-2 13: a bubble is at most 78% of the screen wide.
    private var maxWidth: CGFloat { screenWidth * 0.78 }

    /// 16 pt, 5 where bubbles of one run meet; the user's always keep the 5 pt bottom-trailing corner.
    private var corners: (topLeading: CGFloat, topTrailing: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat) {
        let round = CGFloat(ClomniTheme.Radius.message)
        let joined = CGFloat(ClomniTheme.Radius.messageJoined)
        let joinsAbove = bubble.position == .middle || bubble.position == .last
        let joinsBelow = bubble.position == .first || bubble.position == .middle
        if incoming {
            return (joinsAbove ? joined : round, round, joinsBelow ? joined : round, round)
        }
        return (round, joinsAbove ? joined : round, round, joined)
    }

    private var shape: BubbleShape {
        let c = corners
        // The shape draws in screen coordinates; leading is on the right in right-to-left languages.
        return layoutDirection == .rightToLeft
            ? BubbleShape(topLeft: c.topTrailing, topRight: c.topLeading, bottomLeft: c.bottomTrailing,
                          bottomRight: c.bottomLeading)
            : BubbleShape(topLeft: c.topLeading, topRight: c.topTrailing, bottomLeft: c.bottomLeading,
                          bottomRight: c.bottomTrailing)
    }

    var body: some View {
        VStack(alignment: incoming ? .leading : .trailing, spacing: CGFloat(ClomniTheme.Space.xxs)) {
            if let name = bubble.nameLine {
                // Outside the bubble, over its run.
                Text(name)
                    .clomniFont(13, .semibold, relativeTo: .footnote)
                    .foregroundStyle(theme.colors.textSecondary.color)
                    .padding(.leading, CGFloat(ClomniTheme.Size.headerAvatar + ClomniTheme.Space.s))
                    .accessibilityHidden(true)
            }
            HStack(alignment: .bottom, spacing: CGFloat(ClomniTheme.Space.s)) {
                if incoming {
                    avatarSlot
                }
                // At most 78% of the screen's width, never at its edge (the transcript keeps 16 pt on each side).
                BubbleBody(bubble: bubble, theme: theme, shape: shape, actions: actions)
                    .frame(maxWidth: maxWidth, alignment: incoming ? .leading : .trailing)
            }
            .frame(maxWidth: .infinity, alignment: incoming ? .leading : .trailing)
            if let meta = bubble.meta {
                Text(meta)
                    .clomniFont(ClomniTheme.FontSize.meta, relativeTo: .caption2)
                    .foregroundStyle(theme.colors.textSecondary.color)
                    // Under the bubble, past the avatar's slot.
                    .padding(.leading, CGFloat(ClomniTheme.Size.headerAvatar + ClomniTheme.Space.s))
                    .accessibilityHidden(true)
            }
            if let status = bubble.status {
                StatusLine(status: status, theme: theme, retry: actions.retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: incoming ? .leading : .trailing)
        // A new run starts a little apart: 4 pt for the other side, 8 pt for the user.
        .padding(.top, bubble.position == .first || bubble.position == .single ? (incoming ? 4 : 8) : 0)
    }

    @ViewBuilder
    private var avatarSlot: some View {
        if let avatar = bubble.avatar {
            ChatAvatarView(avatar: avatar, size: ClomniTheme.Size.headerAvatar, theme: theme)
        } else {
            Color.clear.frame(width: CGFloat(ClomniTheme.Size.headerAvatar), height: 1)
        }
    }
}

/// The bubble itself: text, image, file card or form.
struct BubbleBody: View {
    let bubble: Bubble
    let theme: ClomniTheme
    let shape: BubbleShape
    let actions: ChatActions
    @Environment(\.openURL) private var openURL

    private var incoming: Bool { bubble.side == .incoming }
    private var fill: Color { incoming ? theme.colors.surface.color : theme.colors.primary.color }
    private var ink: Color { incoming ? theme.colors.textPrimary.color : theme.colors.onPrimary.color }

    var body: some View {
        switch bubble.body {
        case .text(let runs):
            Text(attributedText(runs))
                .clomniFont(ClomniTheme.FontSize.text)
                .lineSpacing(3)
                .foregroundStyle(ink)
                .tint(incoming ? theme.colors.primary.color : theme.colors.onPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, CGFloat(ClomniTheme.Space.s))
                .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
                .background(shape.fill(fill))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(bubble.accessibilityLabel))
        case .image(let image):
            // Brief 7.4: an image is rounded 12 all round, not cut to the bubble's shape.
            ImageBubble(image: image, theme: theme, fill: fill, ink: ink, open: actions.openImage)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.card), style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(bubble.accessibilityLabel))
                .accessibilityHint(Text(bubble.accessibilityHint ?? ""))
                .accessibilityAddTraits([.isImage, .isButton])
                .accessibilityAction { if let url = image.fullUrl ?? image.url { actions.openImage(url) } }
        case .file(let file):
            Button {
                if let url = file.url { openURL(url) }
            } label: {
                FileCard(file: file, theme: theme, ink: ink)
                    .background(shape.fill(fill))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Text(bubble.accessibilityLabel))
            .accessibilityHint(Text(bubble.accessibilityHint ?? ""))
        case .form(let card):
            FormCardView(card: card, theme: theme, bubble: shape, bubbleFill: fill,
                         submit: { values in await actions.submit(card.messageId, values) })
        }
    }
}

/// Rounded corners of their own each.
struct BubbleShape: Shape {
    var topLeft: CGFloat
    var topRight: CGFloat
    var bottomLeft: CGFloat
    var bottomRight: CGFloat

    func path(in rect: CGRect) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let tl = min(topLeft, limit), tr = min(topRight, limit)
        let bl = min(bottomLeft, limit), br = min(bottomRight, limit)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// An image in its reserved box (radius 12), the caption under it; a tap opens it full screen.
struct ImageBubble: View {
    let image: Bubble.ImageBody
    let theme: ClomniTheme
    let fill: Color
    let ink: Color
    let open: (URL) -> Void
    @Environment(\.clomniLoadsRemoteImages) private var loadsImages
    @Environment(\.clomniLoadingLabel) private var loadingLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if let url = image.fullUrl ?? image.url { open(url) }
            } label: {
                picture
            }
            .buttonStyle(PlainButtonStyle())
            if let caption = image.caption {
                Text(attributedText(caption))
                    .clomniFont(ClomniTheme.FontSize.text)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, CGFloat(ClomniTheme.Space.s))
                    .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
                    .frame(width: CGFloat(image.width), alignment: .leading)
                    .background(fill)
            }
        }
    }

    @ViewBuilder
    private var picture: some View {
        if let file = image.localFile, let local = UIImage(contentsOfFile: file.path) {
            Image(uiImage: local)
                .resizable()
                .scaledToFill()
                .frame(width: CGFloat(image.width), height: CGFloat(image.height))
                .clipped()
        } else if let url = image.url, loadsImages {
            AsyncImage(url: url) { phase in
                if let loaded = phase.image {
                    if image.sizeKnown {
                        loaded.resizable().scaledToFill()
                            .frame(width: CGFloat(image.width), height: CGFloat(image.height))
                            .clipped()
                    } else {
                        // Unknown size: the image takes its own ratio once it is here.
                        loaded.resizable().scaledToFit()
                            .frame(maxWidth: CGFloat(Media.maxImageWidth), maxHeight: CGFloat(Media.maxImageHeight))
                    }
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    /// The image's own size in grey, with the spinner while it loads.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.card), style: .continuous)
            .fill(theme.colors.surface.color)
            .frame(width: CGFloat(image.width), height: CGFloat(image.height))
            .overlay(LoadingIndicator(loading: loadsImages && image.url != nil, label: loadingLabel, theme: theme))
    }
}

/// Icon, name, size.
struct FileCard: View {
    let file: Bubble.FileBody
    let theme: ClomniTheme
    let ink: Color

    var body: some View {
        HStack(spacing: CGFloat(ClomniTheme.Space.m)) {
            Image(systemName: file.symbol)
                .font(.system(size: 22))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.xxs)) {
                Text(file.name)
                    .clomniFont(ClomniTheme.FontSize.text, .medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.size)
                    .clomniFont(ClomniTheme.FontSize.label, relativeTo: .caption)
                    .opacity(0.7)
            }
        }
        .foregroundStyle(ink)
        .padding(.vertical, CGFloat(ClomniTheme.Space.m))
        .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
        .frame(maxWidth: 222, alignment: .leading)
    }
}

/// "Göndərildi", "Oxundu"; a failure in red, tapping it sends again.
struct StatusLine: View {
    let status: Bubble.Status
    let theme: ClomniTheme
    let retry: (String) -> Void

    var body: some View {
        if let retryId = status.retryId {
            Button {
                retry(retryId)
            } label: {
                label
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .padding(.vertical, -12)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            label
        }
    }

    /// Only the failure stays its own element (a button); "Göndərildi" and "Oxundu" are read with the bubble.
    private var label: some View {
        Text(status.text)
            .accessibilityHidden(!status.isFailure)
            .clomniFont(ClomniTheme.FontSize.meta, relativeTo: .caption2)
            .foregroundStyle(status.isFailure ? theme.colors.unread.color : theme.colors.textSecondary.color)
    }
}

/// Centred grey text with small avatars.
struct SystemLineView: View {
    let line: SystemLine
    let theme: ClomniTheme

    var body: some View {
        HStack(spacing: CGFloat(ClomniTheme.Space.xs)) {
            if !line.avatars.isEmpty {
                HStack(spacing: -11) {
                    ForEach(Array(line.avatars.enumerated()), id: \.offset) { _, avatar in
                        ChatAvatarView(avatar: avatar, size: 20, theme: theme)
                            .padding(2)
                            .background(Circle().fill(theme.colors.background.color))
                    }
                }
                .accessibilityHidden(true)
            }
            Text(line.text)
                .clomniFont(ClomniTheme.FontSize.label, relativeTo: .caption)
                .foregroundStyle(theme.colors.textSecondary.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CGFloat(ClomniTheme.Space.m))
        .padding(.bottom, CGFloat(ClomniTheme.Space.xs))
    }
}

/// Three dots in a bot bubble; they pulse unless Reduce Motion is on.
struct TypingRow: View {
    let line: TypingLine
    let theme: ClomniTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .bottom, spacing: CGFloat(ClomniTheme.Space.s)) {
            ChatAvatarView(avatar: line.avatar, size: ClomniTheme.Size.headerAvatar, theme: theme)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(theme.colors.textSecondary.color)
                        .frame(width: 6, height: 6)
                        .opacity(pulse ? 0.9 : 0.5 + 0.2 * Double(index))
                }
            }
            .padding(.vertical, CGFloat(ClomniTheme.Space.l))
            .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
            .background(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.message), style: .continuous)
                .fill(theme.colors.surface.color))
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(line.accessibilityLabel))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { pulse = true }
        }
    }
}

/// A person's or the bot's face; the bot without a picture is a brand-coloured circle with its initial.
struct ChatAvatarView: View {
    let avatar: ChatAvatar
    let size: Double
    let theme: ClomniTheme

    var body: some View {
        if avatar.isBot && avatar.url == nil {
            Circle()
                .fill(theme.colors.primary.color)
                .overlay(Text(avatar.initial)
                    .clomniFixedFont(size * 0.45, .bold)
                    .foregroundStyle(theme.colors.onPrimary.color))
                .frame(width: CGFloat(size), height: CGFloat(size))
                .accessibilityHidden(true)
        } else {
            AvatarView(url: avatar.url, initial: avatar.initial, size: size, theme: theme)
        }
    }
}
#endif
