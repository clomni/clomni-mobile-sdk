#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(ClomniPresentation)
import ClomniPresentation
#endif

/// iOS has no emoji picker of its own to show (DESIGN-PASS-3 A6): a sheet with the recently used ones first, then
/// eight categories of the common emoji, a tab per category. The list is small and fixed (500), so the SDK stays
/// small; the keyboard's own emoji are always there for the rest.
struct EmojiPickerSheet: View {
    let title: String
    let theme: ClomniTheme
    let pick: (String) -> Void
    @State private var recent: [String] = []
    @State private var section = 0

    private var sections: [(icon: String, emoji: [String])] {
        (recent.isEmpty ? [] : [("🕘", recent)]) + EmojiCatalog.categories.map { ($0.emoji.first ?? "", $0.emoji) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .clomniFont(ClomniTheme.FontSize.brand, .semibold, relativeTo: .headline)
                .foregroundStyle(theme.colors.textPrimary.color)
                .padding(.vertical, CGFloat(ClomniTheme.Space.m))
                .accessibilityAddTraits(.isHeader)
            tabs
            Rectangle().fill(theme.colors.border.color).frame(height: 1)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 4)], spacing: 4) {
                    ForEach(sections.indices.contains(section) ? sections[section].emoji : [], id: \.self) { emoji in
                        Button { choose(emoji) } label: {
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(PressShapeStyle(shape: Circle()))
                    }
                }
                .padding(CGFloat(ClomniTheme.Space.m))
            }
        }
        .background(theme.colors.background.color.ignoresSafeArea())
        .task {
            recent = await Task.detached(priority: .userInitiated) { EmojiCatalog.loadRecent() }.value
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(sections.indices, id: \.self) { index in
                    Button { section = index } label: {
                        Text(sections[index].icon)
                            .font(.system(size: 22))
                            .frame(width: 44, height: 40)
                            .background(Capsule().fill(index == section ? theme.colors.surface.color : .clear))
                    }
                    .buttonStyle(PressShapeStyle(shape: Capsule()))
                    .accessibilityAddTraits(index == section ? .isSelected : [])
                }
            }
            .padding(.horizontal, CGFloat(ClomniTheme.Space.m))
            .padding(.bottom, CGFloat(ClomniTheme.Space.s))
        }
    }

    private func choose(_ emoji: String) {
        let updated = Array(([emoji] + recent.filter { $0 != emoji }).prefix(EmojiCatalog.recentLimit))
        Task.detached(priority: .utility) { EmojiCatalog.saveRecent(updated) }
        pick(emoji)
    }
}

/// The emoji the sheet offers, by category, and the recently used ones on disk (Application Support, no defaults).
enum EmojiCatalog {
    static let recentLimit = 24

