package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.ClomniStrings.Key
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.SenderType
import java.util.Locale
import java.util.TimeZone

/** Everything the Home tab shows, decided here so the Compose view only draws it (brief 8·7.3, 7.5). */
internal data class HomeScreen(
    val phase: Phase,
    val header: Header,
    /** Null hides a card. */
    val newConversation: NewConversationCard?,
    val recent: RecentCard?,
    val channels: ChannelsCard?,
    /** The cards in the panel's order; one without its card above (no channels, nothing recent) is left out. */
    val order: List<MessengerConfig.HomeCard>,
    val tabs: Tabs,
    /** "Powered by Clomni" under the cards, or null where the plan turns it off. */
    val poweredBy: String?,
    /** The thin yellow strip under the header. */
    val offline: String?,
    val failure: Failure?,
) {
    enum class Phase {
        /** Nothing cached yet: grey skeleton blocks, no spinner. */
        LOADING,
        READY,

        /** Nothing cached and the server failed: "Nəsə səhv getdi" + "Yenidən cəhd et". */
        FAILED,
    }

    data class Header(
        val brandName: String,
        val logoUrl: String?,
        /** For dark mode; [logoUrl] when null. */
        val logoDarkUrl: String?,
        val style: MessengerConfig.HeaderStyle,
        /** The photo of [MessengerConfig.HeaderStyle.IMAGE], under a dark veil. */
        val imageUrl: String?,
        /** A soft glow of the brand colour behind the header. */
        val glow: Boolean,
        /** Stands in the logo square while there is no logo. */
        val brandInitial: String,
        /** Up to three, overlapping. */
        val teamAvatars: List<String>,
        /** "Salam, Aysel 👋", smaller than [title] and in the same colour. */
        val greeting: String,
        /** "Necə kömək edə bilərik?" */
        val title: String,
        val closeLabel: String,
    )

    /** "Bizə mesaj göndərin" with the reply time under it. */
    data class NewConversationCard(val title: String, val subtitle: String?, val accessibilityLabel: String)

    data class RecentCard(val label: String, val row: ConversationRow)

    data class ChannelsCard(val label: String, val items: List<ChannelItem>)

    data class Tabs(
        val home: String,
        val messages: String,
        /** The red dot on "Mesajlar". */
        val messagesUnread: Boolean,
        val messagesAccessibilityLabel: String,
    )

    data class Failure(val message: String, val retry: String)
}

/** A conversation in a list, and the "Son mesaj" card. */
internal data class ConversationRow(
    val id: String,
    val avatarUrl: String?,
    /** Shown while the avatar loads, or when there is none. */
    val initial: String,
    /** The last message, one line. */
    val preview: String,
    /** "Leyla · 2 dəq" */
    val detail: String,
    val unread: Boolean,
    val accessibilityLabel: String,
)

/** The Messages tab. */
internal data class MessagesScreen(
    val title: String,
    val phase: HomeScreen.Phase,
    val rows: List<ConversationRow>,
    /** "Hələ söhbət yoxdur", when the list is loaded and empty. */
    val empty: String?,
    val newConversation: HomeScreen.NewConversationCard,
    val offline: String?,
    val failure: HomeScreen.Failure?,
)

/** What the screens are built from. */
internal data class MessengerSnapshot(
    val config: MessengerConfig? = null,
    val configLoad: Load = Load.LOADING,
    /** Newest first. */
    val conversations: List<Conversation> = emptyList(),
    val conversationsLoad: Load = Load.LOADING,
    val unreadTotal: Int = 0,
    /** The logged-in user's name, for the greeting. */
    val userName: String? = null,
    val isOffline: Boolean = false,
) {
    enum class Load { LOADING, LOADED, FAILED }
}

