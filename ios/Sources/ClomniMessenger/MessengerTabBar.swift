#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// The tabs under a list screen (config home.tab_bar, SDK 1.0.7; brief 7.3): icon 22, label 11, the screen's own tab
/// in text_primary semibold and the others in text_secondary; the conversations' unread count on their icon. A
/// hairline over it, the page's background under the home indicator.
struct MessengerTabBarView: View {
    let tabBar: TabBar
    let selected: TabBar.Tab
    let theme: ClomniTheme
    let select: (TabBar.Tab) -> Void

    static let iconSize: CGFloat = 22
    static let labelSize = 11.0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabBar.items) { item in
                let current = item.tab == selected
                Button { select(item.tab) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: Self.symbol(item.tab, filled: current))
                            .font(.system(size: Self.iconSize))
                            .frame(height: Self.iconSize + 4)
                            .overlay(alignment: .topTrailing) {
                                if let badge = item.badge { TabBadge(text: badge, theme: theme) }
                            }
                        Text(item.title)
                            .clomniFont(Self.labelSize, current ? .semibold : .regular, relativeTo: .caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle((current ? theme.colors.textPrimary : theme.colors.textSecondary).color)
                    .frame(maxWidth: .infinity, minHeight: CGFloat(ClomniTheme.Size.touchTarget + 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(item.accessibilityLabel))
                .accessibilityAddTraits(current ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("clomni.tab.\(item.tab.rawValue)")
            }
        }
        .padding(.horizontal, CGFloat(ClomniTheme.Space.s))
        .padding(.top, 2)
        .background(theme.colors.background.color.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(theme.colors.border.color).frame(height: 0.5) }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// SF Symbols, filled for the screen's own tab.
    static func symbol(_ tab: TabBar.Tab, filled: Bool) -> String {
        let name: String
        switch tab {
        case .home: name = "house"
        case .messages: name = "bubble.left"
        case .news: name = "megaphone"
        case .faq: name = "questionmark.circle"
        }
        return filled ? name + ".fill" : name
    }
}

/// The unread count on the conversations' tab: white 11 semibold on the unread red, at least a circle.
private struct TabBadge: View {
    let text: String
    let theme: ClomniTheme

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(theme.colors.unread.color))
            .fixedSize()
            .offset(x: 12, y: -6)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The tab bar under a list screen when there is one (`tabBar`) and this screen is a tab's list (`selected`).
    @ViewBuilder
    func messengerTabBar(_ tabBar: TabBar?, selected: TabBar.Tab?, theme: ClomniTheme,
                         select: @escaping (TabBar.Tab) -> Void) -> some View {
        if let tabBar, let selected {
            safeAreaInset(edge: .bottom, spacing: 0) {
                MessengerTabBarView(tabBar: tabBar, selected: selected, theme: theme, select: select)
            }
        } else {
            self
        }
    }
}
#endif
