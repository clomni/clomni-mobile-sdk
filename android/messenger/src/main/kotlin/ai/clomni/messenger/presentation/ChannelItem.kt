package ai.clomni.messenger.presentation

import java.net.URI
import java.util.Locale

/**
 * One circle of "Bizi izləyin" (DESIGN-PASS-3 D2): the platform's monochrome mark (Simple Icons, CC0) or a Material
 * icon for email, phone and a website, all in the text colour; and its name for TalkBack.
 */
internal data class ChannelItem(
    val id: String,
    val url: String,
    val icon: Icon,
    val accessibilityLabel: String,
) {
    enum class Icon {
        INSTAGRAM, WHATSAPP, TELEGRAM, FACEBOOK, MESSENGER, LINKEDIN, YOUTUBE, TIKTOK, X, EMAIL, PHONE, LINK
    }

    private class Style(val name: String, val icon: Icon)

    companion object {
        fun of(type: String, url: String, strings: ClomniStrings): ChannelItem {
            val scheme = url.substringBefore(':', "").lowercase(Locale.ROOT)
            val kind = when (scheme) {
                "mailto" -> "email"
                "tel" -> "phone"
                else -> type.lowercase(Locale.ROOT)
            }
            val style = STYLES[kind]
            return ChannelItem(
                id = "$type $url",
                url = url,
                icon = style?.icon ?: Icon.LINK,
                accessibilityLabel = when (kind) {
                    "email" -> strings[ClomniStrings.Key.EMAIL]
                    "phone" -> strings[ClomniStrings.Key.PHONE]
                    else -> style?.name ?: host(url) ?: url
                },
            )
        }

        private fun host(url: String): String? = runCatching { URI(url).host }.getOrNull()

        private val STYLES = mapOf(
            "instagram" to Style("Instagram", Icon.INSTAGRAM),
            "whatsapp" to Style("WhatsApp", Icon.WHATSAPP),
            "telegram" to Style("Telegram", Icon.TELEGRAM),
            "facebook" to Style("Facebook", Icon.FACEBOOK),
            "messenger" to Style("Messenger", Icon.MESSENGER),
            "linkedin" to Style("LinkedIn", Icon.LINKEDIN),
            "youtube" to Style("YouTube", Icon.YOUTUBE),
            "tiktok" to Style("TikTok", Icon.TIKTOK),
            "x" to Style("X", Icon.X),
            "twitter" to Style("X", Icon.X),
            "email" to Style("", Icon.EMAIL),
            "phone" to Style("", Icon.PHONE),
        )
    }
}
