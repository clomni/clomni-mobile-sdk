package ai.clomni.messenger.protocol

/**
 * GET /v1/mobile/config, version 2 (APPEARANCE-CONTRACT 1): the messenger's look and texts as set in the Clomni panel.
 * Every field the server leaves out, or sends broken, has a default here, so a minimal config is enough to open the
 * messenger.
 */
internal data class MessengerConfig(
    /** The published appearance's version; 0 when the server does not say. */
    val version: Int,
    val brand: Brand,
    val team: Team,
    val bot: Bot,
    val home: Home,
    val theme: ThemeSettings,
    val composer: Composer,
    /** As sent; never empty (`az` when the server sends none). */
    val languages: List<String>,
    /** The selected language's texts: protocol/strings.json with the panel's overrides; the SDK fills any gap. */
    val strings: Map<String, String>,
    val limits: Limits,
    /** "Powered by Clomni" under Home; false only where the plan allows. */
    val poweredBy: Boolean,
) {
    data class Brand(
        val name: String,
        val logoUrl: String?,
        /** For dark mode; [logoUrl] when null. */
        val logoDarkUrl: String?,
        /** `#RRGGBB`; [DEFAULT_PRIMARY_COLOR] when missing or not a colour. */
        val primaryColor: String,
        val headerStyle: HeaderStyle,
        /** For [HeaderStyle.IMAGE]. */
        val headerImageUrl: String?,
        /** A soft glow of the brand colour behind the header. */
        val glow: Boolean,
        /** The colours the server derived; null makes the SDK derive them by the same rules. */
        val colors: Colors?,
    ) {
        companion object {
            /** Clomni green, used when the config has no valid brand colour. */
            const val DEFAULT_PRIMARY_COLOR: String = "#10A670"
        }
    }

    enum class HeaderStyle { GRADIENT, SOLID, IMAGE }

    data class Colors(val light: Palette, val dark: Palette)

    /** `#RRGGBB` each. */
    data class Palette(
        val primary: String,
        val onPrimary: String,
        /** The brand at 10% over the background: placeholders, soft backgrounds. */
        val primarySoft: String,
        /** The brand at 22%: pill borders. */
        val primaryLine: String,
        /** The header's top and bottom. */
        val headerFrom: String,
        val headerTo: String,
        /** Text and icons on the header; null from a server before it sent one: the SDK works it out. */
        val headerText: String? = null,
    )

    data class Team(
        /** The team's avatars on Home and in the conversation's header. */
        val show: Boolean,
        val avatars: List<String>,
        val replyTime: String?,
        /** Instead of [replyTime] after hours. */
        val replyTimeOffline: String?,
        val officeHours: OfficeHours?,
    )

    data class OfficeHours(
        val timeZone: String?,
        val openNow: Boolean,
        /** Epoch milliseconds, UTC: when the team is back, while [openNow] is false; null when the server has none. */
        val nextOpenAt: Long? = null,
    )

    /** [avatarUrl] null: the brand's logo, else the initial. */
    data class Bot(val name: String, val avatarUrl: String?)

    data class Home(
        /** In the panel's order; [HomeCard.SEND] is always there. */
        val cards: List<HomeCard>,
        /** At most five, in the panel's order. */
        val channels: List<Channel>,
        /** The greeting's size, chosen in the panel. */
        val titleSize: TitleSize = TitleSize.M,
    )

    enum class HomeCard { SEND, RECENT, CHANNELS }

    /** `home.title_size`: the greeting's two lines, sp (first line normal, second semibold). Unknown: [M]. */
    enum class TitleSize(val firstLine: Float, val secondLine: Float) {
        S(15f, 20f),
        M(17f, 24f),
        L(19f, 28f),
    }

    /** A social channel icon on Home; [type] is open-ended (instagram, whatsapp, linkedin, email, …). */
    data class Channel(val type: String, val url: String)

    data class ThemeSettings(val mode: ThemeMode, val launcher: Launcher)

    enum class ThemeMode { SYSTEM, LIGHT, DARK }

    data class Launcher(
        /** Off unless the panel (or the app) turns it on. */
        val enabled: Boolean,
        val position: LauncherPosition,
        /** dp, 0–200. */
        val bottomPadding: Int,
    )

    enum class LauncherPosition { LEFT, RIGHT }

    data class Composer(val attachments: Boolean, val emoji: Boolean)

    data class Limits(val imageMb: Int, val fileMb: Int, val textChars: Int)

    companion object {
        const val MAX_CHANNELS = 5
    }
}
