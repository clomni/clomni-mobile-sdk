package ai.clomni.messenger.protocol

/**
 * GET /v1/mobile/config, version 2 (APPEARANCE-CONTRACT 1): the messenger's look and texts as set in the Clomni panel.
 * Every field the server leaves out, or sends broken, has a default here, so a minimal config is enough to open the
 * messenger.
 */
/**
 * The language the Messenger speaks with this config (DESIGN-PASS-3 D1): [host]'s (`Clomni.setLanguage`) if the panel
 * has it on, else the device's if on, else the panel's main language.
 */
internal fun MessengerConfig?.speaks(host: String?, device: String? = java.util.Locale.getDefault().language): String =
    (this?.languages ?: MessengerConfig.Languages()).pick(host, device)

internal data class MessengerConfig(
    /** The published appearance's version; 0 when the server does not say. */
    val version: Int,
    val brand: Brand,
    val team: Team,
    val bot: Bot,
    val home: Home,
    val theme: ThemeSettings,
    val composer: Composer,
    /** The languages the panel turned on and the one to fall back to (DESIGN-PASS-3 D1). */
    val languages: Languages = Languages(),
    /** The selected language's texts: protocol/strings.json with the panel's overrides; the SDK fills any gap. */
    val strings: Map<String, String>,
    val limits: Limits,
    /** "Powered by Clomni" under Home; false only where the plan allows. */
    val poweredBy: Boolean,
    /** `conversation.starts_with_flow`: a new conversation starts a flow, so it is created as soon as it opens. */
    val startsWithFlow: Boolean = false,
    /** Short sounds for a sent and a received message; the app can still turn them off. */
    val sounds: Boolean = true,
    /**
     * The language [strings] are in: the one asked for when the panel has it on, else the panel's default. Null for a
     * config kept by an older SDK, whose strings are taken as they are.
     */
    val stringsLanguage: String? = null,
) {
    /**
     * [strings] when they are in [language]; none otherwise, so a config kept in one language does not mix its texts
     * into another (test report: English online, Azerbaijani offline). The SDK's own texts of [language] stand in.
     */
    fun strings(language: String): Map<String, String> =
        if (stringsLanguage == null || stringsLanguage == language) strings else emptyMap()

    /** The config's strings as answered for a request in [requested]. */
    fun answeredIn(requested: String?): MessengerConfig =
        copy(stringsLanguage = requested?.let(Languages::base)?.takeIf { it in languages.enabled } ?: languages.default)

    /**
     * `languages {enabled, default}`; absent, all three are on and az is the default. The Messenger speaks the host's
     * language when it is on, else the device's when it is on, else [default] ([pick]); with one on, always that one.
     */
    data class Languages(val enabled: List<String> = ALL, val default: String = "az") {
        fun pick(host: String?, device: String?): String =
            listOfNotNull(host, device).map { base(it) }.firstOrNull { it in enabled } ?: default

        companion object {
            val ALL = listOf("az", "en", "ru")

            /** "en-GB", "ru_RU" → "en", "ru". */
            fun base(tag: String): String = tag.lowercase(java.util.Locale.ROOT).substringBefore('-').substringBefore('_')
        }
    }

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
        /**
         * The full written logo for Home's header, in place of the logo and the name (`logo_style: "wordmark"`); null
         * for the mark, also when the server sent the style without a picture.
         */
        val wordmarkUrl: String? = null,
        /** For dark mode; [wordmarkUrl] when null. */
        val wordmarkDarkUrl: String? = null,
        /** The logo's height, % of 32 dp (60–200, the panel's slider); 100 when not set. */
        val logoScale: Int = 100,
    ) {
        companion object {
            /** For [ai.clomni.messenger.presentation.ClomniTheme]'s grey before any config: the secondary text grey. */
            internal val neutral = Brand(
                name = "",
                logoUrl = null,
                logoDarkUrl = null,
                primaryColor = "#6A6E7A",
                headerStyle = HeaderStyle.SOLID,
                headerImageUrl = null,
                glow = false,
                colors = null,
            )

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
        /** Home's first greeting line (at about 70%); null from a server before it sent one. */
        val primaryStrong: String? = null,
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
        /** In the panel's order; [HomeCard.MESSAGES] and [HomeCard.SEND] are always there. */
        val cards: List<HomeCard>,
        /** At most five, in the panel's order. */
        val channels: List<Channel>,
        /** The greeting's size, % of 28 (70–140, the panel's slider); 100 when not set. */
        val titleScale: Int = 100,
    )

    /** The default order is [entries]'. */
    enum class HomeCard { MESSAGES, RECENT, SEND, NEWS, CHANNELS }

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

    /** [voiceSeconds]: the longest voice message; the recorder stops there. */
    data class Limits(val imageMb: Int, val fileMb: Int, val textChars: Int, val voiceSeconds: Int = DEFAULT_VOICE_SECONDS)

    companion object {
        const val MAX_CHANNELS = 5

        /** Five minutes, when the config does not say (protocol config.json limits.voice_seconds). */
        const val DEFAULT_VOICE_SECONDS = 300
    }
}
