#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// Home's news card: each item with its 16:9 cover (radius 12) when it has one, the title 16 semibold on two lines
/// and the summary 14 on two lines; a tap opens the item.
struct NewsCardView: View {
    let card: HomeScreen.NewsCard
    let theme: ClomniTheme
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.xxl)) {
            ForEach(card.items) { item in
                Button {
                    open(item.id)
                } label: {
                    VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.s)) {
                        if let image = item.imageUrl {
                            Color.clear
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .overlay(RemoteImage(url: image, kind: .header, points: 360, theme: theme))
                                .clipShape(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.card),
                                                            style: .continuous))
                        }
                        Text(item.title)
                            .clomniFont(16, .semibold, relativeTo: .headline)
                            .foregroundStyle(theme.colors.textPrimary.color)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let summary = item.summary {
                            Text(summary)
                                .clomniFont(ClomniTheme.FontSize.text, relativeTo: .subheadline)
                                .foregroundStyle(theme.colors.textSecondary.color)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(item.accessibilityLabel))
                .accessibilityAddTraits(.isButton)
            }
        }
        .clomniCard(theme)
    }
}

/// A news item (DESIGN-PASS-2 "Xəbərlər"): the cover, the title 24 bold, the date 13, the text with its markdown and
/// lists, and the button, whose link goes to the app's `onLink` (the system opens it without one).
struct NewsScreenView: View {
    @ObservedObject var model: MessengerModel
    let id: String
    let coordinator: MessengerCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clomniThemeOverride) private var themeOverride
    @Environment(\.openURL) private var openURL

    private var theme: ClomniTheme {
        ClomniTheme.make(config: model.config, systemIsDark: colorScheme == .dark, override: themeOverride)
    }

    var body: some View {
        let article = model.controller.article(id)
        VStack(spacing: 0) {
            ScreenBar(closeLabel: article?.closeLabel ?? model.home.header.closeLabel, theme: theme,
                      close: { coordinator.dismiss() }) {
                CircleBackButton(label: article?.backLabel ?? "", theme: theme, action: { coordinator.back() })
            }
            .background(theme.colors.background.color.ignoresSafeArea(edges: .top))
            if let article {
                ScrollView {
                    content(article)
                        .padding(.horizontal, CGFloat(ClomniTheme.Size.barEdge))
                        .padding(.bottom, CGFloat(ClomniTheme.Space.xxxl))
                }
                .task { await model.controller.opened(article) }
            }
            Spacer(minLength: 0)
        }
        .background(theme.colors.background.color.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    private func content(_ article: NewsArticle) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.l)) {
            if let image = article.imageUrl {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(RemoteImage(url: image, kind: .header, points: 390, theme: theme))
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.card), style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: CGFloat(ClomniTheme.Space.xxs)) {
                Text(article.title)
                    .clomniFont(24, .bold, relativeTo: .title)
                    .foregroundStyle(theme.colors.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Text(article.date)
                    .clomniFont(13, relativeTo: .footnote)
                    .foregroundStyle(theme.colors.textSecondary.color)
            }
            ForEach(Array(article.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let runs):
                    Text(attributedText(runs))
                        .clomniFont(16, relativeTo: .body)
                        .foregroundStyle(theme.colors.textPrimary.color)
                        .tint(theme.colors.primary.color)
                case .listItem(let runs):
                    HStack(alignment: .firstTextBaseline, spacing: CGFloat(ClomniTheme.Space.s)) {
                        Text(verbatim: "•").accessibilityHidden(true)
                        Text(attributedText(runs))
                    }
                    .clomniFont(16, relativeTo: .body)
                    .foregroundStyle(theme.colors.textPrimary.color)
                    .tint(theme.colors.primary.color)
                }
            }
            if let button = article.button {
                Button {
                    if let link = ClomniShared.state.read({ $0.events.link }) {
                        link(button.url)
                    } else {
                        openURL(button.url)
                    }
                } label: {
                    Text(button.text)
                        .clomniFont(ClomniTheme.FontSize.brand, .semibold, relativeTo: .headline)
                        .foregroundStyle(theme.colors.onPrimary.color)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: CGFloat(ClomniTheme.Radius.card), style: .continuous)
                            .fill(theme.colors.primary.color))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, CGFloat(ClomniTheme.Space.s))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
