import Foundation

/// The texts of the messenger. The config's `strings` (set in the panel, in the user's language) come first; the SDK
/// carries az, en and ru for every key, so a minimal config still reads well.
package struct ClomniStrings: Sendable, Equatable {
    package enum Key: String, CaseIterable, Sendable {
        case today, yesterday, tomorrow, send
        case sendCardTitle = "send_card_title"
        case greetingLine1 = "greeting_line1"
        case greetingLine1Anonymous = "greeting_line1_anonymous"
        case greetingLine2 = "greeting_line2"
        case recentMessage = "recent_message"
        case followUs = "follow_us"
        case messagesTitle = "messages_title"
        case newsTitle = "news_title"
        case pickMedia = "pick_media"
        case pickCamera = "pick_camera"
        case pickFile = "pick_file"
        case removeAttachment = "remove_attachment"
        case emptyList = "empty_list"
        case error, retry, offline, connected, now, you, close, unread, email, phone
        // Replies (DESIGN-PASS-3 F2): the long-press menu, and a quote whose message is gone.
        case reply, copy
        case quoteDeleted = "quote_deleted"
        // The conversation (CM-083).
        case headerSubtitle = "header_subtitle"
        case online
        case away
        case awayUntil = "away_until"
        case composerPlaceholder = "composer_placeholder"
        case sending, sent, read, failed
        case closed
        case startNewConversation = "start_new_conversation"
        case back
        case goBack = "go_back"
        case bot, typing, attach, emoji, image, file
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
        // VoiceOver (CM-087).
        case loading
        case required
        /// After an optional form field's label: "E-poçt (istəyə görə)".
        case optional
        case opensImage = "opens_image"
        case opensFile = "opens_file"
        /// The capsule over the transcript while the user reads further up and a message arrives (H2).
        case newMessage = "new_message"
        // A rating (CSAT, CM-087): the five faces as VoiceOver reads them, a star's, the comment field, the thanks.
        case rating1 = "rating_1"
        case rating2 = "rating_2"
        case rating3 = "rating_3"
        case rating4 = "rating_4"
        case rating5 = "rating_5"
        case ratingStars = "rating_stars"
        case ratingComment = "rating_comment"
        case ratingThanks = "rating_thanks"
        case ratingYours = "rating_yours"
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

    /// VoiceOver for a flow button: "Azərbaycan dili, 1-ci, cəmi 3". VoiceOver adds "Button" itself, in the system's
    /// language (iOS has no Azerbaijani).
    package func buttonPosition(title: String, index: Int, count: Int) -> String {
        switch language {
        case "en": return "\(title), \(index) of \(count)"
        case "ru": return "\(title), \(index) из \(count)"
        default: return "\(title), \(index)-\(Self.azerbaijaniOrdinalSuffix(index)), cəmi \(count)"
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
            .today: "Bu gün", .yesterday: "Dünən", .tomorrow: "sabah", .send: "Göndər", .sendCardTitle: "Bizə mesaj göndərin",
            .greetingLine1: "Salam, {first_name}", .greetingLine1Anonymous: "Salam", .greetingLine2: "Necə kömək edə bilərik?", .recentMessage: "Ən son mesaj",
            .followUs: "Bizi izləyin", .messagesTitle: "Mesajlar", .newsTitle: "Xəbərlər", .pickMedia: "Şəkil və ya video",
            .pickCamera: "Kamera", .pickFile: "Fayl", .removeAttachment: "Sil", .reply: "Cavabla", .copy: "Kopyala",
            .quoteDeleted: "Mesaj silinib",
            .emptyList: "Hələ söhbət yoxdur", .error: "Nəsə səhv getdi", .retry: "Yenidən cəhd et",
            .offline: "İnternet yoxdur", .connected: "Qoşuldu", .now: "indi", .you: "Siz",
            .close: "Bağla", .unread: "Oxunmamış", .unreadMessages: "Oxunmamış mesaj var", .minutesShort: "%d dəq",
            .hoursShort: "%d saat", .daysShort: "%d gün", .email: "E-poçt", .phone: "Telefon",
            .headerSubtitle: "Adətən bir neçə dəqiqəyə cavab veririk", .online: "onlayn", .away: "Hazırda iş saatı deyil",
            .awayUntil: "Növbəti iş saatı: %@",
            .composerPlaceholder: "Mesaj yazın…",
            .sending: "Göndərilir", .sent: "Göndərildi", .read: "Oxundu", .failed: "Göndərilmədi",
            .closed: "Söhbət bağlanıb", .startNewConversation: "Yeni söhbət başlat", .back: "← Geri",
            .optional: "(istəyə görə)",
            .goBack: "Geri", .bot: "Bot", .typing: "yazır", .attach: "Fayl əlavə et",
            .emoji: "Emoji", .image: "Şəkil", .file: "Fayl", .fieldRequired: "Bu sahəni doldurun",
            .invalidEmail: "E-poçt düzgün deyil", .invalidPhone: "Telefon nömrəsi düzgün deyil",
            .invalidNumber: "Rəqəm yazın", .tooLong: "Ən çox %d simvol", .chooseOption: "Variantlardan birini seçin",
            .fileTooLarge: "Fayl çox böyükdür (maks. %d MB)", .loading: "Yüklənir", .required: "məcburi",
            .opensImage: "Şəkli tam ekranda açır", .opensFile: "Faylı açır", .newMessage: "Yeni mesaj",
            .rating1: "Çox pis", .rating2: "Pis", .rating3: "Normal", .rating4: "Yaxşı", .rating5: "Əla",
            .ratingStars: "5 ulduzdan %d", .ratingComment: "Rəyiniz", .ratingThanks: "Rəyiniz üçün təşəkkür edirik",
            .ratingYours: "Qiymətiniz: %@",
        ],
        "en": [
            .today: "Today", .yesterday: "Yesterday", .tomorrow: "tomorrow", .send: "Send", .sendCardTitle: "Send us a message",
            .greetingLine1: "Hi, {first_name}", .greetingLine1Anonymous: "Hi", .greetingLine2: "How can we help?", .recentMessage: "Recent message",
            .followUs: "Follow us", .messagesTitle: "Messages", .newsTitle: "News", .pickMedia: "Photo or video",
            .pickCamera: "Camera", .pickFile: "File", .removeAttachment: "Remove", .reply: "Reply", .copy: "Copy",
            .quoteDeleted: "Message deleted",
            .emptyList: "No conversations yet", .error: "Something went wrong", .retry: "Try again",
            .offline: "No internet connection", .connected: "Connected", .now: "now", .you: "You",
            .close: "Close", .unread: "Unread", .unreadMessages: "Unread messages", .minutesShort: "%d min",
            .hoursShort: "%d h", .daysShort: "%d d", .email: "Email", .phone: "Phone",
            .headerSubtitle: "Typically replies in a few minutes", .online: "online", .away: "Outside working hours",
            .awayUntil: "Next working hours: %@",
            .composerPlaceholder: "Write a message…",
            .sending: "Sending", .sent: "Sent", .read: "Read", .failed: "Not sent",
            .closed: "Conversation closed", .startNewConversation: "Start a new conversation",
            .back: "← Back", .optional: "(optional)", .goBack: "Back", .bot: "Bot", .typing: "is typing",
            .attach: "Attach a file", .emoji: "Emoji", .image: "Image", .file: "File",
            .fieldRequired: "Fill in this field", .invalidEmail: "Enter a valid email",
            .invalidPhone: "Enter a valid phone number", .invalidNumber: "Enter a number",
            .tooLong: "At most %d characters", .chooseOption: "Choose one of the options",
            .fileTooLarge: "The file is too large (max %d MB)", .loading: "Loading", .required: "required",
            .opensImage: "Opens the picture full screen", .opensFile: "Opens the file", .newMessage: "New message",
            .rating1: "Very bad", .rating2: "Bad", .rating3: "Okay", .rating4: "Good", .rating5: "Great",
            .ratingStars: "%d of 5 stars", .ratingComment: "Your feedback", .ratingThanks: "Thank you for your feedback",
            .ratingYours: "Your rating: %@",
        ],
        "ru": [
            .today: "Сегодня", .yesterday: "Вчера", .tomorrow: "завтра", .send: "Отправить", .sendCardTitle: "Напишите нам",
            .greetingLine1: "Здравствуйте, {first_name}", .greetingLine1Anonymous: "Здравствуйте", .greetingLine2: "Чем можем помочь?", .recentMessage: "Последнее сообщение",
            .followUs: "Мы в соцсетях", .messagesTitle: "Сообщения", .newsTitle: "Новости", .pickMedia: "Фото или видео",
            .pickCamera: "Камера", .pickFile: "Файл", .removeAttachment: "Удалить", .reply: "Ответить", .copy: "Копировать",
            .quoteDeleted: "Сообщение удалено",
            .emptyList: "Пока нет переписки", .error: "Что-то пошло не так", .retry: "Повторить",
            .offline: "Нет подключения к интернету", .connected: "Подключено", .now: "сейчас", .you: "Вы",
            .close: "Закрыть", .unread: "Не прочитано", .unreadMessages: "Есть непрочитанные сообщения",
            .minutesShort: "%d мин", .hoursShort: "%d ч", .daysShort: "%d дн", .email: "Почта", .phone: "Телефон",
            .headerSubtitle: "Обычно отвечаем в течение нескольких минут", .online: "в сети", .away: "Сейчас нерабочее время",
            .awayUntil: "Следующее рабочее время: %@",
            .composerPlaceholder: "Напишите сообщение…",
            .sending: "Отправляется", .sent: "Отправлено", .read: "Прочитано", .failed: "Не отправлено",
            .closed: "Диалог закрыт", .startNewConversation: "Начать новый диалог", .back: "← Назад", .optional: "(необязательно)",
            .goBack: "Назад", .bot: "Бот", .typing: "печатает", .attach: "Прикрепить файл",
            .emoji: "Эмодзи", .image: "Изображение", .file: "Файл", .fieldRequired: "Заполните это поле",
            .invalidEmail: "Неверный email", .invalidPhone: "Неверный номер телефона",
            .invalidNumber: "Введите число", .tooLong: "Не больше %d символов", .chooseOption: "Выберите вариант",
            .fileTooLarge: "Файл слишком большой (макс. %d МБ)", .loading: "Загрузка", .required: "обязательно",
            .opensImage: "Открывает изображение на весь экран", .opensFile: "Открывает файл",
            .newMessage: "Новое сообщение",
            .rating1: "Очень плохо", .rating2: "Плохо", .rating3: "Нормально", .rating4: "Хорошо", .rating5: "Отлично",
            .ratingStars: "%d из 5 звёзд", .ratingComment: "Ваш отзыв", .ratingThanks: "Спасибо за ваш отзыв",
            .ratingYours: "Ваша оценка: %@",
        ],
    ]
}
