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
    }

    /** az, en or ru; anything else reads as az. */
    val language: String = (language ?: "az").lowercase(Locale.ROOT).take(2).takeIf { it in FALLBACKS } ?: "az"

    operator fun get(key: Key): String =
        overrides[key.wire]?.takeIf { it.isNotEmpty() } ?: FALLBACKS.getValue(language)[key] ?: key.wire

    /** A text with one number in it ("%d dəq"). */
    fun format(key: Key, number: Int): String = get(key).replace("%d", number.toString())

    /** Month names as they stand before or after a day ("1 oktyabr", "1 октября", "October 1"). */
    val months: List<String> get() = MONTHS.getValue(language)

    companion object {
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
                Key.TODAY to "Bu gün", Key.YESTERDAY to "Dünən", Key.SEND to "Göndər",
                Key.NEW_CONVERSATION to "Bizə mesaj göndərin", Key.GREETING_HELLO to "Salam",
                Key.GREETING_TITLE to "Necə kömək edə bilərik?", Key.RECENT_MESSAGE to "Son mesaj",
                Key.FOLLOW_US to "Bizi izləyin", Key.TAB_HOME to "Ana səhifə", Key.TAB_MESSAGES to "Mesajlar",
                Key.NO_CONVERSATIONS to "Hələ söhbət yoxdur", Key.ERROR to "Nəsə səhv getdi",
                Key.RETRY to "Yenidən cəhd et", Key.OFFLINE to "İnternet yoxdur, mesajlar göndəriləndə çatdırılacaq",
                Key.NOW to "indi", Key.YOU to "Siz", Key.CLOSE to "Bağla", Key.UNREAD to "Oxunmamış",
                Key.UNREAD_MESSAGES to "Oxunmamış mesaj var", Key.MINUTES_SHORT to "%d dəq",
                Key.HOURS_SHORT to "%d saat", Key.DAYS_SHORT to "%d gün", Key.EMAIL to "E-poçt", Key.PHONE to "Telefon",
            ),
            "en" to mapOf(
                Key.TODAY to "Today", Key.YESTERDAY to "Yesterday", Key.SEND to "Send",
                Key.NEW_CONVERSATION to "Send us a message", Key.GREETING_HELLO to "Hi",
                Key.GREETING_TITLE to "How can we help?", Key.RECENT_MESSAGE to "Recent message",
                Key.FOLLOW_US to "Follow us", Key.TAB_HOME to "Home", Key.TAB_MESSAGES to "Messages",
                Key.NO_CONVERSATIONS to "No conversations yet", Key.ERROR to "Something went wrong",
                Key.RETRY to "Try again", Key.OFFLINE to "No internet. Messages will be delivered when you are back online",
                Key.NOW to "now", Key.YOU to "You", Key.CLOSE to "Close", Key.UNREAD to "Unread",
                Key.UNREAD_MESSAGES to "Unread messages", Key.MINUTES_SHORT to "%d min", Key.HOURS_SHORT to "%d h",
                Key.DAYS_SHORT to "%d d", Key.EMAIL to "Email", Key.PHONE to "Phone",
            ),
            "ru" to mapOf(
                Key.TODAY to "Сегодня", Key.YESTERDAY to "Вчера", Key.SEND to "Отправить",
                Key.NEW_CONVERSATION to "Напишите нам", Key.GREETING_HELLO to "Здравствуйте",
                Key.GREETING_TITLE to "Чем можем помочь?", Key.RECENT_MESSAGE to "Последнее сообщение",
                Key.FOLLOW_US to "Мы в соцсетях", Key.TAB_HOME to "Главная", Key.TAB_MESSAGES to "Сообщения",
                Key.NO_CONVERSATIONS to "Пока нет переписки", Key.ERROR to "Что-то пошло не так",
                Key.RETRY to "Повторить", Key.OFFLINE to "Нет интернета, сообщения будут доставлены позже",
                Key.NOW to "сейчас", Key.YOU to "Вы", Key.CLOSE to "Закрыть", Key.UNREAD to "Не прочитано",
                Key.UNREAD_MESSAGES to "Есть непрочитанные сообщения", Key.MINUTES_SHORT to "%d мин",
                Key.HOURS_SHORT to "%d ч", Key.DAYS_SHORT to "%d дн", Key.EMAIL to "Почта", Key.PHONE to "Телефон",
            ),
        )
    }
}
