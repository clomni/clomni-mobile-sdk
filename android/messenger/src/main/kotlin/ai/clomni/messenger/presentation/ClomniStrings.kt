package ai.clomni.messenger.presentation

import java.util.Locale

/**
 * The texts of the messenger. The config's `strings` (set in the panel, in the user's language) come first; the SDK
 * carries az, en and ru for every key, so a minimal config still reads well. The same keys and texts as iOS.
 */
internal class ClomniStrings(language: String?, private val overrides: Map<String, String> = emptyMap()) {

    enum class Key(val wire: String) {
        TODAY("today"),
        YESTERDAY("yesterday"),
        TOMORROW("tomorrow"),
        SEND("send"),
        SEND_CARD_TITLE("send_card_title"),
        GREETING_LINE1("greeting_line1"),
        GREETING_LINE1_ANONYMOUS("greeting_line1_anonymous"),
        GREETING_LINE2("greeting_line2"),
        RECENT_MESSAGE("recent_message"),
        FOLLOW_US("follow_us"),
        TAB_HOME("tab_home"),
        TAB_MESSAGES("tab_messages"),
        EMPTY_LIST("empty_list"),
        ERROR("error"),

        /** TalkBack's name of the loading indicator. */
        LOADING("loading"),
        RETRY("retry"),
        OFFLINE("offline"),
        NOW("now"),
        YOU("you"),
        CLOSE("close"),
        UNREAD("unread"),
        EMAIL("email"),
        PHONE("phone"),
        UNREAD_MESSAGES("unread_messages"),
        MINUTES_SHORT("minutes_short"),
        HOURS_SHORT("hours_short"),
        DAYS_SHORT("days_short"),

        // The conversation (CM-073).
        HEADER_SUBTITLE("header_subtitle"),
        ONLINE("online"),
        AWAY("away"),
        AWAY_UNTIL("away_until"),
        COMPOSER_PLACEHOLDER("composer_placeholder"),
        CHOOSE_ABOVE("choose_above"),
        SENDING("sending"),
        SENT("sent"),
        READ("read"),
        FAILED("failed"),
        CLOSED("closed"),
        START_NEW_CONVERSATION("start_new_conversation"),
        BACK("back"),
        GO_BACK("go_back"),
        BOT("bot"),
        TYPING("typing"),
        ATTACH("attach"),
        EMOJI("emoji"),
        IMAGE("image"),
        FILE("file"),
        FIELD_REQUIRED("field_required"),

        /** TalkBack, after a form field's name: "Ad, soyad, məcburi" (the screen shows "*"). */
        REQUIRED("required"),
        INVALID_EMAIL("invalid_email"),
        INVALID_PHONE("invalid_phone"),
        INVALID_NUMBER("invalid_number"),
        TOO_LONG("too_long"),
        CHOOSE_OPTION("choose_option"),
        FILE_TOO_LARGE("file_too_large"),

        // Push (CM-075): the Android notification channel's name.
        SUPPORT_MESSAGES("support_messages"),
    }

    /** az, en or ru; anything else reads as az. */
    val language: String = (language ?: "az").lowercase(Locale.ROOT).take(2).takeIf { it in FALLBACKS } ?: "az"

    operator fun get(key: Key): String =
        overrides[key.wire]?.takeIf { it.isNotEmpty() } ?: FALLBACKS.getValue(language)[key] ?: key.wire

    /**
     * Home's first line: greeting_line1 with `{name}` (the user's name) and `{first_name}`, or
     * greeting_line1_anonymous when nobody with a name is logged in.
     */
    fun greeting(name: String?): String {
        val full = name?.trim()?.takeIf { it.isNotEmpty() } ?: return get(Key.GREETING_LINE1_ANONYMOUS)
        val first = full.split(Regex("\\s+")).first()
        return get(Key.GREETING_LINE1).replace("{name}", full).replace("{first_name}", first)
    }

    /** A text with one number in it ("%d dəq"). */
    fun format(key: Key, number: Int): String = get(key).replace("%d", number.toString())

    /** A text with one word in it ("Növbəti iş saatı: %@"; protocol/strings.json's placeholder). */
    fun format(key: Key, text: String): String = get(key).replace("%@", text)

    /**
     * TalkBack for a flow button: "Azərbaycan dili, 1-ci, cəmi 3". The button role is read by the system itself, in
     * the system's language, so the text does not say "Düymə" again.
     */
    fun buttonPosition(title: String, index: Int, count: Int): String = when (language) {
        "en" -> "$title, $index of $count"
        "ru" -> "$title, $index из $count"
        else -> "$title, $index-${azerbaijaniOrdinalSuffix(index)}, cəmi $count"
    }

    /** Month names as they stand before or after a day ("1 oktyabr", "1 октября", "October 1"). */
    val months: List<String> get() = MONTHS.getValue(language)

