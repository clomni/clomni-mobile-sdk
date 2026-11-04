package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.ClomniStrings.Key
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.FaqItem
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.NewsItem
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import java.util.Locale
import java.util.TimeZone

/** Everything the Home tab shows, decided here so the Compose view only draws it (brief 8·7.3, 7.5). */
internal data class HomeScreen(
    val phase: Phase,
    val loadingLabel: String = "",
    val header: Header,
    /** Null hides a card. */
    val newConversation: NewConversationCard?,
    val recent: RecentCard?,
    val channels: ChannelsCard?,
    /** The cards in the panel's order; one without its card above (no channels, nothing recent) is left out. */
    val order: List<MessengerConfig.HomeCard>,
    val messagesCard: MessagesCard,
    /** As many as the panel's news_on_home (1–3, 2 by default); none: no news card. */
    val news: List<NewsCard> = emptyList(),
    /** "Hamısı" under the news: the news list (the News tab when there is a tab bar); null when Home shows them all. */
    val newsSeeAll: String? = null,
    /** The first questions (FAQ) and "Hamısı"; null without questions or with the FAQ off. */
    val faq: FaqCard? = null,
    /** The tabs under the list screens; null without the panel's tab_bar (SDK 1.0.7). */
    val tabBar: TabBar? = null,
    /** "Powered by", before the Clomni wordmark under the cards (H3); null where the plan turns it off. */
    val poweredBy: String?,
    /** The capsule over the screen while offline (CM-077). */
    val offline: String?,
    /** "Qoşuldu": the capsule's word for a second once the connection is back. */
    val connected: String,
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
        /** The written logo in place of the logo and the name; null shows those. */
        val wordmarkUrl: String? = null,
        /** For dark mode; [wordmarkUrl] when null. */
        val wordmarkDarkUrl: String? = null,
        val style: MessengerConfig.HeaderStyle,
        /** The photo of [MessengerConfig.HeaderStyle.IMAGE], under a dark veil. */
        val imageUrl: String?,
        /** A soft glow of the brand colour behind the header. */
        val glow: Boolean,
        /** Stands in the logo square while there is no logo. */
        val brandInitial: String,
        /** Up to three, overlapping. */
        val teamAvatars: List<String>,
        /** "Salam, Aysel", smaller than [title] and in the same colour. */
        val greeting: String,
        /** "Necə kömək edə bilərik?" */
        val title: String,
        /** Both lines' size, sp: 28 × the panel's title_scale. */
        val titleSize: Float = 28f,
        /** The logo's (and the written logo's) height, dp: 32 × the panel's logo_scale. */
        val logoSize: Float = 32f,
        val closeLabel: String,
    )

    /** "Bizə mesaj göndərin" with the reply time under it. */
    data class NewConversationCard(val title: String, val subtitle: String?, val accessibilityLabel: String)

    data class RecentCard(val label: String, val row: ConversationRow)

    /** One news item on Home: its picture, title and short text; a tap opens it. */
    data class NewsCard(val id: String, val title: String, val summary: String?, val imageUrl: String?, val accessibilityLabel: String)

    /** "Mesajlar": the list of conversations, with a red dot while something is unread. */
    data class MessagesCard(val title: String, val unread: Boolean, val accessibilityLabel: String)

    /**
     * "Tez-tez verilən suallar": the first [HomePresenter.FAQ_ON_HOME] questions, each opening its answer, and "Hamısı"
     * when there are more (null otherwise).
     */
    data class FaqCard(val title: String, val questions: List<FaqRow>, val seeAll: String?)

    data class ChannelsCard(val label: String, val items: List<ChannelItem>)

    data class Failure(val message: String, val retry: String)
}

/** One question in a list: a tap opens its answer. */
internal data class FaqRow(val id: String, val question: String)

/** The four tabs, in their order (contract 1.0.7 §3), with the screen each one is. */
internal enum class MessengerTab(val route: MessengerRoute) {
    HOME(MessengerRoute.Home),
    MESSAGES(MessengerRoute.Messages),
    NEWS(MessengerRoute.NewsList),
    FAQ(MessengerRoute.Faq),
    ;

