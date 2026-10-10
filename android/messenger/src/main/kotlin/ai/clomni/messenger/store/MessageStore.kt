package ai.clomni.messenger.store

import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.NewsItem
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.RealtimeEvent
import ai.clomni.messenger.protocol.toJson
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.io.File

/**
 * The user's conversations, their messages, the config and the [outbox], in memory and on disk, so the Messenger
 * shows the last known state the moment it opens.
 *
 * - A message is kept once per `id` and once per `seq`, whether it came over REST, the socket or both; a newer copy
 *   (`message.updated`, or another id for the same `seq`) replaces the old one. A message carrying the `client_id` of
 *   a pending message confirms it.
 * - Messages are ordered by `seq`. [syncedSeq] is the highest `seq` received, from REST or the socket: reopening the
 *   conversation asks only for what is newer. A socket message past a hole ([putMessage] answers where the hole
 *   starts) makes the caller fetch that range once with `after_seq`.
 * - Mutations are collected and written by [commit], which answers what changed for the screens.
 */
internal class MessageStore(private val dir: File?, private val protocol: ProtocolJson) {
    val outbox = Outbox(dir?.let { JsonFile(File(it, "outbox.json")) }, protocol, dir?.let { File(it, "uploads") })
    private val conversationsFile = dir?.let { JsonFile(File(it, "conversations.json")) }
    private val configFile = dir?.let { JsonFile(File(it, "config.json")) }
    private val newsFile = dir?.let { JsonFile(File(it, "news.json")) }
    private var newsBody: String? = null
    private var newsDirty = false

    /** The published news, kept like the config (shown at once next time, then checked with its ETag). */
    @get:Synchronized
    var news: List<NewsItem> = emptyList()
        private set

    @get:Synchronized
    var newsEtag: String? = null
        private set

    private val conversations = LinkedHashMap<String, Conversation>()
    private val messages = HashMap<String, MutableMap<String, Message>>()
    private val synced = HashMap<String, Long>()
    private val operatorRead = HashMap<String, Long>()
    private val answered = LinkedHashSet<String>()
    private var configBody: String? = null
    private var configLanguage: String? = null
    private var conversationsDirty = false
    private var configDirty = false
    private val messagesDirty = mutableSetOf<String>()
    private val changes = LinkedHashSet<ClomniChange>()

    @get:Synchronized
    var config: MessengerConfig? = null
        private set

    @get:Synchronized
    var configEtag: String? = null
        private set

    /** Unread messages of the user over all conversations: the badge on the customer's own button. */
    @get:Synchronized
    var unreadTotal: Int = 0
        private set

    // Reads

    /** Most recent activity first. */
    @Synchronized
    fun conversations(): List<Conversation> =
        conversations.values.sortedWith(
            compareByDescending<Conversation> { it.lastMessage?.createdAt ?: it.createdAt }.thenByDescending { it.id },
        )

    @Synchronized
    fun conversation(id: String): Conversation? = conversations[id]

    /** Ordered by `seq`. */
    @Synchronized
    fun messages(conversationId: String): List<Message> =
        messages[conversationId]?.values.orEmpty().sortedWith(compareBy({ it.seq }, { it.id }))

    @Synchronized
    fun message(id: String): Message? = messages.values.firstNotNullOfOrNull { it[id] }

    /** The user's messages not yet confirmed by the server, oldest first; shown after [messages]. */
    fun pending(conversationId: String): List<PendingMessage> = outbox.entries(conversationId)

    /** The conversation is known without holes up to this `seq`; null before its history was ever loaded. */
    @Synchronized
    fun syncedSeq(conversationId: String): Long? = synced[conversationId]

    /** The operator has read the user's messages up to this `seq` ("Oxundu"). */
    @Synchronized
    fun readByOperator(conversationId: String): Long? = operatorRead[conversationId]

    /** Answered on this device (buttons, form, rating), whatever the server's copy says yet. */
    @Synchronized
    fun isAnswered(messageId: String): Boolean = messageId in answered

