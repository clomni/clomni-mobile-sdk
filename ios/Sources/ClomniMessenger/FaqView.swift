#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// Home's FAQ card (SDK 1.0.7): "Tez-tez verilən suallar", the first three questions as rows between hairlines, and
/// "Hamısı" while there are more. A question opens its answer.
struct FaqCardView: View {
    let card: HomeScreen.FaqCard
    let theme: ClomniTheme
    let open: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(text: card.title, theme: theme)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, CGFloat(ClomniTheme.Space.xs))
            ForEach(card.items) { item in
                if item.id != card.items.first?.id {
                    Rectangle().fill(theme.colors.border.color).frame(height: 1)
                }
                FaqRow(question: item.question, theme: theme) { open(item.id) }
            }
            if let seeAll = card.seeAll {
                SeeAllLink(label: seeAll, theme: theme) { open(nil) }
                    .padding(.top, CGFloat(ClomniTheme.Space.xl))
            }
        }
        .clomniCard(theme)
    }
}

/// A question: 14 in the text colour over two lines at most, the chevron at its end, its own 44 pt target.
private struct FaqRow: View {
    let question: String
    let theme: ClomniTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CGFloat(ClomniTheme.Space.m)) {
                Text(question)
                    .clomniFont(ClomniTheme.FontSize.text, relativeTo: .subheadline)
                    .foregroundStyle(theme.colors.textPrimary.color)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary.color)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, CGFloat(ClomniTheme.Space.m))
            .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
            .contentShape(Rectangle())
        }
        .buttonStyle(SoftPressStyle())
    }
}

/// The FAQ's questions (SDK 1.0.7): the bar with "Tez-tez verilən suallar", the search field, the questions in one
/// card; a question opens its answer on a screen of its own (the news item's). The search runs on the device, over
/// questions and answers: "Heç nə tapılmadı" when it finds none, "Hələ sual yoxdur" when there are none at all.
struct FaqListView: View {
    let screen: FaqScreen
    let theme: ClomniTheme
    let actions: MessengerActions
    /// The FAQ tab's list: no back, the tab bar under it.
    var isTab = false
    @State private var query = ""

    var body: some View {
        let entries = screen.matching(query)
        VStack(spacing: 0) {
            MessagesTitleBar(title: screen.title, closeLabel: screen.closeLabel, backLabel: screen.backLabel,
                             theme: theme, back: isTab ? nil : actions.back, close: actions.close)
            ScrollView {
                VStack(spacing: CGFloat(ClomniTheme.Space.m)) {
                    if !screen.entries.isEmpty { search }
                    if entries.isEmpty {
                        Text(screen.entries.isEmpty ? screen.empty : screen.noResults)
                            .clomniFont(ClomniTheme.FontSize.text, .semibold)
                            .foregroundStyle(theme.colors.textPrimary.color)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, CGFloat(ClomniTheme.Space.xxl))
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(entries) { entry in
                                if entry.id != entries.first?.id {
                                    Rectangle().fill(theme.colors.border.color).frame(height: 1)
                                }
                                FaqRow(question: entry.question, theme: theme) { actions.openFaq(entry.id) }
                            }
                        }
                        .clomniCard(theme)
                    }
                }
                .padding(CGFloat(ClomniTheme.Space.l))
            }
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
        .messengerTabBar(isTab ? screen.tabBar : nil, selected: .faq, theme: theme, select: actions.selectTab)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    /// "Sual axtarın": radius 10 on the page, the magnifier in front.
    private var search: some View {
        HStack(spacing: CGFloat(ClomniTheme.Space.s)) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(theme.colors.textSecondary.color)
                .accessibilityHidden(true)
            TextField(screen.searchPlaceholder, text: $query)
                .clomniFont(ClomniTheme.FontSize.text)
                .foregroundStyle(theme.colors.textPrimary.color)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .accessibilityIdentifier("clomni.faq.search")
        }
        .padding(.horizontal, CGFloat(ClomniTheme.Space.m))
        .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill((theme.isDark ? theme.colors.surface : theme.colors.background).color))
    }
}
#endif
