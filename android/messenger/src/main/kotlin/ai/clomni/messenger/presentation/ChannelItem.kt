package ai.clomni.messenger.presentation

import java.net.URI
import java.util.Locale

/**
 * One icon of "Bizi izləyin": the platform's monochrome mark (Simple Icons, CC0) in white on its colour, or a Material
 * icon on the surface for email, phone and other links; and its name for TalkBack.
 */
internal data class ChannelItem(
    val id: String,
    val url: String,
    val icon: Icon,
    val tint: Tint,
    val accessibilityLabel: String,
) {
    enum class Icon { INSTAGRAM, WHATSAPP, TELEGRAM, FACEBOOK, MESSENGER, LINKEDIN, YOUTUBE, TIKTOK, X, EMAIL, PHONE, LINK }

    sealed interface Tint {
        /** The platform's colour behind a white mark. */
        data class Brand(val color: RgbColor) : Tint

        /** The theme's surface behind an icon in the text colour (email, phone, links, and black brands). */
        object Neutral : Tint
    }

    private class Style(val name: String, val icon: Icon, val color: String?)

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
                tint = style?.color?.let(RgbColor::parse)?.let { Tint.Brand(it) } ?: Tint.Neutral,
                accessibilityLabel = when (kind) {
                    "email" -> strings[ClomniStrings.Key.EMAIL]
                    "phone" -> strings[ClomniStrings.Key.PHONE]
                    else -> style?.name ?: host(url) ?: url
                },
            )
        }

        private fun host(url: String): String? = runCatching { URI(url).host }.getOrNull()

        private val STYLES = mapOf(
            "instagram" to Style("Instagram", Icon.INSTAGRAM, "#E4405F"),
            "whatsapp" to Style("WhatsApp", Icon.WHATSAPP, "#25D366"),
            "telegram" to Style("Telegram", Icon.TELEGRAM, "#229ED9"),
            "facebook" to Style("Facebook", Icon.FACEBOOK, "#1877F2"),
            "messenger" to Style("Messenger", Icon.MESSENGER, "#0084FF"),
            "linkedin" to Style("LinkedIn", Icon.LINKEDIN, "#0A66C2"),
            "youtube" to Style("YouTube", Icon.YOUTUBE, "#FF0000"),
            "tiktok" to Style("TikTok", Icon.TIKTOK, "#EE1D52"),
            // X's colour is black, which would vanish in dark mode.
            "x" to Style("X", Icon.X, null),
            "twitter" to Style("X", Icon.X, null),
            "email" to Style("", Icon.EMAIL, null),
            "phone" to Style("", Icon.PHONE, null),
        )
    }
}