    static let categories: [(name: String, emoji: [String])] = [
        ("smileys", "😀😃😄😁😆😅🤣😂🙂🙃😉😊😇🥰😍🤩😘😗😚😙😋😛😜🤪😝🤑🤗🤭🤫🤔🤐🤨😐😑😶😏😒🙄😬🤥😌😔😪🤤😴😷🤒🤕🤢🤮🤧🥵🥶🥴😵🤯🤠🥳😎🤓🧐😕😟🙁😮😯😲😳🥺😦😧😨😰😥😢😭😱😖😣😞😓😩😫🥱😤😡😠🤬😈👿💀💩🤡👻👽"),
        ("people", "👋🤚🖐✋🖖👌🤏✌🤞🤟🤘🤙👈👉👆👇☝👍👎✊👊🤛🤜👏🙌👐🤲🤝🙏✍💅🤳💪🦾👂👃🧠👀👁👅👄👶🧒👦👧🧑👱👨🧔👩🧓👴👵🙍🙎🙅🙆💁🙋🧏🙇🤦🤷👮🕵💂👷🤴👸👳"),
        ("nature", "🐶🐱🐭🐹🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🙈🙉🙊🐔🐧🐦🐤🦆🦅🦉🦇🐺🐗🐴🦄🐝🐛🦋🐌🐞🐜🦟🐢🐍🦎🐙🦑🦐🦀🐡🐠🐟🐬🐳🐋🦈🐊🐅🐆🦓🦍🐘🦛🦏🐪🐫🦒🐃🐂🐄🐎🐖🐏🐑🐐🦌🐕🐈🐓🦃🦚🦜🦢🕊🐇"),
        ("food", "🍏🍎🍐🍊🍋🍌🍉🍇🍓🍈🍒🍑🥭🍍🥥🥝🍅🍆🥑🥦🥬🥒🌶🌽🥕🧄🧅🥔🍠🥐🥯🍞🥖🥨🧀🥚🍳🧈🥞🧇🥓🥩🍗🍖🌭🍔🍟🍕🥪🥙🧆🌮🌯🥗🥘🍝🍜🍲🍛🍣🍱🥟🍤🍙🍚🍘🍥🥮🍢🍡"),
        ("activity", "⚽🏀🏈⚾🥎🎾🏐🏉🥏🎱🏓🏸🏒🏑🥍🏏🥅⛳🏹🎣🥊🥋🎽🛹⛸🥌🎿⛷🏂🏋🤸⛹🤺🤾🏌🏇🧘🏄🏊🤽🚣🧗🚵🚴🏆"),
        ("travel", "🚗🚕🚙🚌🚎🏎🚓🚑🚒🚐🚚🚛🚜🛴🚲🛵🏍🚨🚔🚍🚘🚖🚡🚠🚟🚃🚋🚞🚝🚄🚅🚈🚂🚆🚇🚊🚉✈🛫🛬🛩💺🛰🚀🛸"),
        ("objects", "⌚📱💻⌨🖥🖨🖱💽💾💿📀📷📸📹🎥📞☎📟📠📺📻🎙⏰⏳⌛📡🔋🔌💡🔦🕯🧯💸💵💴💶💷💰💳💎⚖🧰🔧🔨⚒🛠⛏🔩⚙🧱"),
        ("symbols", "❤🧡💛💚💙💜🖤🤍🤎💔❣💕💞💓💗💖💘💝💟💯💢💥💫💦💨💬💭🗯💤✅☑✔❌❎⭕❗❓‼⁉⚠🚫⛔🛑🔞📵"),
    ].map { ($0.0, $0.1.map(presented)) }

    /// A character drawn as text by default (❤, ☀, ✌) gets the emoji variation selector, so it is drawn in colour.
    private static func presented(_ character: Character) -> String {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first, !scalar.properties.isEmojiPresentation else {
            return String(character)
        }
        return String(character) + "\u{FE0F}"
    }

    private static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Clomni", isDirectory: true).appendingPathComponent("recent-emoji.txt")
    }

    static func loadRecent() -> [String] {
        guard let file, let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).prefix(recentLimit).map { $0 }
    }

    static func saveRecent(_ emoji: [String]) {
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? emoji.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }
}

/// Inserts text where the cursor of the focused field is, or at the end when nothing is focused (the sheet takes
/// the focus away, so the place is read before it opens).
enum TextInsertion {
    /// The cursor of the first responder as a UTF-16 offset, if it is a text input.
    @MainActor
    static func cursorOffset() -> Int? {
        #if canImport(ObjectiveC)
        FirstResponder.current = nil
        UIApplication.shared.sendAction(#selector(UIResponder.clomniFindFirstResponder(_:)), to: nil, from: nil, for: nil)
        guard let input = FirstResponder.current as? UITextInput, let range = input.selectedTextRange else { return nil }
        return input.offset(from: input.beginningOfDocument, to: range.start)
        #else
        return nil
        #endif
    }

    static func insert(_ insertion: String, into text: String, atUTF16 offset: Int?) -> String {
        let utf16 = text.utf16
        guard let offset, offset >= 0, offset <= utf16.count,
              let index = utf16.index(utf16.startIndex, offsetBy: offset, limitedBy: utf16.endIndex)?
                .samePosition(in: text) else { return text + insertion }
        var result = text
        result.insert(contentsOf: insertion, at: index)
        return result
    }
}

#if canImport(ObjectiveC)
private enum FirstResponder {
    static weak var current: UIResponder?
}

extension UIResponder {
    @objc func clomniFindFirstResponder(_ sender: Any?) {
        FirstResponder.current = self
    }
}
#endif
#endif