    /**
     * Only the latest interactive message of a conversation has live buttons, and only until it is answered. Choices
     * (operator, 2026-10-04) also need to be the conversation's last word: a message after them (the user's choice, an
     * operator) answered or ended them, which is all a reloaded history can tell.
     */
    @Synchronized
    fun canAnswer(message: Message): Boolean {
        if (message.flow?.interactive != true || message.id in answered) return false
        val list = messages(message.conversationId)
        val latest = list.lastOrNull { it.flow?.interactive == true }
        if (latest != null && latest.id != message.id) return false
        if (message.content !is MessageContent.QuickReplies) return true
        return list.dropWhile { it.id != message.id }.drop(1).all { it.content is MessageContent.System }
    }

    // Mutations

    @Synchronized
    fun putConversations(list: List<Conversation>) {
        list.forEach(::putConversation)
    }

    @Synchronized
    fun putConversation(conversation: Conversation) {
        val known = conversations[conversation.id]
        // A list fetched before a socket message arrived must not take that message back.
        val last = listOfNotNull(known?.lastMessage, conversation.lastMessage).maxByOrNull { it.seq }
        val merged = conversation.copy(lastMessage = last)
        if (merged == known) return
        conversations[conversation.id] = merged
        conversationsDirty = true
        changes += ClomniChange.Conversations
    }

    /**
     * A page from REST. [syncedThrough] is the `seq` the page proves the conversation complete up to: the latest page,
     * or one fetched `after_seq`. An older page (`before_seq`) passes null.
     */
    @Synchronized
    fun putMessages(conversationId: String, list: List<Message>, syncedThrough: Long?) {
        list.forEach(::insert)
        if (syncedThrough != null) {
            synced[conversationId] = maxOf(synced[conversationId] ?: syncedThrough, syncedThrough)
            advance(conversationId)
            messagesDirty += conversationId
        }
    }

    /**
     * A message from the socket: the mark rises to it. Answers the `after_seq` to fetch when it leaves a gap (40 → 42),
     * otherwise null.
     */
    @Synchronized
    fun putMessage(message: Message): Long? {
        insert(message)
        val conversationId = message.conversationId
        val upTo = advance(conversationId) ?: return null
        if (message.seq <= upTo) return null
        synced[conversationId] = message.seq
        messagesDirty += conversationId
        return upTo
    }

    /** `conversation.updated`; false for a conversation not known yet. */
    @Synchronized
    fun apply(update: RealtimeEvent.ConversationUpdate): Boolean {
        val known = conversations[update.id] ?: return false
        val unread = update.unreadCount ?: known.unreadCount
        putConversation(
            known.copy(status = update.status, assignee = update.assignee, unreadCount = unread, flow = update.flow ?: known.flow),
        )
        return true
    }

    /** The user answered [messageId] (buttons, form, rating): it stays dead while the server's copy is on its way. */
    @Synchronized
    fun markAnswered(messageId: String) {
        if (!answered.add(messageId)) return
        conversationsDirty = true
        message(messageId)?.let { changes += ClomniChange.Messages(it.conversationId) }
    }

    @Synchronized
    fun markReadByOperator(conversationId: String, upToSeq: Long) {
        if ((operatorRead[conversationId] ?: -1) >= upToSeq) return
        operatorRead[conversationId] = upToSeq
        conversationsDirty = true
        changes += ClomniChange.Read(conversationId, upToSeq)
    }

    /** The user has seen the conversation. */
    @Synchronized
    fun markSeen(conversationId: String) {
        val known = conversations[conversationId] ?: return
        if (known.unreadCount != 0) putConversation(known.copy(unreadCount = 0))
    }

    @Synchronized
    fun setUnreadTotal(total: Int) {
        if (total == unreadTotal) return
        unreadTotal = total
        conversationsDirty = true
        changes += ClomniChange.Unread(total)
    }

