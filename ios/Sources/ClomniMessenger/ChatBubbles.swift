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

/// Off in snapshot tests, so pictures from the network cannot make them flaky: placeholders stay. Nothing waits to
/// come in there either (`entrance`): a picture shows where things end.
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
    /// A rating's score, with the comment when its card has a field.
    var rate: (_ messageId: String, _ score: Int, _ comment: String?) async -> Void = { _, _, _ in }
    var retry: (_ clientId: String) -> Void = { _ in }
    var openImage: (URL) -> Void = { _ in }
    /// A swipe or "Cavabla": the message to quote over the field.
    var reply: (_ messageId: String) -> Void = { _ in }
    /// A tap on a quote: scroll to the quoted message.
    var jump: (_ messageId: String) -> Void = { _ in }
    /// A form field took or lost the focus: the list keeps it over the keyboard (G4).
    var focus: (_ key: String, _ focused: Bool) -> Void = { _, _ in }
    /// The bubble a quote has just led to, lit for a second.
    var highlighted: String?
    var replyLabel = ""
    var copyLabel = ""
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

/// Where a link in a message's text goes (CM-087): a web address to the app's `onLink` when it has one, as a news
/// button's does; tel:, mailto: and any address without `onLink` to the system.
struct MessageLinks: ViewModifier {
    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let link = ClomniShared.state.read({ $0.events.link }) else { return .systemAction }
            link(url)
            return .handled
        })
    }
}

/// The messages, separators, buttons and typing, top to bottom (in a ScrollView on screen, bare in snapshots).
///
/// An eager VStack, not a LazyVStack: the list's height is then its real height, which is where ScrollPin holds the
/// end. A lazy stack's is an estimate, and on iOS 27 it moves the scroll view's offset itself as it measures (CM-087,
/// TestFlight 13). A conversation is a few pages of messages; older ones come only when the user scrolls up to them.
struct ChatTranscript: View {
    let items: [ChatItem]
    let theme: ClomniTheme
    let actions: ChatActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Under the last row.
    static let bottomPadding = CGFloat(ClomniTheme.Space.s)

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.xxs)) {
            ForEach(items) { item in
                // Fades in once, when it is new: an item is keyed by its client id from the moment it is written, so
                // the server's copy changes only its status, and scrolling back is not an insertion.
                ChatItemView(item: item, theme: theme, actions: actions)
                    .id(item.id)
                    .transition(Motion.arrival(item, still: reduceMotion))
            }
        }
        .padding(.horizontal, CGFloat(ClomniTheme.Space.xl))
        .padding(.top, CGFloat(ClomniTheme.Space.xl))
        .padding(.bottom, Self.bottomPadding)
        // M3: new items come in on the emphasized easing and the rest move to their place; Reduce Motion: nothing moves.
        // Only for a change at the end: a page of history above lands in one pass, not sliding the rows under the
        // ScrollPin for 200 ms (CM-087).
        .animation(reduceMotion ? nil : Motion.decelerate(0.2), value: items.last?.id)
    }
}

struct ChatItemView: View {
    let item: ChatItem
    let theme: ClomniTheme
    let actions: ChatActions

