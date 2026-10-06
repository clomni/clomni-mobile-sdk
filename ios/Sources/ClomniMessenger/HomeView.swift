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
    /// Home's "Mesajlar" card.
    var openMessages: () -> Void = {}
    /// An item of Home's news card.
    var openNews: (String) -> Void = { _ in }
    var back: () -> Void = {}
    var retry: () -> Void = {}
}

/// Home (DESIGN-PASS-2, Intercom's layout): no header block. The brand's colour runs full under the logo and the
/// greeting and 16 pt past them, then fades into the page over 160 pt, where the cards start; text never stands in
/// the fade. The logo top left and ✕ top right. No tab bar: the "Mesajlar" card leads to the conversations.
struct HomeView: View {
    let screen: HomeScreen
    let theme: ClomniTheme
    let actions: MessengerActions
    /// The logo and greeting block's height: the full colour reaches 16 pt past it, the fade 160 pt further.
    @State private var block: CGFloat = 200

    static let fullPast: CGFloat = 16
    static let fade: CGFloat = 160

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HomeTopBar(header: screen.header, theme: theme, close: actions.close, width: proxy.size.width)
                        GreetingView(header: screen.header, theme: theme)
                            .frame(maxWidth: proxy.size.width * 0.8, alignment: .leading)
                            .padding(.horizontal, CGFloat(ClomniTheme.Size.barEdge))
                            .padding(.top, CGFloat(ClomniTheme.Space.xxxl))
                    }
                    .background(GeometryReader { measured in
                        Color.clear
                            .onAppear { block = measured.size.height }
                            .onChange(of: measured.size.height) { block = $0 }
                    })
                    .padding(.bottom, Self.fullPast)
                    HomeCardsView(screen: screen, theme: theme, actions: actions)
                        .padding(.horizontal, CGFloat(ClomniTheme.Size.barEdge))
                        .padding(.bottom, CGFloat(ClomniTheme.Space.xxl))
                }
                .padding(.top, proxy.safeAreaInsets.top)
                .background(alignment: .top) {
                    let full = proxy.safeAreaInsets.top + block + Self.fullPast
                    HomeBackground(style: screen.header.style, glow: screen.header.glow, theme: theme,
                                   solidShare: full / (full + Self.fade))
                        .frame(height: full + Self.fade)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        // 8 under the logo's 48 pt row, which starts 16 under the safe area; it stays there as the page scrolls.
        .overlay(alignment: .top) {
            OfflineCapsule(offline: screen.offline, connected: screen.connected, theme: theme)
                .padding(.top, CGFloat(ClomniTheme.Size.barTop + ClomniTheme.Size.barRow) + 8)
        }
        // The page: canvas grey in light mode (the white cards stand on it, the fade ends in it), background in dark.
        .background((theme.isDark ? theme.colors.background : theme.colors.canvas).color.ignoresSafeArea())
    }
}

/// The brand's colour from the top, fading into the page by its bottom: top left the brand, to the right a little
/// lighter (a gradient header); one colour for a solid one; the panel's picture for an image, under its veil. Pulled
/// down past the top, the colour goes on above.
struct HomeBackground: View {
    let style: HomeScreen.Style
    let glow: Bool
    let theme: ClomniTheme
    /// The share of the height in full colour; the rest fades.
    var solidShare: CGFloat = 0.5

