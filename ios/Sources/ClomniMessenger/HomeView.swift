#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// What the screens hand back to whoever presents the messenger (CM-084 wires these to navigation).
struct MessengerActions {
    var close: () -> Void = {}
    var newConversation: () -> Void = {}
    var openConversation: (String) -> Void = { _ in }
    var retry: () -> Void = {}
}

/// The Home tab (brief 8 · 7.3): the brand header with the greeting, and the cards riding up over it by 40.
struct HomeView: View {
    let screen: HomeScreen
    let theme: ClomniTheme
    let actions: MessengerActions

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HomeHeaderView(header: screen.header, theme: theme, close: actions.close)
                if let offline = screen.offline {
                    OfflineStrip(text: offline, theme: theme)
                }
                HomeCardsView(screen: screen, theme: theme, actions: actions)
                    .padding(.horizontal, CGFloat(ClomniTheme.Space.l))
                    // Under the offline strip the cards cannot ride up over the header.
                    .padding(.top, screen.offline == nil ? -CGFloat(ClomniTheme.Size.cardOverlap)
                             : CGFloat(ClomniTheme.Space.m))
                    .padding(.bottom, CGFloat(ClomniTheme.Space.xxl))
            }
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
    }
}

struct HomeHeaderView: View {
    let header: HomeScreen.Header
    let theme: ClomniTheme
    let close: () -> Void
    /// The header's width, for the full logo's 60%; a typical phone's until measured.
    @State private var width: CGFloat = 390

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CGFloat(ClomniTheme.Space.l)) {
                if let wordmark = header.wordmark {
                    WordmarkView(wordmark: wordmark, header: header, theme: theme, maxWidth: width * 0.6)
                } else {
                    BrandMark(header: header, theme: theme)
                }
                Spacer(minLength: 0)
                TeamAvatars(urls: header.teamAvatars, ring: theme.colors.headerFrom, theme: theme)
                CloseButton(label: header.closeLabel, color: ink, edge: CGFloat(ClomniTheme.Space.xxl), action: close)
            }
            .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
            // Both lines in the header's full colour, told apart by size and weight (BRIEF-DEVIATIONS #18), at the
            // panel's size (home.title_size). They wrap rather than shrink or cut off at large Dynamic Type sizes.
            VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.xxs)) {
                GreetingLine(text: header.greeting, size: header.titleSize.greeting, weight: .regular, style: .headline)
                GreetingLine(text: header.title, size: header.titleSize.title, weight: .semibold, style: .title2)
            }
            .padding(.top, 20)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .foregroundStyle(ink.color)
        .padding(.horizontal, CGFloat(ClomniTheme.Space.xxl))
        // 64 = the 40 the cards ride up + 24 of air above them.
        .padding(.bottom, 64)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { width = $0 }
        })
        .background {
            ZStack {
                if header.glow {
                    HeaderGlow(color: theme.colors.primary)
                }
                HeaderBackground(style: header.style, theme: theme)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    /// header_text: white over a picture (its dark veil), else white or near-black by the header's colours.
    private var ink: RGBColor {
        if case .image = header.style { return .white }
        return theme.colors.headerText
    }
}

/// The glow (APPEARANCE-CONTRACT 1): a soft radial light of the brand colour at 25% behind the header, so it shows
/// where it spills out under it, around the cards, whatever the header's style; as the panel's preview and Android
/// draw it: an ellipse 140% of the header's width and 260 pt tall, from 45% of the header's height down.
struct HeaderGlow: View {
    let color: RGBColor

    var body: some View {
        GeometryReader { proxy in
            EllipticalGradient(gradient: Gradient(colors: [color.color.opacity(0.25), .clear]),
                               center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                .frame(width: proxy.size.width * 1.4, height: 260)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.45 + 130)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Behind the header and the status bar: the brand gradient (header_from at the top to header_to; one colour when
/// solid) or the panel's picture under a black veil, 35% at the top to 55% at the bottom.
struct HeaderBackground: View {
    let style: HomeScreen.Style
    let theme: ClomniTheme

    var body: some View {
        ZStack {
            switch style {
            case .gradient, .solid:
                LinearGradient(gradient: Gradient(colors: [theme.colors.headerFrom.color, theme.colors.headerTo.color]),
                               startPoint: .top, endPoint: .bottom)
            case .image(let url):
                GeometryReader { proxy in
                    RemoteImage(url: url, kind: .header, points: proxy.size.width, theme: theme)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.55)]),
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One line of the greeting: `size` scaled with Dynamic Type, lines 1.25 times the size apart, wrapping.
struct GreetingLine: View {
    let text: String
    let size: Double
    let weight: Font.Weight
    let style: Font.TextStyle

    var body: some View {
        Text(text)
            .clomniFont(size, weight, relativeTo: style)
            // The system font's own line height is about 1.19 times its size; this makes it 1.25.
            .lineSpacing(CGFloat(size * (HomeScreen.TitleSize.lineHeight - 1.19)))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The logo as it is, 32 pt with 8 pt corners, no tile behind it; without one the initial in a 32 pt circle of the
/// brand's soft tone. The name 17 semibold, 10 pt to the right, both centred on one line.
struct BrandMark: View {
    let header: HomeScreen.Header
    let theme: ClomniTheme

    var body: some View {
        HStack(alignment: .center, spacing: CGFloat(ClomniTheme.Space.m)) {
            Group {
                // The dark-mode logo when the panel has one.
                if let logo = (theme.isDark ? header.logoDarkUrl : nil) ?? header.logoUrl {
                    RemoteImage(url: logo, kind: .icon, points: ClomniTheme.Size.logo, theme: theme, fit: true)
                        .clipShape(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.logo), style: .continuous))
                } else {
                    Text(header.brandInitial)
                        .clomniFixedFont(15, .semibold)
                        .foregroundStyle(theme.colors.primary.color)
                        .frame(width: CGFloat(ClomniTheme.Size.logo), height: CGFloat(ClomniTheme.Size.logo))
                        .background(Circle().fill(theme.colors.primarySoft.color))
                }
            }
            .frame(width: CGFloat(ClomniTheme.Size.logo), height: CGFloat(ClomniTheme.Size.logo))
            .accessibilityHidden(true)
            Text(header.brandName)
                .clomniFont(ClomniTheme.FontSize.brand, .semibold, relativeTo: .headline)
                .lineLimit(1)
        }
    }
}

/// The full logo in place of the logo and the name (APPEARANCE-CONTRACT § 4a): 32 pt high, at most 60% of the
/// header's width, fitted, never cut or stretched; the dark one in dark mode when there is one. Its height is held
/// while it loads; if it does not load, the logo and the name. VoiceOver reads the brand's name.
struct WordmarkView: View {
    let wordmark: HomeScreen.Wordmark
    let header: HomeScreen.Header
    let theme: ClomniTheme
    /// 60% of the header's width.
    let maxWidth: CGFloat
    @Environment(\.displayScale) private var scale
    @Environment(\.clomniLoadsRemoteImages) private var loadsImages
    @StateObject private var loader = ImageLoader()

    private var url: URL {
        let source = (theme.isDark ? wordmark.darkUrl : nil) ?? wordmark.url
        return ImageSizing.url(source, kind: .wordmark, points: Double(maxWidth), scale: Double(scale))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if loader.failed || !loadsImages {
                BrandMark(header: header, theme: theme)
            } else {
                // Its place, kept while it loads.
                Color.clear
            }
        }
        .frame(maxWidth: maxWidth, maxHeight: CGFloat(ClomniTheme.Size.wordmark), alignment: .leading)
        .frame(height: CGFloat(ClomniTheme.Size.wordmark))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(header.brandName))
        .task(id: url) {
            guard loadsImages else { return }
            await loader.load(url)
        }
    }
}

/// Up to three 24 pt avatars overlapping by 7, each ringed in the header's colour.
struct TeamAvatars: View {
    let urls: [URL]
    let ring: RGBColor
    let theme: ClomniTheme

    var body: some View {
        HStack(spacing: -CGFloat(ClomniTheme.Size.headerAvatarOverlap) - 4) {
            ForEach(urls, id: \.self) { url in
                AvatarView(url: url, initial: "", size: ClomniTheme.Size.headerAvatar, theme: theme)
                    .padding(2)
                    .background(Circle().fill(ring.color))
            }
        }
        .accessibilityHidden(true)
    }
}

/// ✕: a 28 pt icon (its cross 16 pt, as Android's 28 dp close icon draws it) in a 44 pt target, the icon 12 pt from
/// the screen's edge. `edge`: the side padding of the row it sits in, which the target reaches into.
struct CloseButton: View {
    let label: String
    let color: RGBColor
    var edge: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .resizable()
                .scaledToFit()
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 16, height: 16)
                .frame(width: CGFloat(ClomniTheme.Size.closeIcon), height: CGFloat(ClomniTheme.Size.closeIcon))
                .foregroundStyle(color.color)
                .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.trailing, Self.trailing(edge: edge))
        .accessibilityLabel(Text(label))
    }

    /// The icon 12 pt from the edge: the target is 8 pt wider than the icon on each side.
    static func trailing(edge: CGFloat) -> CGFloat {
        let overhang = (CGFloat(ClomniTheme.Size.touchTarget) - CGFloat(ClomniTheme.Size.closeIcon)) / 2
        return CGFloat(ClomniTheme.Space.l) - edge - overhang
    }
}

/// Skeleton, error, or the cards the config asks for.
struct HomeCardsView: View {
    let screen: HomeScreen
    let theme: ClomniTheme
    let actions: MessengerActions

    var body: some View {
        VStack(spacing: CGFloat(ClomniTheme.Space.m)) {
            switch screen.phase {
            case .loading:
                // No config yet: the neutral blocks, with the spinner over them once it takes a while.
                VStack(spacing: CGFloat(ClomniTheme.Space.m)) {
                    SkeletonBlock(height: 58, theme: theme)
                    SkeletonBlock(height: 74, theme: theme)
                }
                .accessibilityHidden(true)
                .overlay(LoadingIndicator(loading: true, label: screen.loadingLabel, theme: theme))
            case .failed:
                if let failure = screen.failure {
                    FailureView(failure: failure, theme: theme, retry: actions.retry)
                }
            case .ready:
                // In the panel's order.
                ForEach(screen.order, id: \.self) { card in
                    switch card {
                    case .send:
                        if let send = screen.newConversation {
                            NewConversationCardView(card: send, theme: theme, action: actions.newConversation)
                        }
                    case .recent:
                        if let recent = screen.recent {
                            RecentCardView(card: recent, theme: theme, open: actions.openConversation)
                        }
                    case .channels:
                        if let channels = screen.channels {
                            ChannelsCardView(card: channels, theme: theme)
                        }
                    }
                }
                if let poweredBy = screen.poweredBy {
                    Text(verbatim: poweredBy)
                        .clomniFont(ClomniTheme.FontSize.meta, relativeTo: .caption2)
                        .foregroundStyle(theme.colors.textSecondary.color)
                        .frame(maxWidth: .infinity)
                        .padding(.top, CGFloat(ClomniTheme.Space.s))
                }
            }
        }
        // Fades only, so Reduce Motion needs nothing else.
        .animation(.easeOut(duration: 0.2), value: screen.phase)
    }
}

/// "Bizə mesaj göndərin", the reply time, and the paper plane in the brand colour.
struct NewConversationCardView: View {
    let card: HomeScreen.NewConversationCard
    let theme: ClomniTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CGFloat(ClomniTheme.Space.l)) {
                VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.xxs)) {
                    Text(card.title)
                        .clomniFont(ClomniTheme.FontSize.text, .semibold)
                        .foregroundStyle(theme.colors.textPrimary.color)
                    if let subtitle = card.subtitle {
                        Text(subtitle)
                            .clomniFont(ClomniTheme.FontSize.secondary, relativeTo: .footnote)
                            .foregroundStyle(theme.colors.textSecondary.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.colors.primary.color)
            }
            .clomniCard(theme)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(card.accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }
}

/// "Son mesaj": the newest conversation's last message.
struct RecentCardView: View {
    let card: HomeScreen.RecentCard
    let theme: ClomniTheme
    let open: (String) -> Void

    var body: some View {
        Button {
            open(card.row.id)
        } label: {
            VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.s)) {
                Text(card.label)
                    .clomniFont(ClomniTheme.FontSize.label, .semibold, relativeTo: .caption)
                    .foregroundStyle(theme.colors.textPrimary.color)
                ConversationRowView(row: card.row, theme: theme)
            }
            .clomniCard(theme)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(card.label). \(card.row.accessibilityLabel)"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Avatar 28, the message on one line (13), "Ad · vaxt" (12.5, grey), and the red unread dot 7.
struct ConversationRowView: View {
    let row: ConversationRow
    let theme: ClomniTheme

    var body: some View {
        HStack(spacing: CGFloat(ClomniTheme.Space.m)) {
            AvatarView(url: row.avatarUrl, initial: row.initial, size: ClomniTheme.Size.avatar, theme: theme)
            VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.xxs)) {
                Text(row.preview)
                    .clomniFont(ClomniTheme.FontSize.preview)
                    .foregroundStyle(theme.colors.textPrimary.color)
                    .lineLimit(1)
                Text(row.detail)
                    .clomniFont(ClomniTheme.FontSize.secondary, relativeTo: .footnote)
                    .foregroundStyle(theme.colors.textSecondary.color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.unread {
                Circle()
                    .fill(theme.colors.unread.color)
                    .frame(width: CGFloat(ClomniTheme.Size.unreadDot), height: CGFloat(ClomniTheme.Size.unreadDot))
                    .accessibilityHidden(true)
            }
        }
    }
}

/// "Bizi izləyin": 30 pt squares (radius 8) with each platform's mark in its colour, 44 pt targets.
struct ChannelsCardView: View {
    let card: HomeScreen.ChannelsCard
    let theme: ClomniTheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.s)) {
            Text(card.label)
                .clomniFont(ClomniTheme.FontSize.label, .semibold, relativeTo: .caption)
                .foregroundStyle(theme.colors.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            icons
                .padding(.horizontal, -Self.overhang)
                .padding(.vertical, -Self.overhang)
        }
        .clomniCard(theme)
    }

    /// How far a 44 pt target reaches past its 30 pt square.
    private static let overhang = CGFloat(ClomniTheme.Size.touchTarget - ClomniTheme.Size.channel) / 2
    /// Between two targets, for squares 20 pt apart.
    private static let gap = CGFloat(ClomniTheme.Space.channelGap) - 2 * overhang

    /// The squares 20 pt apart, across and between rows, so their 44 pt targets never overlap; a row that is full
    /// continues on the next line.
    @ViewBuilder
    private var icons: some View {
        if #available(iOS 16.0, *) {
            WrapLayout(spacing: Self.gap, leading: true) {
                ForEach(card.items) { item in
                    ChannelButton(item: item, theme: theme) { openURL(item.url) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Self.gap) {
                ForEach(Array(card.rows().enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Self.gap) {
                        ForEach(row) { item in
                            ChannelButton(item: item, theme: theme) { openURL(item.url) }
                        }
                    }
                }
            }
        }
    }
}

struct ChannelButton: View {
    let item: ChannelItem
    let theme: ClomniTheme
    let action: () -> Void

    private var background: Color {
        switch item.glyph {
        case .brand(_, let color): return color.color
        case .symbol: return theme.colors.surface.color
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.channel), style: .continuous)
                    .fill(background)
                glyph
            }
            .frame(width: CGFloat(ClomniTheme.Size.channel), height: CGFloat(ClomniTheme.Size.channel))
            .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(Text(item.accessibilityLabel))
    }

    @ViewBuilder
    private var glyph: some View {
        switch item.glyph {
        case .brand(let path, _):
            SVGShape(svg: path)
                .fill(Color.white)
                .frame(width: 16, height: 16)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary.color)
        }
    }
}

/// An `SVGPath` drawn into the frame it is given, its 24×24 box scaled to fit and centred.
struct SVGShape: Shape {
    let svg: SVGPath
    var box: Double = 24

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / CGFloat(box)
        let dx = rect.minX + (rect.width - CGFloat(box) * scale) / 2
        let dy = rect.minY + (rect.height - CGFloat(box) * scale) / 2
        func point(_ p: SVGPath.Point) -> CGPoint {
            CGPoint(x: dx + CGFloat(p.x) * scale, y: dy + CGFloat(p.y) * scale)
        }
        var result = Path()
        for segment in svg.segments {
            switch segment {
            case .move(let to): result.move(to: point(to))
            case .line(let to): result.addLine(to: point(to))
            case .cubic(let first, let second, let to):
                result.addCurve(to: point(to), control1: point(first), control2: point(second))
            case .close: result.closeSubpath()
            }
        }
        return result
    }
}
#endif