    companion object {
        /** The tab [route] is, or null for a screen under one (a conversation, a news item, an answer). */
        fun of(route: MessengerRoute?): MessengerTab? = entries.firstOrNull { it.route == route }
    }
}

/**
 * The tab bar under Home, the conversations, the news and the questions (config home.tab_bar): Home and the
 * conversations always, the news while there is any, the questions while the FAQ is on and has some. A conversation,
 * a news item or an answer opens over it, without it.
 */
internal data class TabBar(val tabs: List<Tab>) {
    data class Tab(
        val kind: MessengerTab,
        val title: String,
        /** The conversations' unread count: "3", "99+"; null when nothing is unread. */
        val badge: String? = null,
        val accessibilityLabel: String = title,
    )

    operator fun contains(kind: MessengerTab): Boolean = tabs.any { it.kind == kind }
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
    /** "Leyla", and "2 dəq": Home's "Son mesaj" card shows them on one line over the message. */
    val name: String = "",
    val time: String = "",
    val unread: Boolean,
    val accessibilityLabel: String,
)

/** The Messages tab. */
internal data class MessagesScreen(
    val title: String,
    /** "Geri": the bar's arrow back to Home. */
    val backLabel: String = "",
    val phase: HomeScreen.Phase,
    val loadingLabel: String = "",
    val rows: List<ConversationRow>,
    /** "Hələ söhbət yoxdur", when the list is loaded and empty. */
    val empty: String?,
    val newConversation: HomeScreen.NewConversationCard,
    val offline: String?,
    val connected: String,
    val failure: HomeScreen.Failure?,
)

/** All the news, from Home's "Hamısı" or the News tab. */
internal data class NewsListScreen(
    val title: String,
    val items: List<HomeScreen.NewsCard>,
    val backLabel: String,
    val closeLabel: String,
)

/** The questions (FAQ), filtered by what is typed in the search field. */
internal data class FaqScreen(
    val title: String,
    /** "Sual axtarın": the search field's placeholder and name. */
    val search: String,
    val rows: List<FaqRow>,
    /** "Hələ sual yoxdur": nothing published; "Heç nə tapılmadı": nothing matches the search. */
    val empty: String?,
    val backLabel: String,
    val closeLabel: String,
)

/** A news item's own screen: its picture, title, date, text and button. An answer (FAQ) is drawn as one too. */
internal data class NewsScreen(
    val id: String,
    val title: String,
    /** "Bu gün 09:00", "2 oktyabr 09:00". */
    val date: String?,
    val imageUrl: String?,
    /** The text by paragraph; a list item ("- ") is its own block with a bullet. */
    val blocks: List<Block>,
    val button: NewsItem.Button?,
    val backLabel: String,
    val closeLabel: String,
) {
    data class Block(val runs: List<TextRun>, val bullet: Boolean)
}