    companion object {
        /** The suffix follows the vowel of the number's last word: 1-ci, 3-cü, 6-cı, 9-cu, 10-cu, 40-cı. */
        fun azerbaijaniOrdinalSuffix(number: Int): String {
            val ones = listOf("", "ci", "ci", "cü", "cü", "ci", "cı", "ci", "ci", "cu")
            val tens = listOf("", "cu", "ci", "cu", "cı", "ci", "cı", "ci", "ci", "cı")
            val value = Math.abs(number) % 100
            return when {
                value % 10 != 0 -> ones[value % 10]
                value != 0 -> tens[value / 10]
                Math.abs(number) % 1000 == 0 -> "ci"
                else -> "cü"
            }
        }

        private val MONTHS = mapOf(
            "az" to listOf(
                "yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avqust", "sentyabr", "oktyabr", "noyabr",
                "dekabr",
            ),
            "en" to listOf(
                "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                "November", "December",
            ),
            "ru" to listOf(
                "января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября",
                "ноября", "декабря",
            ),
        )

        val FALLBACKS: Map<String, Map<Key, String>> = mapOf(
            "az" to mapOf(
                Key.TODAY to "Bu gün", Key.YESTERDAY to "Dünən", Key.TOMORROW to "sabah", Key.SEND to "Göndər",
                Key.SEND_CARD_TITLE to "Bizə mesaj göndərin", Key.GREETING_LINE1 to "Salam, {first_name}", Key.GREETING_LINE1_ANONYMOUS to "Salam",
                Key.GREETING_LINE2 to "Necə kömək edə bilərik?", Key.RECENT_MESSAGE to "Son mesaj",
                Key.FOLLOW_US to "Bizi izləyin", Key.TAB_HOME to "Ana səhifə", Key.TAB_MESSAGES to "Mesajlar",
                Key.EMPTY_LIST to "Hələ söhbət yoxdur", Key.ERROR to "Nəsə səhv getdi", Key.LOADING to "Yüklənir",
                Key.RETRY to "Yenidən cəhd et", Key.OFFLINE to "İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq",
                Key.NOW to "indi", Key.YOU to "Siz", Key.CLOSE to "Bağla", Key.UNREAD to "Oxunmamış",
                Key.UNREAD_MESSAGES to "Oxunmamış mesaj var", Key.MINUTES_SHORT to "%d dəq",
                Key.HOURS_SHORT to "%d saat", Key.DAYS_SHORT to "%d gün", Key.EMAIL to "E-poçt", Key.PHONE to "Telefon",
                Key.HEADER_SUBTITLE to "Komanda da kömək edə bilər", Key.ONLINE to "onlayn",
                Key.AWAY to "Hazırda iş saatı deyil", Key.AWAY_UNTIL to "Növbəti iş saatı: %@",
                Key.COMPOSER_PLACEHOLDER to "Mesaj yazın…", Key.CHOOSE_ABOVE to "Yuxarıdakı variantlardan birini seçin",
                Key.SENDING to "Göndərilir", Key.SENT to "Göndərildi", Key.READ to "Oxundu", Key.FAILED to "Göndərilmədi",
                Key.CLOSED to "Söhbət bağlanıb", Key.START_NEW_CONVERSATION to "Yeni söhbət başlat",
                Key.BACK to "← Geri", Key.GO_BACK to "Geri", Key.BOT to "Bot", Key.TYPING to "yazır",
                Key.ATTACH to "Fayl əlavə et", Key.EMOJI to "Emoji", Key.IMAGE to "Şəkil", Key.FILE to "Fayl",
                Key.FIELD_REQUIRED to "Bu sahəni doldurun", Key.REQUIRED to "məcburi", Key.INVALID_EMAIL to "Email düzgün deyil",
                Key.INVALID_PHONE to "Telefon nömrəsi düzgün deyil", Key.INVALID_NUMBER to "Rəqəm yazın",
                Key.TOO_LONG to "Ən çox %d simvol", Key.CHOOSE_OPTION to "Variantlardan birini seçin",
                Key.FILE_TOO_LARGE to "Fayl çox böyükdür (maks. %d MB)", Key.SUPPORT_MESSAGES to "Dəstək mesajları",
            ),
            "en" to mapOf(
                Key.TODAY to "Today", Key.YESTERDAY to "Yesterday", Key.TOMORROW to "tomorrow", Key.SEND to "Send",
                Key.SEND_CARD_TITLE to "Send us a message", Key.GREETING_LINE1 to "Hi, {first_name}", Key.GREETING_LINE1_ANONYMOUS to "Hi",
                Key.GREETING_LINE2 to "How can we help?", Key.RECENT_MESSAGE to "Recent message",
                Key.FOLLOW_US to "Follow us", Key.TAB_HOME to "Home", Key.TAB_MESSAGES to "Messages",
                Key.EMPTY_LIST to "No conversations yet", Key.ERROR to "Something went wrong", Key.LOADING to "Loading",
                Key.RETRY to "Try again",
                Key.OFFLINE to "No internet. Messages will be delivered when you are back online",
                Key.NOW to "now", Key.YOU to "You", Key.CLOSE to "Close", Key.UNREAD to "Unread",
                Key.UNREAD_MESSAGES to "Unread messages", Key.MINUTES_SHORT to "%d min", Key.HOURS_SHORT to "%d h",
                Key.DAYS_SHORT to "%d d", Key.EMAIL to "Email", Key.PHONE to "Phone",
                Key.HEADER_SUBTITLE to "The team can help too", Key.ONLINE to "online",
                Key.AWAY to "Outside working hours", Key.AWAY_UNTIL to "Next working hours: %@",
                Key.COMPOSER_PLACEHOLDER to "Write a message…", Key.CHOOSE_ABOVE to "Choose one of the options above",
                Key.SENDING to "Sending", Key.SENT to "Sent", Key.READ to "Read", Key.FAILED to "Not sent",
                Key.CLOSED to "Conversation closed", Key.START_NEW_CONVERSATION to "Start a new conversation",
                Key.BACK to "← Back", Key.GO_BACK to "Back", Key.BOT to "Bot",
                Key.TYPING to "is typing", Key.ATTACH to "Attach a file", Key.EMOJI to "Emoji", Key.IMAGE to "Image",
                Key.FILE to "File", Key.FIELD_REQUIRED to "Fill in this field", Key.REQUIRED to "required",
                Key.INVALID_EMAIL to "Enter a valid email",
                Key.INVALID_PHONE to "Enter a valid phone number", Key.INVALID_NUMBER to "Enter a number",
                Key.TOO_LONG to "At most %d characters", Key.CHOOSE_OPTION to "Choose one of the options",
                Key.FILE_TOO_LARGE to "The file is too large (max %d MB)", Key.SUPPORT_MESSAGES to "Support messages",
            ),
            "ru" to mapOf(
                Key.TODAY to "Сегодня", Key.YESTERDAY to "Вчера", Key.TOMORROW to "завтра", Key.SEND to "Отправить",
                Key.SEND_CARD_TITLE to "Напишите нам", Key.GREETING_LINE1 to "Здравствуйте, {first_name}", Key.GREETING_LINE1_ANONYMOUS to "Здравствуйте",
                Key.GREETING_LINE2 to "Чем можем помочь?", Key.RECENT_MESSAGE to "Последнее сообщение",
                Key.FOLLOW_US to "Мы в соцсетях", Key.TAB_HOME to "Главная", Key.TAB_MESSAGES to "Сообщения",
                Key.EMPTY_LIST to "Пока нет переписки", Key.ERROR to "Что-то пошло не так", Key.LOADING to "Загрузка",
                Key.RETRY to "Повторить", Key.OFFLINE to "Нет интернета, сообщения будут доставлены позже",
                Key.NOW to "сейчас", Key.YOU to "Вы", Key.CLOSE to "Закрыть", Key.UNREAD to "Не прочитано",
                Key.UNREAD_MESSAGES to "Есть непрочитанные сообщения", Key.MINUTES_SHORT to "%d мин",
                Key.HOURS_SHORT to "%d ч", Key.DAYS_SHORT to "%d дн", Key.EMAIL to "Почта", Key.PHONE to "Телефон",
                Key.HEADER_SUBTITLE to "Команда тоже может помочь", Key.ONLINE to "в сети",
                Key.AWAY to "Сейчас нерабочее время", Key.AWAY_UNTIL to "Следующее рабочее время: %@",
                Key.COMPOSER_PLACEHOLDER to "Напишите сообщение…", Key.CHOOSE_ABOVE to "Выберите один из вариантов выше",
                Key.SENDING to "Отправляется", Key.SENT to "Отправлено", Key.READ to "Прочитано",
                Key.FAILED to "Не отправлено", Key.CLOSED to "Диалог закрыт",
                Key.START_NEW_CONVERSATION to "Начать новый диалог", Key.BACK to "← Назад", Key.GO_BACK to "Назад",
                Key.BOT to "Бот", Key.TYPING to "печатает", Key.ATTACH to "Прикрепить файл",
                Key.EMOJI to "Эмодзи", Key.IMAGE to "Изображение", Key.FILE to "Файл",
                Key.FIELD_REQUIRED to "Заполните это поле", Key.REQUIRED to "обязательно", Key.INVALID_EMAIL to "Неверный email",
                Key.INVALID_PHONE to "Неверный номер телефона", Key.INVALID_NUMBER to "Введите число",
                Key.TOO_LONG to "Не больше %d символов", Key.CHOOSE_OPTION to "Выберите вариант",
                Key.FILE_TOO_LARGE to "Файл слишком большой (макс. %d МБ)", Key.SUPPORT_MESSAGES to "Сообщения поддержки",
            ),
        )
    }
}