    /** [language]: the one the config was asked in, kept with it so the next launch knows its texts' language. */
    @Synchronized
    fun setConfig(config: MessengerConfig, body: String, etag: String?, language: String? = null) {
        configRead = true
        this.config = config
        configBody = body
        configEtag = etag
        configLanguage = language
        configDirty = true
        changes += ClomniChange.Config
    }

    @Synchronized
    fun setNews(items: List<NewsItem>, body: String, etag: String?) {
        news = items
        newsBody = body
        newsEtag = etag
        newsDirty = true
        changes += ClomniChange.News
    }

    /** Something outside the store changed for the screens, e.g. the outbox of a conversation. */
    @Synchronized
    fun changed(change: ClomniChange) {
        changes += change
    }

    /** Writes what changed since the last commit and answers it. */
    @Synchronized
    fun commit(): List<ClomniChange> {
        if (dir != null) save()
        return changes.toList().also { changes.clear() }
    }

    // Disk

    /** The config.json [readConfig] read, or the server's since: [cachedConfig] does not read it again. */
    private var configRead = false

    /**
     * The look the previous run kept, read from disk now if [load] has not run yet (a small file): the messenger's
     * first frame is in the brand's colours, never in a default that changes a moment later.
     */
    @Synchronized
    fun cachedConfig(): MessengerConfig? {
        if (!configRead) readConfig()
        return config
    }

    private fun readConfig() {
        configRead = true
        val cachedConfig = configFile?.read() as? JsonObject
        (cachedConfig?.get("body") as? JsonPrimitive)?.contentOrNull?.let { body ->
            configLanguage = (cachedConfig["lang"] as? JsonPrimitive)?.contentOrNull
            config = protocol.parseConfig(body)?.let { parsed -> configLanguage?.let(parsed::answeredIn) ?: parsed }
            configBody = body.takeIf { config != null }
            configEtag = (cachedConfig["etag"] as? JsonPrimitive)?.contentOrNull.takeIf { config != null }
        }
    }

    /** The state the previous run left, shown before the network answers. */
    @Synchronized
    fun load() {
        dir ?: return
        val saved = conversationsFile?.read() as? JsonObject
        (saved?.get("conversations") as? JsonArray).orEmpty().forEach { element ->
            protocol.parseConversation(element.toString())?.let { conversations[it.id] = it }
        }
        unreadTotal = (saved?.get("unread_total") as? JsonPrimitive)?.intOrNull ?: 0
        (saved?.get("read_by_operator") as? JsonObject).orEmpty().forEach { (id, seq) ->
            (seq as? JsonPrimitive)?.longOrNull?.let { operatorRead[id] = it }
        }
        (saved?.get("answered") as? JsonArray).orEmpty().forEach { id ->
            (id as? JsonPrimitive)?.contentOrNull?.let { answered += it }
        }
        File(dir, MESSAGES_DIR).listFiles().orEmpty().forEach { file ->
            val page = JsonFile(file).read() as? JsonObject ?: return@forEach
            val conversationId = (page["conversation_id"] as? JsonPrimitive)?.contentOrNull ?: return@forEach
            (page["messages"] as? JsonArray).orEmpty().forEach messages@{ element ->
                val message = protocol.parseMessage(element) ?: return@messages
                messages.getOrPut(conversationId) { LinkedHashMap() }[message.id] = message
            }
            (page["synced_seq"] as? JsonPrimitive)?.longOrNull?.let { synced[conversationId] = it }
        }
        if (!configRead) readConfig()
        (newsFile?.read() as? JsonObject)?.let { saved ->
            (saved["body"] as? JsonPrimitive)?.contentOrNull?.let { body ->
                protocol.parseNews(body)?.let {
                    news = it
                    newsBody = body
                    newsEtag = (saved["etag"] as? JsonPrimitive)?.contentOrNull
                }
            }
        }
        outbox.load()
        changes += listOf(ClomniChange.Config, ClomniChange.Conversations, ClomniChange.Unread(unreadTotal))
    }