    var body: some View {
        switch item {
        case .time(_, let text):
            // The day line 12; with the list's 4 pt, 16 over it.
            Text(text)
                .clomniFont(ClomniTheme.FontSize.label, relativeTo: .caption2)
                .foregroundStyle(theme.colors.textSecondary.color)
                .frame(maxWidth: .infinity)
                .padding(.top, CGFloat(ClomniTheme.Space.m))
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

/// A bubble with its avatar slot (28, next to the last of a run), the author over the first of a run (13 medium), the
/// time under the last (12), and the status, on its side of the screen. With the list's 4 pt, bubbles of a run are 4
/// apart and runs 16 (DESIGN-PASS-3 B2).
struct BubbleRow: View {
    let bubble: Bubble
    let theme: ClomniTheme
    let actions: ChatActions
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.clomniScreenWidth) private var screenWidth
    @State private var pulled: CGFloat = 0

    private var incoming: Bool { bubble.side == .incoming }
    private var lit: Bool { actions.highlighted == bubble.id }

    /// DESIGN-PASS-2 13: a bubble is at most 78% of the screen wide.
    private var maxWidth: CGFloat { screenWidth * 0.78 }

    /// 18 pt, 5 where bubbles of one run meet; the user's always keep the 5 pt bottom-trailing corner.
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
                    .clomniFont(13, .medium, relativeTo: .footnote)
                    .foregroundStyle(theme.colors.textSecondary.color)
                    .lineLimit(1)
                    .padding(.leading, CGFloat(ClomniTheme.Size.avatar + ClomniTheme.Space.s))
                    .accessibilityHidden(true)
            }
            HStack(alignment: .bottom, spacing: CGFloat(ClomniTheme.Space.s)) {
                if incoming {
                    avatarSlot
                }
                // At most 78% of the screen's width, never at its edge (the transcript keeps 16 pt on each side).
                BubbleBody(bubble: bubble, theme: theme, shape: shape, actions: actions)
                    .modifier(MessageMenu(bubble: bubble, actions: actions))
                    .overlay(alignment: .leading) {
                        if !incoming { ReplyArrow(pulled: pulled, theme: theme).offset(x: -36) }
                    }
                    .frame(maxWidth: maxWidth, alignment: incoming ? .leading : .trailing)
            }
            .frame(maxWidth: .infinity, alignment: incoming ? .leading : .trailing)
            .modifier(SwipeToReply(enabled: bubble.replyable && bubble.messageId != nil, pulled: $pulled) {
                if let id = bubble.messageId { actions.reply(id) }
            })
            .background(alignment: .leading) { if incoming { ReplyArrow(pulled: pulled, theme: theme) } }
            // The time and the mark are in the bubble (G7); only a failure is under it, in words.
            if let status = bubble.status, let retryId = status.retryId {
                FailureLine(text: status.text, retryId: retryId, theme: theme, retry: actions.retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: incoming ? .leading : .trailing)
        // A quote led here: the row glows in the brand colour for a second.
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(theme.colors.primary.color.opacity(lit ? 0.12 : 0))
            .animation(.easeOut(duration: lit ? 0.2 : 0.7), value: lit))
        // A new run starts 16 pt apart, the list's 4 and 12.
        .padding(.top, bubble.position == .first || bubble.position == .single ? CGFloat(ClomniTheme.Space.m) : 0)
    }

    @ViewBuilder
    private var avatarSlot: some View {
        if let avatar = bubble.avatar {
            ChatAvatarView(avatar: avatar, size: ClomniTheme.Size.avatar, theme: theme)
        } else {
            Color.clear.frame(width: CGFloat(ClomniTheme.Size.avatar), height: 1)
        }
    }
}

/// The bubble itself: text, image, file card, form or rating.
struct BubbleBody: View {
    let bubble: Bubble
    let theme: ClomniTheme
    let shape: BubbleShape
    let actions: ChatActions
    @Environment(\.openURL) private var openURL

    private var incoming: Bool { bubble.side == .incoming }
    private var fill: Color { incoming ? theme.colors.surface.color : theme.colors.primary.color }
    private var ink: Color { incoming ? theme.colors.textPrimary.color : theme.colors.onPrimary.color }
    private var stamp: BubbleStamp { BubbleStamp(bubble) }