    var body: some View {
        ZStack {
            switch style {
            case .gradient:
                LinearGradient(colors: [theme.colors.headerFrom.color, theme.colors.headerFrom.lighter.color],
                               startPoint: .topLeading, endPoint: .trailing)
            case .solid:
                theme.colors.headerFrom.color
            case .image(let url):
                GeometryReader { proxy in
                    RemoteImage(url: url, kind: .header, points: proxy.size.width, theme: theme)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.15)],
                               startPoint: .top, endPoint: .bottom)
            }
            if glow {
                HeaderGlow(color: theme.colors.primary)
            }
        }
        // Into the page: full colour for the top half, gone at the bottom.
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: solidShare),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .background(alignment: .top) {
            theme.colors.headerFrom.color
                .frame(height: 1000)
                .offset(y: -1000)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension RGBColor {
    /// A step lighter, for the gradient's right side.
    var lighter: RGBColor { steps(1) }
}

/// The logo top left (nothing when there is none, as Intercom: no initial), the team's faces 12 pt before ✕ top
/// right, all on the bar's centre line, on Home's colours.
struct HomeTopBar: View {
    let header: HomeScreen.Header
    let theme: ClomniTheme
    let close: () -> Void
    let width: CGFloat

    var body: some View {
        // Its circle 8 pt above the bar's end, as before the row grew to 48.
        ScreenBar(closeLabel: header.closeLabel, closeStyle: .onBrand, theme: theme, close: close,
                  below: CGFloat(ClomniTheme.Space.s - (ClomniTheme.Size.barRow - ClomniTheme.Size.closeCircle) / 2)) {
            Group {
                if let wordmark = header.wordmark {
                    WordmarkView(wordmark: wordmark, header: header, theme: theme, maxWidth: width * 0.6)
                } else if let logo = (theme.isDark ? header.logoDarkUrl : nil) ?? header.logoUrl {
                    RemoteImage(url: logo, kind: .icon, points: CGFloat(header.logoHeight), theme: theme, fit: true,
                                placeholder: .clear)
                        .frame(width: CGFloat(header.logoHeight), height: CGFloat(header.logoHeight))
                        .clipShape(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.logo), style: .continuous))
                        .accessibilityLabel(Text(header.brandName))
                }
            }
            .padding(.leading, ScreenBar<EmptyView>.overhang)
            if !header.teamAvatars.isEmpty {
                Spacer(minLength: 0)
                // 12 pt from ✕'s circle: the bar's 8 pt gap and the 2 pt its target reaches past the circle, plus 2.
                TeamAvatars(urls: header.teamAvatars, ring: theme.colors.headerFrom, theme: theme)
                    .padding(.trailing, 12 - CGFloat(ClomniTheme.Space.s) - ScreenBar<EmptyView>.overhang)
            }
        }
    }
}

/// "Salam, Aysel" over "Necə kömək edə bilərik?": 28 semibold in the header's text colour at 72%, then 28 bold at
/// full; both at the panel's scale, 1.2 line height, wrapping, scaled further by Dynamic Type. Always on the full
/// brand colour (coordinator's decision, 2026-10-03).
struct GreetingView: View {
    let header: HomeScreen.Header
    let theme: ClomniTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GreetingLine(text: header.greeting, size: header.titleSize.greeting, weight: .semibold, style: .title)
                .foregroundStyle(ink.color.opacity(0.72))
            GreetingLine(text: header.title, size: header.titleSize.title, weight: .bold, style: .title)
                .foregroundStyle(ink.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// header_text: white over a picture (its dark veil), else white or near-black by the brand's colours.
    private var ink: RGBColor {
        if case .image = header.style { return .white }
        return theme.colors.headerText
    }
}

/// One line of the greeting: `size` scaled with Dynamic Type, lines 1.2 times the size apart, wrapping.
struct GreetingLine: View {
    let text: String
    let size: Double
    let weight: Font.Weight
    let style: Font.TextStyle