    /** Logout, or another identified user: nothing of the previous one stays, unsent messages included. */
    @Synchronized
    fun clear() {
        conversations.clear()
        messages.clear()
        synced.clear()
        operatorRead.clear()
        answered.clear()
        config = null
        configBody = null
        configEtag = null
        configLanguage = null
        configRead = true
        news = emptyList()
        newsBody = null
        newsEtag = null
        newsDirty = false
        unreadTotal = 0
        conversationsDirty = false
        configDirty = false
        messagesDirty.clear()
        outbox.clear()
        dir?.let { File(it, MESSAGES_DIR).deleteRecursively() }
        conversationsFile?.delete()
        configFile?.delete()
        newsFile?.delete()
        changes += listOf(ClomniChange.Config, ClomniChange.News, ClomniChange.Conversations, ClomniChange.Unread(0))
    }

    private fun insert(message: Message) {
        val conversationId = message.conversationId
        val known = messages.getOrPut(conversationId) { LinkedHashMap() }
        // One message per seq: the same message under another id (a replayed or re-delivered copy) replaces it.
        known.values.filter { it.seq == message.seq && it.id != message.id }.forEach { known.remove(it.id) }
        if (known[message.id] != message) {
            known[message.id] = message
            messagesDirty += conversationId
            changes += ClomniChange.Messages(conversationId)
        }
        // The server's copy of a pending message replaces the optimistic bubble.
        message.clientId?.let { if (outbox.remove(it) != null) changes += ClomniChange.Messages(conversationId) }
        val conversation = conversations[conversationId]
        val last = conversation?.lastMessage
        if (conversation != null && (last == null || message.seq >= last.seq)) {
            putConversation(conversation.copy(lastMessage = message))
        }
    }

    /** Moves the synced mark over messages already held right after it (a gap filled by the socket itself). */
    private fun advance(conversationId: String): Long? {
        var upTo = synced[conversationId] ?: return null
        val seqs = messages[conversationId]?.values?.mapTo(HashSet()) { it.seq }.orEmpty()
        while (upTo + 1 in seqs) upTo++
        synced[conversationId] = upTo
        return upTo
    }

    private fun save() {
        if (conversationsDirty) {
            conversationsFile?.write(
                buildJsonObject {
                    put("conversations", JsonArray(conversations.values.map { it.toJson() }))
                    put("unread_total", unreadTotal)
                    put("read_by_operator", JsonObject(operatorRead.mapValues { JsonPrimitive(it.value) }))
                    put("answered", JsonArray(answered.map(::JsonPrimitive)))
                },
            )
            conversationsDirty = false
        }
        for (conversationId in messagesDirty) {
            val kept = messages(conversationId).takeLast(CACHED_MESSAGES_PER_CONVERSATION)
            messageFile(conversationId).write(
                buildJsonObject {
                    put("conversation_id", conversationId)
                    put("synced_seq", synced[conversationId]?.let(::JsonPrimitive) ?: JsonNull)
                    put("messages", JsonArray(kept.map { it.toJson() }))
                },
            )
        }
        messagesDirty.clear()
        if (configDirty) {
            configFile?.write(buildJsonObject { put("etag", configEtag); put("lang", configLanguage); put("body", configBody) })
            configDirty = false
        }
        if (newsDirty) {
            newsFile?.write(buildJsonObject { put("etag", newsEtag); put("body", newsBody) })
            newsDirty = false
        }
    }

    private fun messageFile(conversationId: String) =
        JsonFile(File(File(dir, MESSAGES_DIR), conversationId.replace(Regex("[^A-Za-z0-9_-]"), "_") + ".json"))

    internal companion object {
        /** Per conversation on disk; older history is loaded again from the server when scrolled to. */
        const val CACHED_MESSAGES_PER_CONVERSATION = 100
        private const val MESSAGES_DIR = "messages"
    }
}