internal class HomePresenter(
    val strings: ClomniStrings,
    timeZone: TimeZone = TimeZone.getDefault(),
    private val now: Long,
) {
    private val time = TimeText(strings, timeZone)

    fun home(snapshot: MessengerSnapshot): HomeScreen {
        val config = snapshot.config
        val cards = config?.home?.cards ?: MessengerConfig.HomeCard.entries
        val recent = if (MessengerConfig.HomeCard.RECENT in cards) {
            snapshot.conversations.asSequence().mapNotNull { row(it, config) }.firstOrNull()
        } else {
            null
        }
        val channels = if (MessengerConfig.HomeCard.CHANNELS in cards) {
            config?.home?.channels.orEmpty().take(MessengerConfig.MAX_CHANNELS).map { ChannelItem.of(it.type, it.url, strings) }
        } else {
            emptyList()
        }
        val failed = config == null && snapshot.configLoad == MessengerSnapshot.Load.FAILED
        return HomeScreen(
            phase = when {
                config != null -> HomeScreen.Phase.READY
                failed -> HomeScreen.Phase.FAILED
                else -> HomeScreen.Phase.LOADING
            },
            header = header(snapshot),
            newConversation = newConversation(config),
            recent = recent?.let { HomeScreen.RecentCard(strings[Key.RECENT_MESSAGE], it) },
            channels = if (channels.isEmpty()) null else HomeScreen.ChannelsCard(strings[Key.FOLLOW_US], channels),
            order = cards.filter {
                when (it) {
                    MessengerConfig.HomeCard.SEND -> true
                    MessengerConfig.HomeCard.RECENT -> recent != null
                    MessengerConfig.HomeCard.CHANNELS -> channels.isNotEmpty()
                }
            },
            tabs = tabs(snapshot),
            poweredBy = if (config?.poweredBy == false) null else POWERED_BY,
            offline = if (snapshot.isOffline) strings[Key.OFFLINE] else null,
            failure = if (failed) failure else null,
        )
    }

    fun messages(snapshot: MessengerSnapshot): MessagesScreen {
        val rows = snapshot.conversations.mapNotNull { row(it, snapshot.config) }
        val failed = rows.isEmpty() && snapshot.conversationsLoad == MessengerSnapshot.Load.FAILED
        val phase = when {
            rows.isNotEmpty() || snapshot.conversationsLoad == MessengerSnapshot.Load.LOADED -> HomeScreen.Phase.READY
            failed -> HomeScreen.Phase.FAILED
            else -> HomeScreen.Phase.LOADING
        }
        return MessagesScreen(
            title = strings[Key.TAB_MESSAGES],
            phase = phase,
            rows = rows,
            empty = if (phase == HomeScreen.Phase.READY && rows.isEmpty()) strings[Key.EMPTY_LIST] else null,
            newConversation = newConversation(snapshot.config),
            offline = if (snapshot.isOffline) strings[Key.OFFLINE] else null,
            failure = if (failed) failure else null,
        )
    }

    /** A conversation with a last message; one without has nothing to show yet. */
    fun row(conversation: Conversation, config: MessengerConfig?): ConversationRow? {
        val message = conversation.lastMessage ?: return null
        val brand = config?.brand?.name.orEmpty()
        val botName = config?.bot?.name?.takeIf { it.isNotEmpty() }
        val name = when (message.sender.type) {
            SenderType.USER -> strings[Key.YOU]
            SenderType.BOT -> message.sender.name ?: botName ?: brand
            SenderType.OPERATOR -> message.sender.name ?: conversation.assignee?.name ?: brand
            SenderType.SYSTEM, SenderType.UNKNOWN -> brand
        }
        // The avatar is the other side's: the operator's, or the bot's.
        val fromUs = message.sender.type == SenderType.USER || message.sender.type == SenderType.SYSTEM
        val otherName = if (fromUs) conversation.assignee?.name ?: botName ?: brand else name
        val botAvatar = botAvatar(config)
        val otherAvatar = when {
            fromUs -> conversation.assignee?.avatarUrl ?: botAvatar
            // The panel's bot picture, as in the conversation.
            message.sender.type == SenderType.BOT -> config?.bot?.avatarUrl ?: message.sender.avatarUrl ?: botAvatar
            else -> message.sender.avatarUrl
        }
        val preview = plainText(message)
        val ago = time.ago(message.createdAt, now)
        val unread = conversation.unreadCount > 0
        return ConversationRow(
            id = conversation.id,
            avatarUrl = otherAvatar,
            initial = otherName.firstOrNull()?.toString()?.uppercase(Locale.ROOT).orEmpty(),
            preview = preview,
            detail = "$name · $ago",
            unread = unread,
            accessibilityLabel = "$name, $ago: $preview" + if (unread) ". ${strings[Key.UNREAD]}" else "",
        )
    }

    private fun header(snapshot: MessengerSnapshot): HomeScreen.Header {
        val config = snapshot.config
        val brand = config?.brand?.name.orEmpty()
        return HomeScreen.Header(
            brandName = brand,
            logoUrl = config?.brand?.logoUrl,
            logoDarkUrl = config?.brand?.logoDarkUrl,
            // A picture style without its picture is the gradient.
            style = config?.brand?.headerStyle
                ?.takeUnless { it == MessengerConfig.HeaderStyle.IMAGE && config.brand.headerImageUrl == null }
                ?: MessengerConfig.HeaderStyle.GRADIENT,
            imageUrl = config?.brand?.headerImageUrl,
            glow = config?.brand?.glow ?: false,
            brandInitial = brand.firstOrNull()?.toString()?.uppercase(Locale.ROOT).orEmpty(),
            teamAvatars = if (config?.team?.show == false) emptyList() else config?.team?.avatars.orEmpty().take(3),
            greeting = strings.greeting(snapshot.userName),
            title = strings[Key.GREETING_LINE2],
            closeLabel = strings[Key.CLOSE],
        )
    }

    private fun newConversation(config: MessengerConfig?): HomeScreen.NewConversationCard {
        val title = strings[Key.SEND_CARD_TITLE]
        val team = config?.team
        // After hours the panel's own line ("Hazırda iş saatı deyil, sizə səhər cavab verəcəyik").
        val subtitle = if (team?.officeHours?.openNow == false) team.replyTimeOffline ?: team.replyTime else team?.replyTime
        return HomeScreen.NewConversationCard(title, subtitle, if (subtitle != null) "$title. $subtitle" else title)
    }

    private fun tabs(snapshot: MessengerSnapshot): HomeScreen.Tabs {
        val unread = snapshot.unreadTotal > 0 || snapshot.conversations.any { it.unreadCount > 0 }
        val messages = strings[Key.TAB_MESSAGES]
        return HomeScreen.Tabs(
            home = strings[Key.TAB_HOME],
            messages = messages,
            messagesUnread = unread,
            messagesAccessibilityLabel = if (unread) "$messages, ${strings[Key.UNREAD_MESSAGES]}" else messages,
        )
    }

    private val failure get() = HomeScreen.Failure(strings[Key.ERROR], strings[Key.RETRY])

    companion object {
        /** Not translated: the product's name. */
        const val POWERED_BY = "Powered by Clomni"

        /** The bot's picture; the brand's logo when the panel set none (the initial when there is no logo either). */
        fun botAvatar(config: MessengerConfig?): String? = config?.bot?.avatarUrl ?: config?.brand?.logoUrl

        private val LINK = Regex("\\[([^\\]]*)\\]\\([^)]*\\)")

        // `\w` spelled out: Java's is ASCII-only, Android's (ICU) is not.
        private val ITALIC = Regex("(^|[^\\p{L}\\p{N}_*])\\*([^*\\n]+)\\*")

        /** One line of a message: its text without the markdown marks, or the fallback text of other types. */
        fun plainText(message: Message): String {
            val content = message.content as? MessageContent.Text ?: return oneLine(message.fallbackText)
            val text = content.text
                .replace(LINK, "$1")
                .replace("**", "")
                .replace(ITALIC, "$1$2")
            return oneLine(text)
        }

        private fun oneLine(text: String) = text.lines().map { it.trim() }.filter { it.isNotEmpty() }.joinToString(" ")
    }
}
