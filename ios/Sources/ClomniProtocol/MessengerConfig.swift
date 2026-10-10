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
    /// The languages the panel turned on and the one to fall back to (DESIGN-PASS-3 D1).
    package let languages: Languages
    /// The texts of the chosen language; a missing key falls back to the SDK's own az/en/ru text.
    package let strings: [String: String]
    package let limits: Limits
    /// "Powered by Clomni" under Home; only a plan that allows it turns it off.
    package let poweredBy: Bool
    /// `conversation.starts_with_flow`: a new conversation starts a flow, so it is created as soon as it opens.
    package let startsWithFlow: Bool
    /// Short sounds for a sent and a received message; the app can still turn them off.
    package let sounds: Bool

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
        /// `wordmark`: Home's header shows the full logo (`wordmarkUrl`) in place of the logo and the name. The server
        /// sends it only with a wordmark; without one it is `mark`, as for a server that does not know the field.
        package let logoStyle: LogoStyle
        package let wordmarkUrl: URL?
        /// For dark mode; nil uses `wordmarkUrl` there too.
        package let wordmarkDarkUrl: URL?
        /// Home's logo (and full logo) height in percent of 32: 60 to 200, 100 when absent.
        package let logoScale: Int

        /// Clomni's own colour, used when the config has none or an invalid one.
        package static let defaultPrimaryColor = "#10A670"
    }

    package enum HeaderStyle: String, Sendable, Equatable {
        case gradient, solid, image
    }

    package enum LogoStyle: String, Sendable, Equatable {
        /// The square logo (or the initial) and the brand's name.
        case mark
        /// The full logo, on Home's header only.
        case wordmark
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
        /// Home's first greeting line (at about 70%); nil from a server before it sent this (the SDK works it out).
        package let primaryStrong: String?
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
        /// In the panel's order; `messages` and `send` are always there.
        package let cards: [HomeCard]
        /// At most five, in the panel's order.
        package let channels: [Channel]
        /// The greeting's size in percent of 28: 70 to 140, 100 when absent.
        package let titleScale: Int
    }

    package enum HomeCard: String, Sendable, Equatable, CaseIterable {
        /// Opens the conversation list (there is no tab bar).
        case messages
        case recent, send
        /// The published news; not drawn when there is none.
        case news
        case channels
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
        /// The longest voice message; the recorder stops there.
        package let voiceSeconds: Int

        package init(imageMb: Int, fileMb: Int, textChars: Int, voiceSeconds: Int = Limits.defaultVoiceSeconds) {
            self.imageMb = imageMb
            self.fileMb = fileMb
            self.textChars = textChars
            self.voiceSeconds = voiceSeconds
        }

        /// Five minutes, when the config does not say (protocol config.json limits.voice_seconds).
        package static let defaultVoiceSeconds = 300
    }

    package static let maxChannels = 5

    /// `languages {enabled, default}`; absent, all three are on and az is the default. The messenger speaks the host's
    /// language when it is on, else the device's when it is on, else `default` (`pick`); with one on, always that one.
    package struct Languages: Sendable, Equatable {
        package static let all = ["az", "en", "ru"]

        package let enabled: [String]
        package let `default`: String

        package init(enabled: [String] = all, default: String = "az") {
            self.enabled = enabled
            self.default = `default`
        }

        package func pick(host: String?, device: String?) -> String {
            [host, device].compactMap { $0.map(Self.base) }.first { enabled.contains($0) } ?? `default`
        }

        /// "en-GB", "ru_RU" → "en", "ru".
        package static func base(_ tag: String) -> String {
            String(tag.lowercased().prefix { $0 != "-" && $0 != "_" })
        }

        /// `{enabled, default}`, or the earlier array (the enabled ones, its first the default). Unknown languages are
        /// dropped, a default that is not on falls to the first enabled one; nothing usable: all three, az.
        init(_ value: JSONValue?) {
            let enabled: [String]
            var fallback: String?
            if case .object(let fields)? = value {
                enabled = (fields["enabled"]?.arrayValue ?? []).compactMap(\.stringValue)
                fallback = fields["default"]?.stringValue
            } else {
                enabled = (value?.arrayValue ?? []).compactMap(\.stringValue)
            }
            var on: [String] = []
            for language in enabled where Self.all.contains(language) && !on.contains(language) { on.append(language) }
            guard let first = on.first else {
                self.init()
                return
            }
            if let wanted = fallback, !on.contains(wanted) { fallback = nil }
            self.init(enabled: on, default: fallback ?? first)
        }
    }

    /// The language the messenger speaks with this config: `host`'s (`Clomni.setLanguage`) if the panel has it on,
    /// else the device's if on, else the panel's main language.
    package func speaks(_ host: String?, device: String? = Locale.preferredLanguages.first) -> String {
        languages.pick(host: host, device: device)
    }
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
            },
            logoStyle: brand.optionalURL("wordmark_url") == nil ? .mark
                : brand.optionalString("logo_style").flatMap(LogoStyle.init(rawValue:)) ?? .mark,
            wordmarkUrl: brand.optionalURL("wordmark_url"),
            wordmarkDarkUrl: brand.optionalURL("wordmark_dark_url"),
            logoScale: Self.percent(brand.optionalInt("logo_scale"), in: 60...200))

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
        if home["cards"] == nil { cards = HomeCard.allCases }
        // The way to the conversations and to a new one is never off; an older server's list has no messages.
        if !cards.contains(.send) { cards.insert(.send, at: 0) }
        if !cards.contains(.messages) { cards.insert(.messages, at: 0) }
        self.home = Home(
            cards: cards,
            channels: Array((home["channels"]?.arrayValue ?? []).compactMap { item -> Channel? in
                guard let type = item["type"]?.stringValue, let url = item["url"]?.stringValue.flatMap(URL.init(string:))
                else { return nil }
                return Channel(type: type, url: url)
            }.prefix(Self.maxChannels)),
            titleScale: Self.percent(home.optionalInt("title_scale"), in: 70...140))

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

        languages = Languages(f["languages"])
        strings = (f["strings"]?.objectValue ?? [:]).compactMapValues(\.stringValue)

        let limits = section(f, "limits")
        let positive = { (key: String, fallback: Int) in limits.optionalInt(key).flatMap { $0 > 0 ? $0 : nil } ?? fallback }
        self.limits = Limits(imageMb: positive("image_mb", 10), fileMb: positive("file_mb", 25),
                             textChars: positive("text_chars", 4000), voiceSeconds: positive("voice_seconds", Limits.defaultVoiceSeconds))
        poweredBy = f.optionalBool("powered_by") ?? true
        startsWithFlow = section(f, "conversation").optionalBool("starts_with_flow") ?? false
        sounds = f.optionalBool("sounds") ?? true
    }

    /// The six colours (and header_text when there), or nil.
    private static func palette(_ f: JSONFields) -> Palette? {
        let color = { (key: String) in hexColor(f.optionalString(key)) }
        guard let primary = color("primary"), let onPrimary = color("on_primary"), let soft = color("primary_soft"),
              let line = color("primary_line"), let from = color("header_from"), let to = color("header_to") else {
            return nil
        }
        return Palette(primary: primary, onPrimary: onPrimary, primarySoft: soft, primaryLine: line, headerFrom: from,
                       headerTo: to, headerText: color("header_text"), primaryStrong: color("primary_strong"))
    }

    /// A panel percentage, kept within its range; 100 when absent.
    private static func percent(_ value: Int?, in range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value ?? 100))
    }

    /// "#RRGGBB" with ASCII hex digits (Character.isHexDigit also takes fullwidth ones), or nil for anything else.
    static func hexColor(_ value: String?) -> String? {
        let digits = Set("0123456789abcdefABCDEF".utf8)
        guard let value, value.utf8.count == 7, value.first == "#",
              value.utf8.dropFirst().allSatisfy(digits.contains) else { return nil }
        return value
    }
}

extension Optional where Wrapped == MessengerConfig {
    /// `MessengerConfig.speaks` before any config: the host's language, else the device's, of the three; else az.
    package func speaks(_ host: String?, device: String? = Locale.preferredLanguages.first) -> String {
        (self?.languages ?? MessengerConfig.Languages()).pick(host: host, device: device)
    }
}
