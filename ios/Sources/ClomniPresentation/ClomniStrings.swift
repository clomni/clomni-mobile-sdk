import Foundation

/// The texts of the messenger. The config's `strings` (set in the panel, in the user's language) come first; the SDK
/// carries az, en and ru for every key, so a minimal config still reads well.
public struct ClomniStrings: Sendable, Equatable {
    public enum Key: String, CaseIterable, Sendable {
        case today, yesterday, send
        case newConversation = "new_conversation"
        case greetingHello = "greeting_hello"
        case greetingTitle = "greeting_title"
        case recentMessage = "recent_message"
        case followUs = "follow_us"
        case tabHome = "tab_home"
        case tabMessages = "tab_messages"
        case noConversations = "no_conversations"
        case error, retry, offline, now, you, close, unread, email, phone
        case unreadMessages = "unread_messages"
        case minutesShort = "minutes_short"
        case hoursShort = "hours_short"
        case daysShort = "days_short"
    }

    /// az, en or ru; anything else reads as az.
    public let language: String
    private let overrides: [String: String]

    public init(language: String?, overrides: [String: String] = [:]) {
        let code = (language ?? "az").lowercased().prefix(2)
        self.language = Self.fallbacks.keys.contains(String(code)) ? String(code) : "az"
        self.overrides = overrides
    }

    public subscript(key: Key) -> String {
        if let text = overrides[key.rawValue], !text.isEmpty { return text }
        return Self.fallbacks[language]?[key] ?? Self.fallbacks["az"]?[key] ?? key.rawValue
    }

    /// A text with one number in it ("%d dəq").
    public func format(_ key: Key, _ number: Int) -> String {
        self[key].replacingOccurrences(of: "%d", with: String(number))
    }

    /// Month names as they stand before or after a day ("1 oktyabr", "1 октября", "October 1").
    var months: [String] {
        Self.monthNames[language] ?? Self.monthNames["az"] ?? []
    }

    private static let monthNames: [String: [String]] = [
        "az": ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avqust", "sentyabr", "oktyabr", "noyabr",
               "dekabr"],
        "en": ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
               "December"],
        "ru": ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября",
               "декабря"],
    ]

    static let fallbacks: [String: [Key: String]] = [
        "az": [
            .today: "Bu gün", .yesterday: "Dünən", .send: "Göndər", .newConversation: "Bizə mesaj göndərin",
            .greetingHello: "Salam", .greetingTitle: "Necə kömək edə bilərik?", .recentMessage: "Son mesaj",
            .followUs: "Bizi izləyin", .tabHome: "Ana səhifə", .tabMessages: "Mesajlar",
            .noConversations: "Hələ söhbət yoxdur", .error: "Nəsə səhv getdi", .retry: "Yenidən cəhd et",
            .offline: "İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq", .now: "indi", .you: "Siz",
            .close: "Bağla", .unread: "Oxunmamış", .unreadMessages: "Oxunmamış mesaj var", .minutesShort: "%d dəq",
            .hoursShort: "%d saat", .daysShort: "%d gün", .email: "E-poçt", .phone: "Telefon",
        ],
        "en": [
            .today: "Today", .yesterday: "Yesterday", .send: "Send", .newConversation: "Send us a message",
            .greetingHello: "Hi", .greetingTitle: "How can we help?", .recentMessage: "Recent message",
            .followUs: "Follow us", .tabHome: "Home", .tabMessages: "Messages",
            .noConversations: "No conversations yet", .error: "Something went wrong", .retry: "Try again",
            .offline: "No internet. Messages will be delivered when you are back online", .now: "now", .you: "You",
            .close: "Close", .unread: "Unread", .unreadMessages: "Unread messages", .minutesShort: "%d min",
            .hoursShort: "%d h", .daysShort: "%d d", .email: "Email", .phone: "Phone",
        ],
        "ru": [
            .today: "Сегодня", .yesterday: "Вчера", .send: "Отправить", .newConversation: "Напишите нам",
            .greetingHello: "Здравствуйте", .greetingTitle: "Чем можем помочь?", .recentMessage: "Последнее сообщение",
            .followUs: "Мы в соцсетях", .tabHome: "Главная", .tabMessages: "Сообщения",
            .noConversations: "Пока нет переписки", .error: "Что-то пошло не так", .retry: "Повторить",
            .offline: "Нет интернета, сообщения будут доставлены позже", .now: "сейчас", .you: "Вы",
            .close: "Закрыть", .unread: "Не прочитано", .unreadMessages: "Есть непрочитанные сообщения",
            .minutesShort: "%d мин", .hoursShort: "%d ч", .daysShort: "%d дн", .email: "Почта", .phone: "Телефон",
        ],
    ]
}
