import Foundation

/// GET /v1/mobile/config, version 2: the messenger's appearance and texts as published in the panel
/// (APPEARANCE-CONTRACT § 1). Read leniently: a missing or invalid field takes its default, so a minimal config still
/// opens the messenger.
package struct MessengerConfig: Sendable, Equatable {
    /// The published appearance's version; +1 on every publish.
    package let version: Int
    package let brand: Brand
    package let team: Team
    package let bot: Bot
    package let home: Home
    package let theme: Theme
    package let composer: Composer
    /// Never empty; "az" when the server sends none.
    package let languages: [String]
    /// The texts of the chosen language; a missing key falls back to the SDK's own az/en/ru text.
    package let strings: [String: String]
    package let limits: Limits
    /// "Powered by Clomni" under Home; only a plan that allows it turns it off.
    package let poweredBy: Bool

    package struct Brand: Sendable, Equatable {
        package let name: String
        package let logoUrl: URL?
        /// The logo for dark mode; nil uses `logoUrl` there too.
        package let logoDarkUrl: URL?
        /// "#RRGGBB".
        package let primaryColor: String
        package let headerStyle: HeaderStyle
        /// The picture of `headerStyle` image.
        package let headerImageUrl: URL?
        /// A soft glow of the brand colour behind the header.
        package let glow: Bool
        /// The tokens the server derived from `primaryColor`, so that Android and iOS show the same; nil when the
        /// server sent none (or an incomplete set): the SDK then derives them itself, by the same rules.
        package let colors: Colors?

        /// Clomni's own colour, used when the config has none or an invalid one.
        package static let defaultPrimaryColor = "#10A670"
    }

    package enum HeaderStyle: String, Sendable, Equatable {
        case gradient, solid, image
    }

    package struct Colors: Sendable, Equatable {
        package let light: Palette
        package let dark: Palette
    }

    /// "#RRGGBB" each.
    package struct Palette: Sendable, Equatable {
        package let primary: String
        package let onPrimary: String
        package let primarySoft: String
        package let primaryLine: String
        /// The top of the header.
        package let headerFrom: String
        /// Its bottom.
        package let headerTo: String
        /// Text and icons on the header; nil from a server before it sent this (the SDK then works it out).
        package let headerText: String?
    }

    package struct Team: Sendable, Equatable {
        /// The team's avatars on Home and in the conversation header.
        package let show: Bool
        package let avatars: [URL]
        package let replyTime: String?
        /// Instead of `replyTime` while the office is closed.
        package let replyTimeOffline: String?
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
        /// nil: the brand's logo stands for the bot, else its initial.
        package let avatarUrl: URL?
    }

    package struct Home: Sendable, Equatable {
        /// In the panel's order; `send` is always there.
        package let cards: [HomeCard]
        /// At most five, in the panel's order.
        package let channels: [Channel]
    }

    package enum HomeCard: String, Sendable, Equatable {
        case send, recent, channels
    }

    /// A social channel icon on Home; `type` is open-ended (instagram, whatsapp, linkedin, email, …).
    package struct Channel: Sendable, Equatable {
        package let type: String
        package let url: URL
    }

    package struct Theme: Sendable, Equatable {
        package let mode: Mode
        package let launcher: Launcher
    }

    package enum Mode: String, Sendable, Equatable {
        case system, light, dark
    }

    /// The floating button; off unless the customer turns it on.
    package struct Launcher: Sendable, Equatable {
        package let enabled: Bool
        package let position: LauncherPosition
        package let bottomPadding: Int
    }

    package enum LauncherPosition: String, Sendable, Equatable {
        case left, right
    }

    package struct Composer: Sendable, Equatable {
        package let attachments: Bool
        package let emoji: Bool
    }

    package struct Limits: Sendable, Equatable {
        package let imageMb: Int
        package let fileMb: Int
        package let textChars: Int
    }

    package static let maxChannels = 5
}