    var body: some View {
        Text(text)
            .clomniFont(size, weight, relativeTo: style)
            // The system font's own line height is about 1.19 times its size.
            .lineSpacing(CGFloat(max(0, size * (HomeScreen.TitleSize.lineHeight - 1.19))))
            .fixedSize(horizontal: false, vertical: true)
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
                // No full logo: the place stays empty, as without a logo.
                Color.clear
            } else {
                // Its place, kept while it loads.
                Color.clear
            }
        }
        .frame(maxWidth: maxWidth, maxHeight: CGFloat(header.logoHeight), alignment: .leading)
        .frame(height: CGFloat(header.logoHeight))
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
                // In the panel's order; the first time they show, 30 ms apart, each rising 8 and fading in (M8).
                ForEach(Array(screen.order.enumerated()), id: \.element) { index, card in
                    Group {
                        switch card {
                        case .messages:
                            MessagesCardView(card: screen.messagesCard, theme: theme, action: actions.openMessages)
                        case .news:
                            if let news = screen.news {
                                NewsCardView(card: news, theme: theme, open: actions.openNews)
                            }
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
                    .entrance(rise: 8, delay: 0.03 * Double(index))
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

/// A card's title, 17 semibold.
struct CardTitle: View {
    let text: String
    let theme: ClomniTheme

    var body: some View {
        Text(text)
            .clomniFont(ClomniTheme.FontSize.brand, .semibold, relativeTo: .headline)
            .foregroundStyle(theme.colors.textPrimary.color)
    }
}

/// "Mesajlar" with the conversations icon (20) and the red dot while something is unread: the way to the list.
struct MessagesCardView: View {
    let card: HomeScreen.MessagesCard
    let theme: ClomniTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CGFloat(ClomniTheme.Space.l)) {
                CardTitle(text: card.title, theme: theme)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: CGFloat(ClomniTheme.Size.cardIcon)))
                    .foregroundStyle(theme.colors.textPrimary.color)
                    .overlay(alignment: .topTrailing) {
                        if card.unread {
                            Circle()
                                .fill(theme.colors.unread.color)
                                .frame(width: CGFloat(ClomniTheme.Size.tabDot), height: CGFloat(ClomniTheme.Size.tabDot))
                                .offset(x: 3, y: -3)
                        }
                    }
            }
            .clomniCard(theme)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(card.accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }
}

/// "Bizə mesaj göndərin" and the paper plane (20) in the brand's colour, the main action.
struct NewConversationCardView: View {
    let card: HomeScreen.NewConversationCard
    let theme: ClomniTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CGFloat(ClomniTheme.Space.l)) {
                CardTitle(text: card.title, theme: theme)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: CGFloat(ClomniTheme.Size.cardIcon)))
                    .foregroundStyle(theme.colors.primary.color)
            }
            .clomniCard(theme)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
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
            VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.l)) {
                CardTitle(text: card.label, theme: theme)
                ConversationRowView(row: card.row, theme: theme)
            }
            .clomniCard(theme)
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
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

/// "Bizi izləyin" (DESIGN-PASS-3 D2): the title 17 semibold, then at most five 44 pt circles 12 apart from the start,
/// each the network's monochrome mark (22 pt) in the text colour on canvas, on background in dark mode; no
/// brand-coloured squares. Each circle is its own 44 pt target.
struct ChannelsCardView: View {
    let card: HomeScreen.ChannelsCard
    let theme: ClomniTheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.m)) {
            CardTitle(text: card.label, theme: theme)
                .accessibilityAddTraits(.isHeader)
            icons
        }
        .clomniCard(theme)
    }

    private static let gap = CGFloat(ClomniTheme.Space.m)

    /// The circles 12 pt apart, across and between rows; a row that is full continues on the next line.
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

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(theme.colors.textPrimary.color)
                .frame(width: CGFloat(ClomniTheme.Size.channel), height: CGFloat(ClomniTheme.Size.channel))
                .contentShape(Circle())
        }
        .buttonStyle(ChannelCircleStyle(theme: theme))
        .accessibilityLabel(Text(item.accessibilityLabel))
    }

    @ViewBuilder
    private var glyph: some View {
        switch item.glyph {
        case .brand(let path):
            SVGShape(svg: path)
                .fill(theme.colors.textPrimary.color)
                .frame(width: 22, height: 22)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 19, weight: .regular))
                .frame(width: 22, height: 22)
        }
    }
}

/// The circle under a channel's mark: canvas (background in dark mode), the text colour at 10% while pressed.
private struct ChannelCircleStyle: ButtonStyle {
    let theme: ClomniTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(configuration.isPressed
                ? theme.colors.textPrimary.color.opacity(0.10)
                : (theme.isDark ? theme.colors.background : theme.colors.canvas).color))
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