    var body: some View {
        switch bubble.body {
        case .text(let runs):
            // With a quote: 6 around, the quote, then the text 8 in.
            VStack(alignment: .leading, spacing: 4) {
                if let quote = bubble.quote {
                    QuoteBlock(quote: quote, ink: ink, outgoing: !incoming, jump: actions.jump)
                }
                StampedText(text: attributedText(runs), size: ClomniTheme.FontSize.message, stamp: stamp, theme: theme,
                            drawsStamp: bubble.quote == nil)
                    .lineSpacing(3)
                    .foregroundStyle(ink)
                    .tint(incoming ? theme.colors.primary.color : theme.colors.onPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    // The stamp 6 over the bubble's bottom edge (H4): 8 of padding, less the 2 it sits under the line.
                    .padding(bubble.quote == nil ? EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14)
                             : EdgeInsets(top: 0, leading: 8, bottom: 4, trailing: 8))
                    .accessibilityLabel(Text(bubble.accessibilityLabel))
            }
            .overlay(alignment: .bottomTrailing) {
                // With a quote the stamp keeps the bubble's corner, where the text's own room would leave it mid-way.
                if bubble.quote != nil {
                    StampView(stamp: stamp, color: stamp.color(theme))
                        .padding(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 8))
                        .offset(y: StampedText.drop)
                }
            }
            .padding(bubble.quote == nil ? 0 : 6)
            .background(shape.fill(fill))
            .fixedSize(horizontal: false, vertical: true)
        case .image(let image):
            // Brief 7.4: an image is rounded 12 all round, not cut to the bubble's shape.
            quoted(ImageBubble(image: image, theme: theme, fill: fill, ink: ink, stamp: stamp, open: actions.openImage)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.card), style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(bubble.accessibilityLabel))
                .accessibilityHint(Text(bubble.accessibilityHint ?? ""))
                .accessibilityAddTraits([.isImage, .isButton])
                .accessibilityAction { if let url = image.fullUrl ?? image.url { actions.openImage(url) } })
        case .file(let file):
            quoted(Button {
                if let url = file.url { openURL(url) }
            } label: {
                FileCard(file: file, theme: theme, ink: ink, stamp: stamp)
                    .background(shape.fill(bubble.quote == nil ? fill : .clear))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Text(bubble.accessibilityLabel))
            .accessibilityHint(Text(bubble.accessibilityHint ?? "")))
        case .form(let card):
            FormCardView(card: card, theme: theme, bubble: shape, bubbleFill: fill,
                         stamp: stamp, submit: { values in await actions.submit(card.messageId, values) },
                         focus: actions.focus)
        case .rating(let card):
            RatingCardView(card: card, theme: theme, bubble: shape, bubbleFill: fill, stamp: stamp,
                           rate: { score, comment in await actions.rate(card.messageId, score, comment) },
                           focus: actions.focus)
        }
    }
}

extension BubbleBody {
    /// An image or file that answers a message: the quote over it, both in one bubble of its colour.
    @ViewBuilder
    func quoted<V: View>(_ content: V) -> some View {
        if let quote = bubble.quote {
            VStack(alignment: .leading, spacing: 4) {
                QuoteBlock(quote: quote, ink: ink, outgoing: !incoming, jump: actions.jump)
                    .padding(2)
                content
            }
            .padding(4)
            .background(shape.fill(fill))
        } else {
            content
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
    let stamp: BubbleStamp
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
            // Without a caption the time is on the picture, white on a dark capsule.
            .overlay(alignment: .bottomTrailing) {
                if image.caption == nil {
                    StampView(stamp: stamp, color: .white, muted: false)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.black.opacity(0.4)))
                        .padding(6)
                }
            }
            if let caption = image.caption {
                StampedText(text: attributedText(caption), size: ClomniTheme.FontSize.text, stamp: stamp, theme: theme)
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
    let stamp: BubbleStamp

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
                HStack(alignment: .lastTextBaseline, spacing: CGFloat(ClomniTheme.Space.s)) {
                    Text(file.size)
                        .clomniFont(ClomniTheme.FontSize.label, relativeTo: .caption)
                        .opacity(0.7)
                    Spacer(minLength: 0)
                    StampView(stamp: stamp, color: stamp.color(theme))
                }
            }
        }
        .foregroundStyle(ink)
        .padding(.vertical, CGFloat(ClomniTheme.Space.m))
        .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
        .frame(maxWidth: 222, alignment: .leading)
    }
}

/// A failure under the user's message, in red words; tapping it sends again.
struct FailureLine: View {
    let text: String
    let retryId: String
    let theme: ClomniTheme
    let retry: (String) -> Void

