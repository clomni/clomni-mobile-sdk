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
    let actions: MessengerActions

    var body: some View {
        VStack(spacing: 0) {
            MessagesTitleBar(title: screen.title, closeLabel: closeLabel, theme: theme, close: actions.close)
            if let offline = screen.offline {
                OfflineStrip(text: offline, theme: theme)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(theme.colors.canvas.color.ignoresSafeArea())
    }

    @ViewBuilder
    private var content: some View {
        switch screen.phase {
        case .loading:
            VStack(spacing: CGFloat(ClomniTheme.Space.m)) {
                SkeletonBlock(height: 58, theme: theme)
                SkeletonBlock(height: 58, theme: theme)
                SkeletonBlock(height: 58, theme: theme)
            }
            .padding(CGFloat(ClomniTheme.Space.l))
            .loadingElement(screen.loadingLabel)
        case .failed:
            if let failure = screen.failure {
                FailureView(failure: failure, theme: theme, retry: actions.retry)
                    .padding(CGFloat(ClomniTheme.Space.l))
            }
        case .ready:
            ScrollView {
                VStack(spacing: CGFloat(ClomniTheme.Space.m)) {
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
        }
    }
}

/// White bar with the bottom hairline: the title 14.5/600 in the middle and ✕ at the end.
struct MessagesTitleBar: View {
    let title: String
    let closeLabel: String
    let theme: ClomniTheme
    let close: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .clomniFont(ClomniTheme.FontSize.title, .semibold, relativeTo: .headline)
                .foregroundStyle(theme.colors.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Spacer()
                CloseButton(label: closeLabel, color: theme.colors.textPrimary, edge: CGFloat(ClomniTheme.Space.xxl),
                            action: close)
            }
        }
        .padding(.horizontal, CGFloat(ClomniTheme.Space.xxl))
        .frame(minHeight: CGFloat(ClomniTheme.Size.touchTarget))
        .background(theme.colors.background.color.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.colors.border.color).frame(height: 1)
        }
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
