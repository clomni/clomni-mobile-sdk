#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
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
                TeamAvatars(urls: header.teamAvatars, ring: theme.colors.primaryDark, theme: theme)
                CloseButton(label: header.closeLabel, color: theme.colors.onPrimary, action: close)
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
        .foregroundStyle(theme.colors.onPrimary.color)
        .padding(.horizontal, CGFloat(ClomniTheme.Space.xxl))
        // 62 = the 40 the cards ride up + 22 of air above them.
        .padding(.bottom, 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // The only gradient in the messenger: primaryDark at the top to primary, behind the status bar too.
            LinearGradient(gradient: Gradient(colors: [theme.colors.primaryDark.color, theme.colors.primary.color]),
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
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
                if let logo = header.logoUrl {
                    AsyncImage(url: logo) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit().padding(3)
                        } else {
                            Color.clear
                        }
                    }
                } else {
                    Text(header.brandInitial)
                        .font(.system(size: 13, weight: .bold))
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
                SkeletonBlock(height: 58, theme: theme)
                SkeletonBlock(height: 74, theme: theme)
            case .failed:
                if let failure = screen.failure {
                    FailureView(failure: failure, theme: theme, retry: actions.retry)
                }
            case .ready:
                if let card = screen.newConversation {
                    NewConversationCardView(card: card, theme: theme, action: actions.newConversation)
                }
                if let recent = screen.recent {
                    RecentCardView(card: recent, theme: theme, open: actions.openConversation)
                }
                if let channels = screen.channels {
                    ChannelsCardView(card: channels, theme: theme)
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
            // 44 pt targets 6 pt into each other keep the squares 8 pt apart.
            HStack(spacing: -6) {
                ForEach(card.items) { item in
                    ChannelButton(item: item, theme: theme) { openURL(item.url) }
                }
            }
            .padding(.horizontal, -7)
            .padding(.vertical, -7)
        }
        .clomniCard(theme)
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