/** What the screens are built from. */
internal data class MessengerSnapshot(
    val config: MessengerConfig? = null,
    val configLoad: Load = Load.LOADING,
    /** Newest first. */
    val conversations: List<Conversation> = emptyList(),
    val conversationsLoad: Load = Load.LOADING,
    val unreadTotal: Int = 0,
    /** The published news, in the panel's order. */
    val news: List<NewsItem> = emptyList(),
    /** The published questions (FAQ), in the panel's order. */
    val faq: List<FaqItem> = emptyList(),
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
        val onHome = config?.home?.newsOnHome ?: MessengerConfig.DEFAULT_NEWS_ON_HOME
        val faq = faqCard(snapshot)
        return HomeScreen(
            loadingLabel = strings[Key.LOADING],
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
                    MessengerConfig.HomeCard.MESSAGES, MessengerConfig.HomeCard.SEND -> true
                    MessengerConfig.HomeCard.NEWS -> snapshot.news.isNotEmpty()
                    MessengerConfig.HomeCard.RECENT -> recent != null
                    MessengerConfig.HomeCard.CHANNELS -> channels.isNotEmpty()
                    MessengerConfig.HomeCard.FAQ -> faq != null
                }
            },
            messagesCard = messagesCard(snapshot),
            news = snapshot.news.take(onHome).map(::newsCard),
            // Coordinator, 2026-11-04: the link only when there are more news than Home shows.
            newsSeeAll = strings[Key.SEE_ALL].takeIf { snapshot.news.size > onHome },
            faq = faq,
            tabBar = tabBar(snapshot),
            poweredBy = if (config?.poweredBy == false) null else POWERED_BY,
            offline = if (snapshot.isOffline) strings[Key.OFFLINE] else null,
            connected = strings[Key.CONNECTED],
            failure = if (failed) failure else null,
        )
    }

    /** The item's screen; null when it is no longer published. */
    fun news(snapshot: MessengerSnapshot, id: String): NewsScreen? {
        val item = snapshot.news.firstOrNull { it.id == id } ?: return null
        return NewsScreen(
            id = item.id,
            title = item.title,
            date = item.publishedAt?.let { time.day(it, now) },
            imageUrl = item.imageUrl,
            blocks = blocks(item.bodyMarkdown.orEmpty()),
            button = item.button,
            backLabel = strings[Key.GO_BACK],
            closeLabel = strings[Key.CLOSE],
        )
    }

    /** All the news, as Home's cards draw them. */
    fun newsList(snapshot: MessengerSnapshot) = NewsListScreen(
        title = strings[Key.NEWS_TITLE],
        items = snapshot.news.map(::newsCard),
        backLabel = strings[Key.GO_BACK],
        closeLabel = strings[Key.CLOSE],
    )

    /**
     * The questions whose question or answer has [query] in it (all of them for a blank one). "Hələ sual yoxdur" when
     * nothing is published, "Heç nə tapılmadı" when the search finds nothing.
     */
    fun faq(snapshot: MessengerSnapshot, query: String = ""): FaqScreen {
        val rows = snapshot.faq.filter { matches(it, query) }.map { FaqRow(it.id, it.question) }
        return FaqScreen(
            title = strings[Key.FAQ_TITLE],
            search = strings[Key.FAQ_SEARCH],
            rows = rows,
            empty = when {
                snapshot.faq.isEmpty() -> strings[Key.FAQ_EMPTY]
                rows.isEmpty() -> strings[Key.FAQ_NO_RESULTS]
                else -> null
            },
            backLabel = strings[Key.GO_BACK],
            closeLabel = strings[Key.CLOSE],
        )
    }

    /** A question with its answer, drawn as a news item is (the same text format); null when it is withdrawn. */
    fun faqItem(snapshot: MessengerSnapshot, id: String): NewsScreen? {
        val item = snapshot.faq.firstOrNull { it.id == id } ?: return null
        return NewsScreen(
            id = item.id,
            title = item.question,
            date = null,
            imageUrl = null,
            blocks = blocks(item.answer),
            button = null,
            backLabel = strings[Key.GO_BACK],
            closeLabel = strings[Key.CLOSE],
        )
    }

    /** A news item's text or an answer by paragraph; a paragraph of "- " lines is a list. */
    private fun blocks(markdown: String): List<NewsScreen.Block> =
        markdown.split(Regex("\\n\\s*\\n")).flatMap { paragraph ->
            val lines = paragraph.trim().lines()
            if (lines.isNotEmpty() && lines.all { it.trimStart().startsWith("- ") || it.trimStart().startsWith("* ") }) {
                lines.map { NewsScreen.Block(LimitedMarkdown.parse(it.trimStart().drop(2)), bullet = true) }
            } else {
                listOf(NewsScreen.Block(LimitedMarkdown.parse(paragraph.trim()), bullet = false))
            }
        }.filter { block -> block.runs.any { it.text.isNotBlank() } }

    private fun newsCard(item: NewsItem) =
        HomeScreen.NewsCard(item.id, item.title, item.summary, item.imageUrl, listOfNotNull(item.title, item.summary).joinToString(". "))

    /** Shown only while the FAQ is on, with questions, and the panel put its card on Home. */
    private fun faqCard(snapshot: MessengerSnapshot): HomeScreen.FaqCard? {
        if (snapshot.config?.faqEnabled != true || snapshot.faq.isEmpty()) return null
        val questions = snapshot.faq.take(FAQ_ON_HOME).map { FaqRow(it.id, it.question) }
        return HomeScreen.FaqCard(strings[Key.FAQ_TITLE], questions, strings[Key.SEE_ALL].takeIf { snapshot.faq.size > FAQ_ON_HOME })
    }

    /** Contract 1.0.7 §3: the panel's tab_bar, and only the tabs that have something to show. */
    fun tabBar(snapshot: MessengerSnapshot): TabBar? {
        val config = snapshot.config ?: return null
        if (!config.home.tabBar) return null
        val unread = snapshot.unreadTotal.takeIf { it > 0 } ?: snapshot.conversations.sumOf { it.unreadCount }
        val messages = strings[Key.TAB_MESSAGES]
        val tabs = listOfNotNull(
            TabBar.Tab(MessengerTab.HOME, strings[Key.TAB_HOME]),
            TabBar.Tab(
                MessengerTab.MESSAGES,
                messages,
                badge = when {
                    unread > 99 -> "99+"
                    unread > 0 -> unread.toString()
                    else -> null
                },
                // "Söhbətlər, 42 oxunmamış": the number itself, in the texts there are (contract 1.0.7b §2).
                accessibilityLabel = if (unread > 0) "$messages, $unread ${strings[Key.UNREAD].lowercase(Locale.ROOT)}" else messages,
            ),
            TabBar.Tab(MessengerTab.NEWS, strings[Key.TAB_NEWS]).takeIf { snapshot.news.isNotEmpty() },
            TabBar.Tab(MessengerTab.FAQ, strings[Key.TAB_FAQ]).takeIf { config.faqEnabled && snapshot.faq.isNotEmpty() },
        )
        return TabBar(tabs)
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
            title = strings[Key.MESSAGES_TITLE],
            backLabel = strings[Key.GO_BACK],
            phase = phase,
            loadingLabel = strings[Key.LOADING],
            rows = rows,
            empty = if (phase == HomeScreen.Phase.READY && rows.isEmpty()) strings[Key.EMPTY_LIST] else null,
            newConversation = newConversation(snapshot.config),
            offline = if (snapshot.isOffline) strings[Key.OFFLINE] else null,
            connected = strings[Key.CONNECTED],
            failure = if (failed) failure else null,
        )
    }

    /**
     * A conversation with a last message; one without has nothing to show yet. Next to the user's own message ("Siz")
     * the conversation's own face, the company's, as a chat list shows it; never the operator's (test report), the same
     * as iOS. A bot is named and pictured as in the conversation ([botName], [botAvatar]).
     */
    fun row(conversation: Conversation, config: MessengerConfig?): ConversationRow? {
        val message = conversation.lastMessage ?: return null
        val brand = config?.brand?.name.orEmpty()
        val name = when (message.sender.type) {
            SenderType.USER -> strings[Key.YOU]
            SenderType.BOT -> botName(message.sender, config)
            SenderType.OPERATOR -> message.sender.name ?: conversation.assignee?.name ?: brand
            SenderType.SYSTEM, SenderType.UNKNOWN -> brand
        }
        val fromUser = message.sender.type == SenderType.USER
        val system = message.sender.type == SenderType.SYSTEM
        // A system line ("Leyla söhbətə qoşuldu") shows who answers: the assignee, else the bot.
        val faceName = when {
            fromUser -> brand.ifEmpty { config?.bot?.name.orEmpty() }
            system -> conversation.assignee?.name ?: botName(null, config)
            else -> name
        }
        val face = when {
            // The company: its logo, else the panel's bot picture, else its initial.
            fromUser -> config?.brand?.logoUrl ?: config?.bot?.avatarUrl
            system -> conversation.assignee?.avatarUrl ?: botAvatar(config)
            message.sender.type == SenderType.BOT -> botAvatar(config, message.sender)
            else -> message.sender.avatarUrl
        }
        val preview = if (message.content is MessageContent.Deleted) strings[Key.MESSAGE_DELETED] else plainText(message)
        val ago = time.ago(message.createdAt, now)
        val unread = conversation.unreadCount > 0
        return ConversationRow(
            id = conversation.id,
            avatarUrl = face,
            initial = faceName.firstOrNull()?.toString()?.uppercase(Locale.ROOT).orEmpty(),
            preview = preview,
            detail = "$name · $ago",
            name = name,
            time = ago,
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
            wordmarkUrl = config?.brand?.wordmarkUrl,
            wordmarkDarkUrl = config?.brand?.wordmarkDarkUrl,
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
            titleSize = 28f * (config?.home?.titleScale ?: 100) / 100f,
            logoSize = 32f * (config?.brand?.logoScale ?: 100) / 100f,
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

    private fun messagesCard(snapshot: MessengerSnapshot): HomeScreen.MessagesCard {
        val unread = snapshot.unreadTotal > 0 || snapshot.conversations.any { it.unreadCount > 0 }
        val title = strings[Key.MESSAGES_TITLE]
        return HomeScreen.MessagesCard(title, unread, if (unread) "$title, ${strings[Key.UNREAD_MESSAGES]}" else title)
    }

    private val failure get() = HomeScreen.Failure(strings[Key.ERROR], strings[Key.RETRY])

    companion object {
        /** Not translated: the product's name. */
        const val POWERED_BY = "Powered by"

        /** Questions on Home's FAQ card (contract 1.0.7 §3). */
        const val FAQ_ON_HOME = 3

        /**
         * The FAQ's search, on this device: [query]'s words each somewhere in the question or the answer's text, case
         * and the dotted and dotless i aside (İ, I, ı and i are one letter here: people type either).
         */
        fun matches(item: FaqItem, query: String): Boolean {
            val words = searchable(query).split(Regex("\\s+")).filter { it.isNotEmpty() }
            if (words.isEmpty()) return true
            val text = searchable(item.question + " " + LimitedMarkdown.plainText(item.answer))
            return words.all { it in text }
        }

        private fun searchable(text: String): String =
            text.lowercase(Locale.ROOT).replace("\u0307", "").replace('ı', 'i')

        /**
         * A bot's name, the same on every screen (contract 1.0.7b §1): what the server sent as the message's sender,
         * else the panel's bot name, else the brand's. The server decides which; the inbox's name is never one.
         */
        fun botName(sender: Sender?, config: MessengerConfig?): String =
            sender?.name?.takeIf { it.isNotBlank() } ?: config?.bot?.name?.takeIf { it.isNotBlank() } ?: config?.brand?.name.orEmpty()

        /**
         * Contract 1.0.7b §5.4: with the panel's single conversation on, a new conversation is the one the server
         * names ([resume], `resume_conversation_id`: the one POST /conversations would answer with), opened with its
         * history; null (the switch off, or none named): a new one. The server, not the SDK, knows which still count
         * (a bot conversation idle for 30 minutes or one its flow ended does not, CM-291).
         */
        fun openConversation(config: MessengerConfig?, resume: String?): String? = resume?.takeIf { config?.singleConversation == true }

        /** A bot's picture: the sender's, else the panel's bot picture, else the brand's logo (the initial without one). */
        fun botAvatar(config: MessengerConfig?, sender: Sender? = null): String? =
            sender?.avatarUrl?.takeIf { it.isNotBlank() } ?: config?.bot?.avatarUrl ?: config?.brand?.logoUrl

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

/**
 * What the offline capsule says (CM-077), the same on every screen: nothing, "İnternet yoxdur", or "Qoşuldu" for
 * [BACK_MS] once the connection is back.
 */
internal enum class OfflineNotice {
    HIDDEN,
    OFFLINE,
    BACK;

    /** Where it goes when the network becomes [offline]: only coming back from offline says "Qoşuldu". */
    fun next(offline: Boolean): OfflineNotice = when {
        offline -> OFFLINE
        this == OFFLINE -> BACK
        else -> this
    }

    /** "Qoşuldu" has had its second. */
    fun expired(): OfflineNotice = if (this == BACK) HIDDEN else this

    companion object {
        const val BACK_MS = 1_000L
    }
}
