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
        NEW_CONVERSATION("new_conversation"),
        GREETING_HELLO("greeting_hello"),
        GREETING_TITLE("greeting_title"),
        RECENT_MESSAGE("recent_message"),
        FOLLOW_US("follow_us"),
        TAB_HOME("tab_home"),
        TAB_MESSAGES("tab_messages"),
        NO_CONVERSATIONS("no_conversations"),
        ERROR("error"),
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
        TEAM_CAN_HELP("team_can_help"),
        ONLINE("online"),
        AWAY("away"),
        AWAY_UNTIL("away_until"),
        MESSAGE_PLACEHOLDER("message_placeholder"),
        CHOOSE_ABOVE("choose_above"),
        SENDING("sending"),
        SENT("sent"),
        READ("read"),
        FAILED("failed"),
        CONVERSATION_CLOSED("conversation_closed"),
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
                Key.NEW_CONVERSATION to "Bizə mesaj göndərin", Key.GREETING_HELLO to "Salam",
                Key.GREETING_TITLE to "Necə kömək edə bilərik?", Key.RECENT_MESSAGE to "Son mesaj",
                Key.FOLLOW_US to "Bizi izləyin", Key.TAB_HOME to "Ana səhifə", Key.TAB_MESSAGES to "Mesajlar",
                Key.NO_CONVERSATIONS to "Hələ söhbət yoxdur", Key.ERROR to "Nəsə səhv getdi",
                Key.RETRY to "Yenidən cəhd et", Key.OFFLINE to "İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq",
                Key.NOW to "indi", Key.YOU to "Siz", Key.CLOSE to "Bağla", Key.UNREAD to "Oxunmamış",
                Key.UNREAD_MESSAGES to "Oxunmamış mesaj var", Key.MINUTES_SHORT to "%d dəq",
                Key.HOURS_SHORT to "%d saat", Key.DAYS_SHORT to "%d gün", Key.EMAIL to "E-poçt", Key.PHONE to "Telefon",
                Key.TEAM_CAN_HELP to "Komanda da kömək edə bilər", Key.ONLINE to "onlayn",
                Key.AWAY to "Hazırda iş saatı deyil", Key.AWAY_UNTIL to "Növbəti iş saatı: %@",
                Key.MESSAGE_PLACEHOLDER to "Mesaj yazın…", Key.CHOOSE_ABOVE to "Yuxarıdakı variantlardan birini seçin",
                Key.SENDING to "Göndərilir", Key.SENT to "Göndərildi", Key.READ to "Oxundu", Key.FAILED to "Göndərilmədi",
                Key.CONVERSATION_CLOSED to "Söhbət bağlanıb", Key.START_NEW_CONVERSATION to "Yeni söhbət başlat",
                Key.BACK to "← Geri", Key.GO_BACK to "Geri", Key.BOT to "Bot", Key.TYPING to "yazır",
                Key.ATTACH to "Fayl əlavə et", Key.EMOJI to "Emoji", Key.IMAGE to "Şəkil", Key.FILE to "Fayl",
                Key.FIELD_REQUIRED to "Bu sahəni doldurun", Key.INVALID_EMAIL to "Email düzgün deyil",
                Key.INVALID_PHONE to "Telefon nömrəsi düzgün deyil", Key.INVALID_NUMBER to "Rəqəm yazın",
                Key.TOO_LONG to "Ən çox %d simvol", Key.CHOOSE_OPTION to "Variantlardan birini seçin",
                Key.FILE_TOO_LARGE to "Fayl çox böyükdür (maks. %d MB)", Key.SUPPORT_MESSAGES to "Dəstək mesajları",
            ),
            "en" to mapOf(
                Key.TODAY to "Today", Key.YESTERDAY to "Yesterday", Key.TOMORROW to "tomorrow", Key.SEND to "Send",
                Key.NEW_CONVERSATION to "Send us a message", Key.GREETING_HELLO to "Hi",
                Key.GREETING_TITLE to "How can we help?", Key.RECENT_MESSAGE to "Recent message",
                Key.FOLLOW_US to "Follow us", Key.TAB_HOME to "Home", Key.TAB_MESSAGES to "Messages",
                Key.NO_CONVERSATIONS to "No conversations yet", Key.ERROR to "Something went wrong",
                Key.RETRY to "Try again",
                Key.OFFLINE to "No internet. Messages will be delivered when you are back online",
                Key.NOW to "now", Key.YOU to "You", Key.CLOSE to "Close", Key.UNREAD to "Unread",
                Key.UNREAD_MESSAGES to "Unread messages", Key.MINUTES_SHORT to "%d min", Key.HOURS_SHORT to "%d h",
                Key.DAYS_SHORT to "%d d", Key.EMAIL to "Email", Key.PHONE to "Phone",
                Key.TEAM_CAN_HELP to "The team can help too", Key.ONLINE to "online",
                Key.AWAY to "Outside working hours", Key.AWAY_UNTIL to "Next working hours: %@",
                Key.MESSAGE_PLACEHOLDER to "Write a message…", Key.CHOOSE_ABOVE to "Choose one of the options above",
                Key.SENDING to "Sending", Key.SENT to "Sent", Key.READ to "Read", Key.FAILED to "Not sent",
                Key.CONVERSATION_CLOSED to "Conversation closed", Key.START_NEW_CONVERSATION to "Start a new conversation",
                Key.BACK to "← Back", Key.GO_BACK to "Back", Key.BOT to "Bot",
                Key.TYPING to "is typing", Key.ATTACH to "Attach a file", Key.EMOJI to "Emoji", Key.IMAGE to "Image",
                Key.FILE to "File", Key.FIELD_REQUIRED to "Fill in this field", Key.INVALID_EMAIL to "Enter a valid email",
                Key.INVALID_PHONE to "Enter a valid phone number", Key.INVALID_NUMBER to "Enter a number",
                Key.TOO_LONG to "At most %d characters", Key.CHOOSE_OPTION to "Choose one of the options",
                Key.FILE_TOO_LARGE to "The file is too large (max %d MB)", Key.SUPPORT_MESSAGES to "Support messages",
            ),
            "ru" to mapOf(
                Key.TODAY to "Сегодня", Key.YESTERDAY to "Вчера", Key.TOMORROW to "завтра", Key.SEND to "Отправить",
                Key.NEW_CONVERSATION to "Напишите нам", Key.GREETING_HELLO to "Здравствуйте",
                Key.GREETING_TITLE to "Чем можем помочь?", Key.RECENT_MESSAGE to "Последнее сообщение",
                Key.FOLLOW_US to "Мы в соцсетях", Key.TAB_HOME to "Главная", Key.TAB_MESSAGES to "Сообщения",
                Key.NO_CONVERSATIONS to "Пока нет переписки", Key.ERROR to "Что-то пошло не так",
                Key.RETRY to "Повторить", Key.OFFLINE to "Нет интернета, сообщения будут доставлены позже",
                Key.NOW to "сейчас", Key.YOU to "Вы", Key.CLOSE to "Закрыть", Key.UNREAD to "Не прочитано",
                Key.UNREAD_MESSAGES to "Есть непрочитанные сообщения", Key.MINUTES_SHORT to "%d мин",
                Key.HOURS_SHORT to "%d ч", Key.DAYS_SHORT to "%d дн", Key.EMAIL to "Почта", Key.PHONE to "Телефон",
                Key.TEAM_CAN_HELP to "Команда тоже может помочь", Key.ONLINE to "в сети",
                Key.AWAY to "Сейчас нерабочее время", Key.AWAY_UNTIL to "Следующее рабочее время: %@",
                Key.MESSAGE_PLACEHOLDER to "Напишите сообщение…", Key.CHOOSE_ABOVE to "Выберите один из вариантов выше",
                Key.SENDING to "Отправляется", Key.SENT to "Отправлено", Key.READ to "Прочитано",
                Key.FAILED to "Не отправлено", Key.CONVERSATION_CLOSED to "Диалог закрыт",
                Key.START_NEW_CONVERSATION to "Начать новый диалог", Key.BACK to "← Назад", Key.GO_BACK to "Назад",
                Key.BOT to "Бот", Key.TYPING to "печатает", Key.ATTACH to "Прикрепить файл",
                Key.EMOJI to "Эмодзи", Key.IMAGE to "Изображение", Key.FILE to "Файл",
                Key.FIELD_REQUIRED to "Заполните это поле", Key.INVALID_EMAIL to "Неверный email",
                Key.INVALID_PHONE to "Неверный номер телефона", Key.INVALID_NUMBER to "Введите число",
                Key.TOO_LONG to "Не больше %d символов", Key.CHOOSE_OPTION to "Выберите вариант",
                Key.FILE_TOO_LARGE to "Файл слишком большой (макс. %d МБ)", Key.SUPPORT_MESSAGES to "Сообщения поддержки",
            ),
        )
    }
}
