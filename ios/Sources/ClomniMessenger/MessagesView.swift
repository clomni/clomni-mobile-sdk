#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
#if canImport(ClomniCore)
import ClomniProtocol
import ClomniCore
#endif
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// The Messages tab: the conversations, newest first, under the same "Bizə mesaj göndərin" card as Home; an empty
/// list says "Hələ söhbət yoxdur".
struct MessagesView: View {
    let screen: MessagesScreen
    let theme: ClomniTheme
    let closeLabel: String
    let backLabel: String
    let actions: MessengerActions
    /// The list has moved up under the bar.
    @State private var scrolled = false

    var body: some View {
        VStack(spacing: 0) {
            MessagesTitleBar(title: screen.title, closeLabel: closeLabel, backLabel: backLabel, theme: theme,
                             showsDivider: scrolled, back: actions.back, close: actions.close)
            OfflineStrip(offline: screen.offline, connected: screen.connected, theme: theme)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
    }

    @ViewBuilder
    private var content: some View {
        switch screen.phase {
        case .loading:
            // The first time only; after that the list comes from the cache.
            LoadingIndicator(loading: true, label: screen.loadingLabel, theme: theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            if let failure = screen.failure {
                FailureView(failure: failure, theme: theme, retry: actions.retry)
                    .padding(CGFloat(ClomniTheme.Space.l))
            }
        case .ready:
            ScrollView {
                VStack(spacing: CGFloat(ClomniTheme.Space.m)) {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ScrollTopOffset.self,
                                               value: proxy.frame(in: .named(ScrollTopOffset.space)).minY)
                    }
                    .frame(height: 0)
                    NewConversationCardView(card: screen.newConversation, theme: theme, action: actions.newConversation)
                    if let empty = screen.empty {
                        // textPrimary: the secondary grey on the canvas is 4.32:1, under WCAG AA.
                        Text(empty)
                            .clomniFont(ClomniTheme.FontSize.text, .semibold)
                            .foregroundStyle(theme.colors.textPrimary.color)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, CGFloat(ClomniTheme.Space.xxl))
                    } else {
                        ConversationList(rows: screen.rows, theme: theme, open: actions.openConversation)
                    }
                }
                .padding(CGFloat(ClomniTheme.Space.l))
            }
            .coordinateSpace(name: ScrollTopOffset.space)
            .onPreferenceChange(ScrollTopOffset.self) { top in scrolled = top < -1 }
        }
    }
}

/// The bar: the title 17 semibold in the screen's centre, back and ✕ in equal slots on either side (both the 40 pt
/// circle), the same edges as every screen's bar; the 1 pt line under it once the list has scrolled.
struct MessagesTitleBar: View {
    let title: String
    let closeLabel: String
    let backLabel: String
    let theme: ClomniTheme
    var showsDivider = false
    let back: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                CircleBackButton(label: backLabel, theme: theme, action: back)
                Spacer(minLength: 0)
                CloseButton(label: closeLabel, theme: theme, action: close)
            }
            Text(title)
                .clomniFont(ClomniTheme.FontSize.brand, .semibold, relativeTo: .headline)
                .foregroundStyle(theme.colors.textPrimary.color)
                .lineLimit(1)
                // Clear of both slots, so it stays in the centre.
                .padding(.horizontal, CGFloat(ClomniTheme.Size.touchTarget + ClomniTheme.Space.s))
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, minHeight: CGFloat(ClomniTheme.Size.barRow))
        .padding(.horizontal, CGFloat(ClomniTheme.Size.barEdge) - ScreenBar<EmptyView>.overhang)
        .padding(.top, CGFloat(ClomniTheme.Size.barTop))
        .padding(.bottom, CGFloat(ClomniTheme.Size.barBottom))
        .background(theme.colors.background.color.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.border.color).frame(height: 1).opacity(showsDivider ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.15), value: showsDivider)
    }
}

/// How far the list has scrolled, from its content's top in the scroll view's space.
struct ScrollTopOffset: PreferenceKey {
    static let space = "clomni.messagesScroll"
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The conversations in one card, separated by hairlines.
struct ConversationList: View {
    let rows: [ConversationRow]
    let theme: ClomniTheme
    let open: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                Button {
                    open(row.id)
                } label: {
                    ConversationRowView(row: row, theme: theme)
                        .padding(.vertical, CGFloat(ClomniTheme.Space.m))
                        .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(row.accessibilityLabel))
                .accessibilityAddTraits(.isButton)
                if row.id != rows.last?.id {
                    Rectangle().fill(theme.colors.border.color).frame(height: 1)
                }
            }
        }
        .clomniCard(theme)
    }
}
#endif
