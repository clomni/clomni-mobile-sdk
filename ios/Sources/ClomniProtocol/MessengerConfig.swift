import Foundation

/// GET /v1/mobile/config (protocol/schema/config.json). Read leniently: a missing or invalid field takes its default,
/// so a minimal config still opens the messenger. Optional fields are those whose fallback is the SDK's own text.
public struct MessengerConfig: Sendable, Equatable {
    public let brand: Brand
    public let launcher: Launcher
    public let home: Home
    public let team: Team
    public let bot: Bot
    public let composer: Composer
    /// Never empty; "az" when the server sends none.
    public let languages: [String]
    /// UI texts set in the panel; a missing key falls back to the SDK's own az/en/ru text.
    public let strings: [String: String]
    public let limits: Limits

    public struct Brand: Sendable, Equatable {
        public let name: String
        public let logoUrl: URL?
        /// "#RRGGBB".
        public let primaryColor: String
        /// "#RRGGBB"; nil means the UI picks white or black for contrast.
        public let onPrimaryColor: String?
        public let theme: Theme

        /// Clomni's own colour, used when the config has none or an invalid one.
        public static let defaultPrimaryColor = "#10A670"
    }

    public enum Theme: String, Sendable, Equatable {
        case system, light, dark
    }

    /// The floating button; off unless the customer turns it on.
    public struct Launcher: Sendable, Equatable {
        public let visible: Bool
        public let position: LauncherPosition
        public let bottomPadding: Int
        public let icon: String
    }

    public enum LauncherPosition: String, Sendable, Equatable {
        case left, right
    }

    public struct Home: Sendable, Equatable {
        public let greetingTitle: String?
        public let greetingSubtitle: String?
        public let showTeamAvatars: Bool
        public let channels: [Channel]
        public let cards: [HomeCard]
    }

    /// A social channel icon on Home; `type` is open-ended (instagram, whatsapp, linkedin, email, …).
    public struct Channel: Sendable, Equatable {
        public let type: String
        public let url: URL
    }

    public enum HomeCard: String, Sendable, Equatable {
        case recentConversation = "recent_conversation"
        case newConversation = "new_conversation"
    }

    public struct Team: Sendable, Equatable {
        public let avatars: [URL]
        public let replyTime: String?
        public let officeHours: OfficeHours?
    }

    public struct OfficeHours: Sendable, Equatable {
        public let timeZone: String?
        public let openNow: Bool
        /// When the team is back, while `openNow` is false.
        public let nextOpenAt: Date?
    }

    public struct Bot: Sendable, Equatable {
        public let name: String
        public let avatarUrl: URL?
    }

    public struct Composer: Sendable, Equatable {
        public let placeholder: String?
        public let attachments: Bool
        public let emoji: Bool
    }

    public struct Limits: Sendable, Equatable {
        public let imageMb: Int
        public let fileMb: Int
        public let textChars: Int
    }
}

extension MessengerConfig {
    init(_ f: JSONFields) {
        let section = { (key: String) in f.optionalObject(key) ?? JSONFields(fields: [:], path: key) }

        let brand = section("brand")
        self.brand = Brand(
            name: brand.optionalString("name") ?? "",
            logoUrl: brand.optionalURL("logo_url"),
            primaryColor: Self.hexColor(brand.optionalString("primary_color")) ?? Brand.defaultPrimaryColor,
            onPrimaryColor: Self.hexColor(brand.optionalString("on_primary_color")),
            theme: brand.optionalString("theme").flatMap(Theme.init(rawValue:)) ?? .system)

        let launcher = section("launcher")
        self.launcher = Launcher(
            visible: launcher.optionalBool("visible") ?? false,
            position: launcher.optionalString("position").flatMap(LauncherPosition.init(rawValue:)) ?? .right,
            bottomPadding: launcher.optionalInt("bottom_padding").flatMap { $0 >= 0 ? $0 : nil } ?? 20,
            icon: launcher.optionalString("icon") ?? "default")

        let home = section("home")
        self.home = Home(
            greetingTitle: home.optionalString("greeting_title"),
            greetingSubtitle: home.optionalString("greeting_subtitle"),
            showTeamAvatars: home.optionalBool("show_team_avatars") ?? true,
            channels: (home["channels"]?.arrayValue ?? []).compactMap { item in
                guard let type = item["type"]?.stringValue, let url = item["url"]?.stringValue.flatMap(URL.init(string:))
                else { return nil }
                return Channel(type: type, url: url)
            },
            cards: home["cards"]?.arrayValue.map { $0.compactMap { $0.stringValue.flatMap(HomeCard.init(rawValue:)) } }
                ?? [.recentConversation, .newConversation])

        let team = section("team")
        self.team = Team(
            avatars: (team["avatars"]?.arrayValue ?? []).compactMap { $0.stringValue.flatMap(URL.init(string:)) },
            replyTime: team.optionalString("reply_time"),
            officeHours: team.optionalObject("office_hours").map {
                OfficeHours(timeZone: $0.optionalString("tz"), openNow: $0.optionalBool("open_now") ?? true,
                            nextOpenAt: $0.optionalString("next_open_at").flatMap(ISOTime.parse))
            })

        let bot = section("bot")
        self.bot = Bot(name: bot.optionalString("name") ?? "", avatarUrl: bot.optionalURL("avatar_url"))

        let composer = section("composer")
        self.composer = Composer(placeholder: composer.optionalString("placeholder"),
                                 attachments: composer.optionalBool("attachments") ?? true,
                                 emoji: composer.optionalBool("emoji") ?? true)

        let languages = (f["languages"]?.arrayValue ?? []).compactMap(\.stringValue)
        self.languages = languages.isEmpty ? ["az"] : languages
        strings = (f["strings"]?.objectValue ?? [:]).compactMapValues(\.stringValue)

        let limits = section("limits")
        let positive = { (key: String, fallback: Int) in limits.optionalInt(key).flatMap { $0 > 0 ? $0 : nil } ?? fallback }
        self.limits = Limits(imageMb: positive("image_mb", 10), fileMb: positive("file_mb", 25),
                             textChars: positive("text_chars", 4000))
    }

    /// "#RRGGBB", or nil for anything else.
    static func hexColor(_ value: String?) -> String? {
        guard let value, value.count == 7, value.first == "#", value.dropFirst().allSatisfy(\.isHexDigit) else {
            return nil
        }
        return value
    }
}
