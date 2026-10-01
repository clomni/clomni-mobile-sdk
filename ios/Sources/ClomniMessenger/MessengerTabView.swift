#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// Hands the controller's screens to SwiftUI.
@MainActor
final class MessengerModel: ObservableObject {
    @Published private(set) var home: HomeScreen
    @Published private(set) var messages: MessagesScreen
    @Published private(set) var config: MessengerConfig?
    let controller: HomeController

    init(controller: HomeController) {
        self.controller = controller
        home = controller.home
        messages = controller.messages
        config = controller.config
        controller.onChange = { [weak self] in self?.sync() }
    }

    convenience init(engine: ClomniEngine, language: String?, userName: String?) {
        self.init(controller: HomeController(source: engine, language: language, userName: userName))
    }

    func load() async {
        await controller.load()
    }

    private func sync() {
        home = controller.home
        messages = controller.messages
        config = controller.config
    }
}

enum MessengerTab: Hashable {
    case home, messages
}

/// Home and Messages with the tab bar under them. Opening a conversation and closing the messenger are handed out
/// through `actions` (the conversation screen is CM-083, presenting CM-084).
struct MessengerTabView: View {
    @ObservedObject var model: MessengerModel
    /// `opened_from` of a conversation started here.
    let source: String?
    let close: () -> Void
    let openConversation: (String) -> Void
    @State private var tab = MessengerTab.home
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ClomniTheme {
        let brand = model.config?.brand
        let dark = ClomniTheme.isDark(brand?.theme, systemIsDark: colorScheme == .dark)
        return ClomniTheme.make(brand: brand, dark: dark)
    }

    private var actions: MessengerActions {
        MessengerActions(
            close: close,
            newConversation: { [model, source, openConversation] in
                Task { @MainActor in
                    if let id = await model.controller.startConversation(openedFrom: source) { openConversation(id) }
                }
            },
            openConversation: openConversation,
            retry: { [model] in
                Task { @MainActor in await model.controller.retry() }
            })
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .home:
                    HomeView(screen: model.home, theme: theme, actions: actions)
                case .messages:
                    MessagesView(screen: model.messages, theme: theme, closeLabel: model.home.header.closeLabel,
                                 actions: actions)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            TabBar(tabs: model.home.tabs, selected: $tab, theme: theme)
        }
        .background(theme.colors.background.color.ignoresSafeArea())
        // Text grows with Dynamic Type up to about twice its size.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .task { await model.load() }
    }
}

/// Ana səhifə, Mesajlar: icon 22, label 11; the active tab in the text colour and semibold; a red dot 8 on Mesajlar
/// while something is unread.
struct TabBar: View {
    let tabs: HomeScreen.Tabs
    @Binding var selected: MessengerTab
    let theme: ClomniTheme

    var body: some View {
        HStack(spacing: 0) {
            TabBarItem(title: tabs.home, accessibilityLabel: tabs.home, symbol: "house", selectedSymbol: "house.fill",
                       isSelected: selected == .home, showsDot: false, theme: theme) { selected = .home }
            TabBarItem(title: tabs.messages, accessibilityLabel: tabs.messagesAccessibilityLabel, symbol: "message",
                       selectedSymbol: "message.fill", isSelected: selected == .messages, showsDot: tabs.messagesUnread,
                       theme: theme) { selected = .messages }
        }
        .padding(.top, 9)
        .background(theme.colors.background.color.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.colors.border.color).frame(height: 1)
        }
    }
}

struct TabBarItem: View {
    let title: String
    let accessibilityLabel: String
    let symbol: String
    let selectedSymbol: String
    let isSelected: Bool
    let showsDot: Bool
    let theme: ClomniTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: CGFloat(ClomniTheme.Space.xxs)) {
                Image(systemName: isSelected ? selectedSymbol : symbol)
                    .font(.system(size: 19))
                    .frame(width: CGFloat(ClomniTheme.Size.tabIcon), height: CGFloat(ClomniTheme.Size.tabIcon))
                    .overlay(alignment: .topTrailing) {
                        if showsDot {
                            Circle()
                                .fill(theme.colors.unread.color)
                                .frame(width: CGFloat(ClomniTheme.Size.tabDot),
                                       height: CGFloat(ClomniTheme.Size.tabDot))
                                .overlay(Circle().stroke(theme.colors.background.color, lineWidth: 2))
                                .offset(x: 4, y: -1)
                        }
                    }
                Text(title)
                    .clomniFont(ClomniTheme.FontSize.meta, isSelected ? .semibold : .regular, relativeTo: .caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? theme.colors.textPrimary.color : theme.colors.textSecondary.color)
            .frame(maxWidth: .infinity, minHeight: CGFloat(ClomniTheme.Size.touchTarget))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
#endif
