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
/// and the summary 14 on two lines; a tap opens the item. "Hamısı" under them when the card does not hold them all
/// (SDK 1.0.7). The news list draws all of them in one card.
struct NewsCardView: View {
    let card: HomeScreen.NewsCard
    let theme: ClomniTheme
    let open: (String) -> Void
    var seeAll: () -> Void = {}

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
                .buttonStyle(SoftPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(item.accessibilityLabel))
                .accessibilityAddTraits(.isButton)
            }
            if let label = card.seeAll {
                SeeAllLink(label: label, theme: theme, action: seeAll)
            }
        }
        .clomniCard(theme)
    }
}

/// "Hamısı" at the bottom of a Home card: 14 semibold in the text colour with a small chevron, its own 44 pt target.
struct SeeAllLink: View {
    let label: String
    let theme: ClomniTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CGFloat(ClomniTheme.Space.xs)) {
                Text(label)
                    .clomniFont(ClomniTheme.FontSize.text, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(theme.colors.textPrimary.color)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary.color)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
        .padding(.vertical, -CGFloat(ClomniTheme.Space.m))
        .accessibilityAddTraits(.isButton)
    }
}

/// Every published news item (SDK 1.0.7), from Home's "Hamısı" or the news tab: the bar with "Xəbərlər", the items as
/// Home's card draws them; a tap opens one.
struct NewsListView: View {
    let screen: NewsListScreen
    let theme: ClomniTheme
    let actions: MessengerActions
    /// The news tab's list: no back, the tab bar under it.
    var isTab = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            MessagesTitleBar(title: screen.title, closeLabel: screen.closeLabel, backLabel: screen.backLabel,
                             theme: theme, back: isTab ? nil : actions.back, close: actions.close)
            // Nothing yet: the spinner in the middle; the items fade in over it (CM-346).
            ZStack {
                if screen.loading {
                    LoadingIndicator(loading: true, label: screen.loadingLabel, theme: theme)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else {
                    ScrollView {
                        if !screen.items.isEmpty {
                            NewsCardView(card: screen.card, theme: theme, open: actions.openNews)
                                .padding(CGFloat(ClomniTheme.Space.l))
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: StackTransition.fadeInSeconds), value: screen.loading)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .messengerTabBar(isTab ? screen.tabBar : nil, selected: .news, theme: theme, select: actions.selectTab)
    }
}

/// A news item (DESIGN-PASS-2 "Xəbərlər"): the cover, the title 24 bold, the date 13, the text with its markdown and
/// lists, and the button, whose link goes to the app's `onLink` (the system opens it without one).
struct NewsScreenView: View {
    @ObservedObject var model: MessengerModel
    let id: String
    let coordinator: MessengerCoordinator
    /// An FAQ answer (SDK 1.0.7): the question as the title, the answer as the text; reported as faq_opened.
    var faqAnswer = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.clomniThemeOverride) private var themeOverride
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: ClomniTheme {
        ClomniTheme.make(config: model.config, systemIsDark: colorScheme == .dark, override: themeOverride)
    }

    var body: some View {
        let article = faqAnswer ? model.controller.faqAnswer(id) : model.controller.article(id)
        let loading = article == nil && (faqAnswer ? model.faq.loading : model.newsList.loading)
        VStack(spacing: 0) {
            ScreenBar(closeLabel: article?.closeLabel ?? model.home.header.closeLabel, theme: theme,
                      close: { coordinator.dismiss() }) {
                CircleBackButton(label: article?.backLabel ?? "", theme: theme, action: { coordinator.back() })
            }
            .background(theme.colors.background.color.ignoresSafeArea(edges: .top))
            // Not here yet: the spinner in the middle, and the item fades in over it (CM-346).
            ZStack {
                if let article {
                    ScrollView {
                        content(article)
                            .padding(.horizontal, CGFloat(ClomniTheme.Size.barEdge))
                            .padding(.bottom, CGFloat(ClomniTheme.Space.xxxl))
                    }
                    .task {
                        if faqAnswer { await model.controller.faqOpened(id) } else { await model.controller.opened(article) }
                    }
                    .transition(.opacity)
                } else if loading {
                    LoadingIndicator(loading: true, label: model.newsList.loadingLabel, theme: theme)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? nil : .easeOut(duration: StackTransition.fadeInSeconds), value: article == nil)
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
                if !article.date.isEmpty {
                    Text(article.date)
                        .clomniFont(13, relativeTo: .footnote)
                        .foregroundStyle(theme.colors.textSecondary.color)
                }
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
                .buttonStyle(SoftPressStyle())
                .padding(.top, CGFloat(ClomniTheme.Space.s))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
