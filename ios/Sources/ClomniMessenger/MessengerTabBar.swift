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
    /// Over the icon, inside the tab: room for the badge, which stands half above the icon (CM-346).
    static let topInset: CGFloat = 7

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabBar.items) { item in
                let current = item.tab == selected
                Button { select(item.tab) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: Self.symbol(item.tab, filled: current))
                            .font(.system(size: Self.iconSize))
                            // On the glyph itself, so it is placed by the icon and not by the row.
                            .overlay(alignment: .top) {
                                if let badge = item.badge { TabBadge(text: badge, theme: theme) }
                            }
                            .frame(height: Self.iconSize + 4)
                        Text(item.title)
                            .clomniFont(Self.labelSize, current ? .semibold : .regular, relativeTo: .caption2)
                            .lineLimit(1)
                    }
                    .padding(.top, Self.topInset)
                    .padding(.bottom, 2)
                    .foregroundStyle((current ? theme.colors.textPrimary : theme.colors.textSecondary).color)
                    .frame(maxWidth: .infinity, minHeight: CGFloat(ClomniTheme.Size.touchTarget + 5), alignment: .top)
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

/// The unread count on the conversations' icon (CM-346; TestFlight #19 had it 18 pt and over the icon): white 11
/// semibold on the unread red, 16 high and at least a circle, 4 either side of the number; ringed 1.5 in the bar's
/// colour, which sets it off the icon in light and dark mode. Its left edge 4 right of the icon's centre and its middle
/// on the icon's top edge, so it covers less than half of the icon and stays inside its tab.
private struct TabBadge: View {
    static let height: CGFloat = 16
    static let ring: CGFloat = 1.5
    static let fromCentre: CGFloat = 4

    let text: String
    let theme: ClomniTheme

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(minWidth: Self.height)
            .frame(height: Self.height)
            .background(Capsule().fill(theme.colors.unread.color))
            .padding(Self.ring)
            .background(Capsule().fill(theme.colors.background.color))
            .fixedSize()
            .accessibilityHidden(true)
            // The ring's left edge 2.5 right of the icon's centre, so the red one is 4 right of it; the middle on top.
            .alignmentGuide(HorizontalAlignment.center) { _ in -(Self.fromCentre - Self.ring) }
            .alignmentGuide(VerticalAlignment.top) { $0.height / 2 }
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
