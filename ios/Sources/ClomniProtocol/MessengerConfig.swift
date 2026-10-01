import Foundation

/// GET /v1/mobile/config (protocol/schema/config.json). Read leniently: a missing or invalid field takes its default,
/// so a minimal config still opens the messenger. Optional fields are those whose fallback is the SDK's own text.
package struct MessengerConfig: Sendable, Equatable {
    package let brand: Brand
    package let launcher: Launcher
    package let home: Home
    package let team: Team
    package let bot: Bot
    package let composer: Composer
    /// Never empty; "az" when the server sends none.
    package let languages: [String]
    /// UI texts set in the panel; a missing key falls back to the SDK's own az/en/ru text.
    package let strings: [String: String]
    package let limits: Limits

    package struct Brand: Sendable, Equatable {
        package let name: String
        package let logoUrl: URL?
        /// "#RRGGBB".
        package let primaryColor: String
        /// "#RRGGBB"; nil means the UI picks white or black for contrast.
        package let onPrimaryColor: String?
        package let theme: Theme

        /// Clomni's own colour, used when the config has none or an invalid one.
        package static let defaultPrimaryColor = "#10A670"
    }

    package enum Theme: String, Sendable, Equatable {
        case system, light, dark
    }

    /// The floating button; off unless the customer turns it on.
    package struct Launcher: Sendable, Equatable {
        package let visible: Bool
        package let position: LauncherPosition
        package let bottomPadding: Int
        package let icon: String
    }

    package enum LauncherPosition: String, Sendable, Equatable {
        case left, right
    }

    package struct Home: Sendable, Equatable {
        package let greetingTitle: String?
        package let greetingSubtitle: String?
        package let showTeamAvatars: Bool
        package let channels: [Channel]
        package let cards: [HomeCard]
    }

    /// A social channel icon on Home; `type` is open-ended (instagram, whatsapp, linkedin, email, …).
    package struct Channel: Sendable, Equatable {
        package let type: String
        package let url: URL
    }

    package enum HomeCard: String, Sendable, Equatable {
        case recentConversation = "recent_conversation"
        case newConversation = "new_conversation"
    }

    package struct Team: Sendable, Equatable {
        package let avatars: [URL]
        package let replyTime: String?
        package let officeHours: OfficeHours?
    }

    package struct OfficeHours: Sendable, Equatable {
        package let timeZone: String?
        package let openNow: Bool
        /// When the team is back, while `openNow` is false.
        package let nextOpenAt: Date?
    }

    package struct Bot: Sendable, Equatable {
        package let name: String
        package let avatarUrl: URL?
    }

    package struct Composer: Sendable, Equatable {
        package let placeholder: String?
        package let attachments: Bool
        package let emoji: Bool
    }

    package struct Limits: Sendable, Equatable {
        package let imageMb: Int
        package let fileMb: Int
        package let textChars: Int
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
