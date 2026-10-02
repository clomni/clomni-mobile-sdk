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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CGFloat(ClomniTheme.Space.l)) {
                BrandMark(header: header, theme: theme)
                Spacer(minLength: 0)
                TeamAvatars(urls: header.teamAvatars, ring: theme.colors.headerFrom, theme: theme)
                CloseButton(label: header.closeLabel, color: ink, action: close)
            }
            .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
            VStack(alignment: .leading, spacing: 0) {
                Text(header.greeting).opacity(0.62)
                Text(header.title)
            }
            .clomniFont(ClomniTheme.FontSize.greeting, .semibold, relativeTo: .title2)
            .padding(.top, 20)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .foregroundStyle(ink.color)
        .padding(.horizontal, CGFloat(ClomniTheme.Space.xxl))
        // 62 = the 40 the cards ride up + 22 of air above them.
        .padding(.bottom, 62)
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// The 22 pt white square with the logo (or the brand's initial) and the brand name 17/700.
struct BrandMark: View {
    let header: HomeScreen.Header
    let theme: ClomniTheme

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.logo), style: .continuous)
                    .fill(Color.white)
                // The dark-mode logo when the panel has one.
                if let logo = (theme.isDark ? header.logoDarkUrl : nil) ?? header.logoUrl {
                    RemoteImage(url: logo, kind: .icon, points: ClomniTheme.Size.logo, theme: theme, fit: true)
                        .padding(3)
                } else {
                    Text(header.brandInitial)
                        .clomniFixedFont(13, .bold)
                        .foregroundStyle(theme.colors.primary.color)
                }
            }
            .frame(width: CGFloat(ClomniTheme.Size.logo), height: CGFloat(ClomniTheme.Size.logo))
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.logo), style: .continuous))
            .accessibilityHidden(true)
            Text(header.brandName)
                .clomniFont(ClomniTheme.FontSize.brand, .bold, relativeTo: .headline)
                .lineLimit(1)
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

/// ✕: a 14 pt glyph in a 44 pt target.
struct CloseButton: View {
    let label: String
    let color: RGBColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color.color)
                .frame(width: CGFloat(ClomniTheme.Size.touchTarget), height: CGFloat(ClomniTheme.Size.touchTarget))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        // The target reaches into the header's margin so the glyph lines up with the edge.
        .padding(.trailing, -15)
        .accessibilityLabel(Text(label))
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
                VStack(spacing: CGFloat(ClomniTheme.Space.m)) {
                    SkeletonBlock(height: 58, theme: theme)
                    SkeletonBlock(height: 74, theme: theme)
                }
                .loadingElement(screen.loadingLabel)
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
                VStack(alignment: .leading, spacing: 1) {
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
            VStack(alignment: .leading, spacing: 1) {
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
                .padding(.horizontal, -7)
                .padding(.vertical, -7)
        }
        .clomniCard(theme)
    }

    /// 44 pt targets 6 pt into each other keep the squares 8 pt apart, across and between rows; a row that is full
    /// continues on the next line.
    @ViewBuilder
    private var icons: some View {
        if #available(iOS 16.0, *) {
            WrapLayout(spacing: -6, leading: true) {
                ForEach(card.items) { item in
                    ChannelButton(item: item, theme: theme) { openURL(item.url) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: -6) {
                ForEach(Array(card.rows().enumerated()), id: \.offset) { _, row in
                    HStack(spacing: -6) {
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
