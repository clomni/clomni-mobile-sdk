import Foundation

/// The texts of the messenger. The config's `strings` (set in the panel, in the user's language) come first; the SDK
/// carries az, en and ru for every key, so a minimal config still reads well.
package struct ClomniStrings: Sendable, Equatable {
    package enum Key: String, CaseIterable, Sendable {
        case today, yesterday, tomorrow, send
        case newConversation = "new_conversation"
        case greetingHello = "greeting_hello"
        case greetingTitle = "greeting_title"
        case recentMessage = "recent_message"
        case followUs = "follow_us"
        case tabHome = "tab_home"
        case tabMessages = "tab_messages"
        case noConversations = "no_conversations"
        case error, retry, offline, now, you, close, unread, email, phone
        // The conversation (CM-083).
        case teamCanHelp = "team_can_help"
        case online
        case away
        case awayUntil = "away_until"
        case messagePlaceholder = "message_placeholder"
        case chooseAbove = "choose_above"
        case sending, sent, read, failed
        case conversationClosed = "conversation_closed"
        case startNewConversation = "start_new_conversation"
        case back
        case goBack = "go_back"
        case bot, button, typing, attach, emoji, image, file
        case fieldRequired = "field_required"
        case invalidEmail = "invalid_email"
        case invalidPhone = "invalid_phone"
        case invalidNumber = "invalid_number"
        case tooLong = "too_long"
        case chooseOption = "choose_option"
        case fileTooLarge = "file_too_large"
        case unreadMessages = "unread_messages"
        case minutesShort = "minutes_short"
        case hoursShort = "hours_short"
        case daysShort = "days_short"
    }

    /// az, en or ru; anything else reads as az.
    package let language: String
    private let overrides: [String: String]

    package init(language: String?, overrides: [String: String] = [:]) {
        let code = (language ?? "az").lowercased().prefix(2)
        self.language = Self.fallbacks.keys.contains(String(code)) ? String(code) : "az"
        self.overrides = overrides
    }

    package subscript(key: Key) -> String {
        if let text = overrides[key.rawValue], !text.isEmpty { return text }
        return Self.fallbacks[language]?[key] ?? Self.fallbacks["az"]?[key] ?? key.rawValue
    }

    /// A text with one number in it ("%d dəq").
    package func format(_ key: Key, _ number: Int) -> String {
        self[key].replacingOccurrences(of: "%d", with: String(number))
    }

    /// A text with one word in it ("Növbəti iş saatı: %@").
    package func format(_ key: Key, _ text: String) -> String {
        self[key].replacingOccurrences(of: "%@", with: text)
    }

    /// VoiceOver for a flow button: "Düymə, Azərbaycan dili, 1-ci, cəmi 3".
    package func buttonPosition(title: String, index: Int, count: Int) -> String {
        switch language {
        case "en": return "\(self[.button]), \(title), \(index) of \(count)"
        case "ru": return "\(self[.button]), \(title), \(index) из \(count)"
        default: return "\(self[.button]), \(title), \(index)-\(Self.azerbaijaniOrdinalSuffix(index)), cəmi \(count)"
        }
    }

    /// The suffix follows the vowel of the number's last word: 1-ci, 3-cü, 6-cı, 9-cu, 10-cu, 40-cı.
    static func azerbaijaniOrdinalSuffix(_ number: Int) -> String {
        let ones = ["", "ci", "ci", "cü", "cü", "ci", "cı", "ci", "ci", "cu"]
        let tens = ["", "cu", "ci", "cu", "cı", "ci", "cı", "ci", "ci", "cı"]
        let value = abs(number) % 100
        if value % 10 != 0 { return ones[value % 10] }
        if value != 0 { return tens[value / 10] }
        return abs(number) % 1000 == 0 ? "ci" : "cü"
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
            .today: "Bu gün", .yesterday: "Dünən", .tomorrow: "sabah", .send: "Göndər", .newConversation: "Bizə mesaj göndərin",
            .greetingHello: "Salam", .greetingTitle: "Necə kömək edə bilərik?", .recentMessage: "Son mesaj",
            .followUs: "Bizi izləyin", .tabHome: "Ana səhifə", .tabMessages: "Mesajlar",
            .noConversations: "Hələ söhbət yoxdur", .error: "Nəsə səhv getdi", .retry: "Yenidən cəhd et",
            .offline: "İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq", .now: "indi", .you: "Siz",
            .close: "Bağla", .unread: "Oxunmamış", .unreadMessages: "Oxunmamış mesaj var", .minutesShort: "%d dəq",
            .hoursShort: "%d saat", .daysShort: "%d gün", .email: "E-poçt", .phone: "Telefon",
            .teamCanHelp: "Komanda da kömək edə bilər", .online: "onlayn", .away: "Hazırda iş saatı deyil",
            .awayUntil: "Növbəti iş saatı: %@",
            .messagePlaceholder: "Mesaj yazın…", .chooseAbove: "Yuxarıdakı variantlardan birini seçin",
            .sending: "Göndərilir", .sent: "Göndərildi", .read: "Oxundu", .failed: "Göndərilmədi",
            .conversationClosed: "Söhbət bağlanıb", .startNewConversation: "Yeni söhbət başlat", .back: "← Geri",
            .goBack: "Geri", .bot: "Bot", .button: "Düymə", .typing: "yazır", .attach: "Fayl əlavə et",
            .emoji: "Emoji", .image: "Şəkil", .file: "Fayl", .fieldRequired: "Bu sahəni doldurun",
            .invalidEmail: "Email düzgün deyil", .invalidPhone: "Telefon nömrəsi düzgün deyil",
            .invalidNumber: "Rəqəm yazın", .tooLong: "Ən çox %d simvol", .chooseOption: "Variantlardan birini seçin",
            .fileTooLarge: "Fayl çox böyükdür (maks. %d MB)",
        ],
        "en": [
            .today: "Today", .yesterday: "Yesterday", .tomorrow: "tomorrow", .send: "Send", .newConversation: "Send us a message",
            .greetingHello: "Hi", .greetingTitle: "How can we help?", .recentMessage: "Recent message",
            .followUs: "Follow us", .tabHome: "Home", .tabMessages: "Messages",
            .noConversations: "No conversations yet", .error: "Something went wrong", .retry: "Try again",
            .offline: "No internet. Messages will be delivered when you are back online", .now: "now", .you: "You",
            .close: "Close", .unread: "Unread", .unreadMessages: "Unread messages", .minutesShort: "%d min",
            .hoursShort: "%d h", .daysShort: "%d d", .email: "Email", .phone: "Phone",
            .teamCanHelp: "The team can help too", .online: "online", .away: "Outside working hours",
            .awayUntil: "Next working hours: %@",
            .messagePlaceholder: "Write a message…", .chooseAbove: "Choose one of the options above",
            .sending: "Sending", .sent: "Sent", .read: "Read", .failed: "Not sent",
            .conversationClosed: "Conversation closed", .startNewConversation: "Start a new conversation",
            .back: "← Back", .goBack: "Back", .bot: "Bot", .button: "Button", .typing: "is typing",
            .attach: "Attach a file", .emoji: "Emoji", .image: "Image", .file: "File",
            .fieldRequired: "Fill in this field", .invalidEmail: "Enter a valid email",
            .invalidPhone: "Enter a valid phone number", .invalidNumber: "Enter a number",
            .tooLong: "At most %d characters", .chooseOption: "Choose one of the options",
            .fileTooLarge: "The file is too large (max %d MB)",
        ],
        "ru": [
            .today: "Сегодня", .yesterday: "Вчера", .tomorrow: "завтра", .send: "Отправить", .newConversation: "Напишите нам",
            .greetingHello: "Здравствуйте", .greetingTitle: "Чем можем помочь?", .recentMessage: "Последнее сообщение",
            .followUs: "Мы в соцсетях", .tabHome: "Главная", .tabMessages: "Сообщения",
            .noConversations: "Пока нет переписки", .error: "Что-то пошло не так", .retry: "Повторить",
            .offline: "Нет интернета, сообщения будут доставлены позже", .now: "сейчас", .you: "Вы",
            .close: "Закрыть", .unread: "Не прочитано", .unreadMessages: "Есть непрочитанные сообщения",
            .minutesShort: "%d мин", .hoursShort: "%d ч", .daysShort: "%d дн", .email: "Почта", .phone: "Телефон",
            .teamCanHelp: "Команда тоже может помочь", .online: "в сети", .away: "Сейчас нерабочее время",
            .awayUntil: "Следующее рабочее время: %@",
            .messagePlaceholder: "Напишите сообщение…", .chooseAbove: "Выберите один из вариантов выше",
            .sending: "Отправляется", .sent: "Отправлено", .read: "Прочитано", .failed: "Не отправлено",
            .conversationClosed: "Диалог закрыт", .startNewConversation: "Начать новый диалог", .back: "← Назад",
            .goBack: "Назад", .bot: "Бот", .button: "Кнопка", .typing: "печатает", .attach: "Прикрепить файл",
            .emoji: "Эмодзи", .image: "Изображение", .file: "Файл", .fieldRequired: "Заполните это поле",
            .invalidEmail: "Неверный email", .invalidPhone: "Неверный номер телефона",
            .invalidNumber: "Введите число", .tooLong: "Не больше %d символов", .chooseOption: "Выберите вариант",
            .fileTooLarge: "Файл слишком большой (макс. %d МБ)",
        ],
    ]
}