extension MessengerConfig {
    init(_ f: JSONFields) {
        let section = { (fields: JSONFields, key: String) in
            fields.optionalObject(key) ?? JSONFields(fields: [:], path: "\(fields.path).\(key)")
        }
        version = f.optionalInt("version") ?? 0

        let brand = section(f, "brand")
        self.brand = Brand(
            name: brand.optionalString("name") ?? "",
            logoUrl: brand.optionalURL("logo_url"),
            logoDarkUrl: brand.optionalURL("logo_dark_url"),
            primaryColor: Self.hexColor(brand.optionalString("primary_color")) ?? Brand.defaultPrimaryColor,
            headerStyle: brand.optionalString("header_style").flatMap(HeaderStyle.init(rawValue:)) ?? .gradient,
            headerImageUrl: brand.optionalURL("header_image_url"),
            glow: brand.optionalBool("glow") ?? false,
            colors: brand.optionalObject("colors").flatMap { colors in
                guard let light = colors.optionalObject("light").flatMap(Self.palette),
                      let dark = colors.optionalObject("dark").flatMap(Self.palette) else { return nil }
                return Colors(light: light, dark: dark)
            })

        let team = section(f, "team")
        self.team = Team(
            show: team.optionalBool("show") ?? true,
            avatars: (team["avatars"]?.arrayValue ?? []).compactMap { $0.stringValue.flatMap(URL.init(string:)) },
            replyTime: team.optionalString("reply_time"),
            replyTimeOffline: team.optionalString("reply_time_offline"),
            officeHours: team.optionalObject("office_hours").map {
                OfficeHours(timeZone: $0.optionalString("tz"), openNow: $0.optionalBool("open_now") ?? true,
                            nextOpenAt: $0.optionalString("next_open_at").flatMap(ISOTime.parse))
            })

        let bot = section(f, "bot")
        self.bot = Bot(name: bot.optionalString("name") ?? "", avatarUrl: bot.optionalURL("avatar_url"))

        let home = section(f, "home")
        var cards: [HomeCard] = []
        for card in (home["cards"]?.arrayValue ?? []).compactMap({ $0.stringValue.flatMap(HomeCard.init(rawValue:)) })
        where !cards.contains(card) {
            cards.append(card)
        }
        if home["cards"] == nil { cards = [.send, .recent, .channels] }
        if !cards.contains(.send) { cards.insert(.send, at: 0) }
        self.home = Home(
            cards: cards,
            channels: Array((home["channels"]?.arrayValue ?? []).compactMap { item -> Channel? in
                guard let type = item["type"]?.stringValue, let url = item["url"]?.stringValue.flatMap(URL.init(string:))
                else { return nil }
                return Channel(type: type, url: url)
            }.prefix(Self.maxChannels)))

        let theme = section(f, "theme")
        let launcher = section(theme, "launcher")
        self.theme = Theme(
            mode: theme.optionalString("mode").flatMap(Mode.init(rawValue:)) ?? .system,
            launcher: Launcher(
                enabled: launcher.optionalBool("enabled") ?? false,
                position: launcher.optionalString("position").flatMap(LauncherPosition.init(rawValue:)) ?? .right,
                bottomPadding: launcher.optionalInt("bottom_padding").flatMap { (0...200).contains($0) ? $0 : nil } ?? 20))

        let composer = section(f, "composer")
        self.composer = Composer(attachments: composer.optionalBool("attachments") ?? true,
                                 emoji: composer.optionalBool("emoji") ?? true)

        let languages = (f["languages"]?.arrayValue ?? []).compactMap(\.stringValue)
        self.languages = languages.isEmpty ? ["az"] : languages
        strings = (f["strings"]?.objectValue ?? [:]).compactMapValues(\.stringValue)

        let limits = section(f, "limits")
        let positive = { (key: String, fallback: Int) in limits.optionalInt(key).flatMap { $0 > 0 ? $0 : nil } ?? fallback }
        self.limits = Limits(imageMb: positive("image_mb", 10), fileMb: positive("file_mb", 25),
                             textChars: positive("text_chars", 4000))
        poweredBy = f.optionalBool("powered_by") ?? true
    }

    /// The six colours (and header_text when there), or nil.
    private static func palette(_ f: JSONFields) -> Palette? {
        let color = { (key: String) in hexColor(f.optionalString(key)) }
        guard let primary = color("primary"), let onPrimary = color("on_primary"), let soft = color("primary_soft"),
              let line = color("primary_line"), let from = color("header_from"), let to = color("header_to") else {
            return nil
        }
        return Palette(primary: primary, onPrimary: onPrimary, primarySoft: soft, primaryLine: line, headerFrom: from,
                       headerTo: to, headerText: color("header_text"))
    }

    /// "#RRGGBB", or nil for anything else.
    static func hexColor(_ value: String?) -> String? {
        guard let value, value.count == 7, value.first == "#", value.dropFirst().allSatisfy(\.isHexDigit) else {
            return nil
        }
        return value
    }
}
