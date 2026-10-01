package ai.clomni.messenger.protocol

/**
 * GET /v1/mobile/config (`protocol/schema/config.json`). Every field the server leaves out, or sends broken,
 * has a default here, so a minimal config is enough to open the messenger.
 */
public data class MessengerConfig(
    val brand: Brand,
    val launcher: Launcher,
    val home: Home,
    val team: Team,
    val bot: Bot,
    val composer: Composer,
    /** `az`, `en`, `ru`; never empty. */
    val languages: List<String>,
    /** UI texts by key; a missing key falls back to the SDK's own az/en/ru texts. */
    val strings: Map<String, String>,
    val limits: Limits,
) {
    public data class Brand(
        val name: String,
        val logoUrl: String?,
        /** `#RRGGBB`; [DEFAULT_PRIMARY_COLOR] when missing or not a colour. */
        val primaryColor: String,
        /** `#RRGGBB`, or null to pick white or dark text by contrast. */
        val onPrimaryColor: String?,
        val theme: Theme,
    )

    public enum class Theme { SYSTEM, LIGHT, DARK }

    public data class Launcher(
        /** Off unless the customer turns it on. */
        val visible: Boolean,
        val position: LauncherPosition,
        val bottomPadding: Int,
        val icon: String,
    )

    public enum class LauncherPosition { LEFT, RIGHT }

    public data class Home(
        val greetingTitle: String?,
        val greetingSubtitle: String?,
        val showTeamAvatars: Boolean,
        val channels: List<HomeChannel>,
        val cards: List<HomeCard>,
    )

    /** A link to another channel of the business; [type] is open-ended (instagram, whatsapp, email, …). */
    public data class HomeChannel(val type: String, val url: String)

    public enum class HomeCard { RECENT_CONVERSATION, NEW_CONVERSATION }

    public data class Team(
        val avatars: List<String>,
        val replyTime: String?,
        val officeHours: OfficeHours?,
    )

    public data class OfficeHours(val tz: String?, val openNow: Boolean?)

    public data class Bot(val name: String, val avatarUrl: String?)

    public data class Composer(
        val placeholder: String?,
        val attachments: Boolean,
        val emoji: Boolean,
    )

    public data class Limits(val imageMb: Int, val fileMb: Int, val textChars: Int)

    public companion object {
        /** Clomni green, used when the config has no valid brand colour. */
        public const val DEFAULT_PRIMARY_COLOR: String = "#10A670"
    }
}