    var body: some View {
        Button {
            retry(retryId)
        } label: {
            Text(text)
                .clomniFont(ClomniTheme.FontSize.meta, relativeTo: .caption2)
                .foregroundStyle(theme.colors.unread.color)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .padding(.vertical, -12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// The time in a bubble's bottom-trailing corner, WhatsApp's way (operator, 2026-10-07, G7 and H4), and on the user's
/// message its mark after it: the clock while it goes, ✓ once sent, two once read. The time is 11 and grows with the
/// text size only up to 13; on the user's bubble it is on_primary at 65%, the mark too until it is read, then 100%; on
/// the others text_muted. VoiceOver reads it with the bubble.
struct BubbleStamp {
    /// The time's size, and its largest with Dynamic Type.
    static let size: CGFloat = 11
    static let largest: CGFloat = 13
    /// The time and the mark, and the corner's ink, at 65% on the user's bubble.
    static let muted = 0.65

    let time: String
    let mark: Bubble.Status.Mark?
    let outgoing: Bool

    init(_ bubble: Bubble) {
        time = bubble.time
        mark = bubble.status?.mark
        outgoing = bubble.side == .outgoing
    }

    /// The time and `mark` as one text, so the room kept for it in a message's last line is exactly as wide. No
    /// break inside it. `muted`: the time, and the mark until read, at 65% of `color`.
    @MainActor
    func text(mark: Bubble.Status.Mark?, color: Color, muted: Bool) -> Text {
        let time = Text(verbatim: self.time).foregroundColor(muted && outgoing ? color.opacity(Self.muted) : color)
        guard let mark else { return time }
        let ink = muted && mark != .read ? color.opacity(Self.muted) : color
        return time + Text(verbatim: "\u{00A0}") + Text(StampGlyph.image(mark)).foregroundColor(ink)
    }

    /// What a message's last line keeps free for the stamp: 6 of gap, then the stamp at its widest (two ✓ on the
    /// user's). A normal space before it: when the line is full it goes to a line of its own.
    @MainActor
    var room: Text {
        Text(verbatim: " \u{00A0}") + text(mark: outgoing ? .read : nil, color: .clear, muted: false)
    }

    func color(_ theme: ClomniTheme) -> Color {
        (outgoing ? theme.colors.onPrimary : theme.colors.textSecondary).color
    }

    /// 11, at most 13 with Dynamic Type, in the app's family when it has one.
    static func font(_ typeface: Typeface?, scaled: CGFloat) -> Font {
        let size = min(scaled, largest)
        return typeface.map { Font.custom($0.face(for: Font.Weight.regular.css), fixedSize: size) } ?? .system(size: size)
    }
}

/// The marks of the stamp, drawn as template images so they sit in its line of text (H4): ✓ 11×8, ✓✓ 15×8 with the
/// second over the first, the clock 8×8; lines 1.5, round ends. An SF Symbol at the text's size was too big and too
/// heavy, and two of them did not overlap.
@MainActor
enum StampGlyph {
    private static var drawn: [Bubble.Status.Mark: Image] = [:]

    static func size(_ mark: Bubble.Status.Mark) -> CGSize {
        switch mark {
        case .sending: return CGSize(width: 8, height: 8)
        case .sent: return CGSize(width: 11, height: 8)
        case .read: return CGSize(width: 15, height: 8)
        }
    }

    static func image(_ mark: Bubble.Status.Mark) -> Image {
        if let image = drawn[mark] { return image }
        let picture = UIGraphicsImageRenderer(size: size(mark)).image { _ in
            let path = UIBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            switch mark {
            case .sending:
                path.lineWidth = 1.2
                path.append(UIBezierPath(ovalIn: CGRect(x: 0.6, y: 0.6, width: 6.8, height: 6.8)))
                path.move(to: CGPoint(x: 4, y: 2.2))
                path.addLine(to: CGPoint(x: 4, y: 4))
                path.addLine(to: CGPoint(x: 5.3, y: 4.9))
            case .sent:
                tick(path)
            case .read:
                tick(path)
                // The second one's short leg mostly hidden behind the first one's long leg.
                path.move(to: CGPoint(x: 6.6, y: 5.9))
                path.addLine(to: CGPoint(x: 7.9, y: 7.25))
                path.addLine(to: CGPoint(x: 14.25, y: 0.75))
            }
            UIColor.black.setStroke()
            path.stroke()
        }
        let image = Image(uiImage: picture.withRenderingMode(.alwaysTemplate))
        drawn[mark] = image
        return image
    }

    private static func tick(_ path: UIBezierPath) {
        path.move(to: CGPoint(x: 0.75, y: 4.4))
        path.addLine(to: CGPoint(x: 3.9, y: 7.25))
        path.addLine(to: CGPoint(x: 10.25, y: 0.75))
    }
}

/// The stamp on its own: on a picture, in a file card, and over the room `StampedText` keeps for it. A change of mark
/// only cross-fades, 150 ms (M3). `muted` false on a picture, where it is white on a dark capsule.
struct StampView: View {
    let stamp: BubbleStamp
    let color: Color
    var muted = true
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = BubbleStamp.size
    @Environment(\.clomniTypeface) private var typeface

    var body: some View {
        ZStack {
            stamp.text(mark: stamp.mark, color: color, muted: muted)
                .font(BubbleStamp.font(typeface, scaled: size))
                .lineLimit(1)
                .fixedSize()
                .id(stamp.mark)
                .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.15), value: stamp.mark)
        .accessibilityHidden(true)
    }
}

/// A message's text with the stamp at the end of its last line when it fits there, else on a line of its own under it:
/// the line keeps room for it in clear text, and the stamp is drawn over that room in the corner, 2 under the line's
/// bottom, so it sits a little below the text's baseline (H4).
struct StampedText: View {
    /// How far under the last line the stamp sits; the bubble's bottom padding is that much smaller.
    static let drop: CGFloat = 2
    let text: AttributedString
    let size: Double
    let stamp: BubbleStamp
    let theme: ClomniTheme
    /// False when the bubble is wider than the text (a quote over it): the bubble then draws the stamp in its own
    /// corner, so it does not hang in the middle with the bubble's right side empty (operator, 2026-10-07).
    var drawsStamp = true
    @ScaledMetric(relativeTo: .caption2) private var stampSize: CGFloat = BubbleStamp.size
    @Environment(\.clomniTypeface) private var typeface

    var body: some View {
        (Text(text) + stamp.room.font(BubbleStamp.font(typeface, scaled: stampSize)))
            .clomniFont(size)
            .modifier(MessageLinks())
            .overlay(alignment: .bottomTrailing) {
                if drawsStamp { StampView(stamp: stamp, color: stamp.color(theme)).offset(y: Self.drop) }
            }
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

    var body: some View {
        HStack(alignment: .bottom, spacing: CGFloat(ClomniTheme.Space.s)) {
            ChatAvatarView(avatar: line.avatar, size: ClomniTheme.Size.avatar, theme: theme)
            TypingDots(color: theme.colors.textSecondary.color)
            .padding(.vertical, CGFloat(ClomniTheme.Space.l))
            .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
            .background(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.message), style: .continuous)
                .fill(theme.colors.surface.color))
        }
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(line.accessibilityLabel))
    }
}

/// M4: three dots on one sine wave, 1.2 s round, each 0.15 s behind the one before; still with Reduce Motion.
private struct TypingDots: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = reduceMotion ? Double(index) / 2
                        : (sin((time - 0.15 * Double(index)) / 1.2 * 2 * .pi) + 1) / 2
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .opacity(0.4 + 0.6 * wave)
                        .scaleEffect(0.8 + 0.2 * wave)
                }
            }
        }
    }
}

/// A person's or the bot's face. The bot is the company: its logo alone once it is there, on nothing (a logo with
/// transparent parts showed a grey disc and the initial through them, CM-087); without one, and until it comes, a
/// brand-coloured circle with its initial.
struct ChatAvatarView: View {
    let avatar: ChatAvatar
    let size: Double
    let theme: ClomniTheme

    var body: some View {
        if avatar.isBot {
            Group {
                if let url = avatar.url {
                    AvatarView(url: url, initial: avatar.initial, size: size, theme: theme)
                } else {
                    brandDisc
                }
            }
            .frame(width: CGFloat(size), height: CGFloat(size))
            .clipShape(Circle())
            .accessibilityHidden(true)
        } else {
            AvatarView(url: avatar.url, initial: avatar.initial, size: size, theme: theme)
        }
    }

    private var brandDisc: some View {
        Circle()
            .fill(theme.colors.primary.color)
            .overlay(Text(avatar.initial)
                .clomniFixedFont(size * 0.45, .bold)
                .foregroundStyle(theme.colors.onPrimary.color))
    }
}
#endif
