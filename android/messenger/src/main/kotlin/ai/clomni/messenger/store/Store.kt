package ai.clomni.messenger.store

import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessengerConfig
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
import java.util.concurrent.CopyOnWriteArrayList

/** One row of a conversation on screen: a message from the server, or the user's own one on its way. */
internal sealed interface TimelineItem {
    data class Received(val message: Message) : TimelineItem

    data class Outgoing(val item: OutboxItem) : TimelineItem
}

/**
 * The user's conversations, their messages, the config and the outbox, in memory and on disk, so the Messenger
 * shows the last known state the moment it opens.
 *
 * - A message is kept once per `id`, whether it came over REST, the socket or both; a newer copy (`message.updated`)
 *   replaces the old one. A message carrying the `client_id` of an outbox item confirms it and replaces its bubble.
 * - Messages are ordered by `seq`. [syncedSeq] is how far a conversation is known without holes; a message beyond it
 *   ([putMessage] answers its value) means a gap the caller fills with `after_seq`.
 * - Mutations are collected and written by [commit], which also tells the listeners.
 */
internal class Store(private val dir: File?, private val protocol: ProtocolJson) {
    val outbox = Outbox(dir?.let { JsonFile(File(it, "outbox.json")) }, protocol)
    private val conversationsFile = dir?.let { JsonFile(File(it, "conversations.json")) }
    private val configFile = dir?.let { JsonFile(File(it, "config.json")) }

    private val conversations = LinkedHashMap<String, Conversation>()
    private val messages = HashMap<String, MutableMap<String, Message>>()
    private val synced = HashMap<String, Long>()
    private val operatorRead = HashMap<String, Long>()
    private var configBody: String? = null
    private var conversationsDirty = false
    private var configDirty = false
    private val messagesDirty = mutableSetOf<String>()
    private var changed = false
    private val listeners = CopyOnWriteArrayList<() -> Unit>()

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

    fun addListener(listener: () -> Unit) {
        listeners += listener
    }

    // Reads

    /** Most recent activity first. */
    @Synchronized
    fun conversations(): List<Conversation> =
        conversations.values.sortedByDescending { it.lastMessage?.createdAt ?: it.createdAt }

    @Synchronized
    fun conversation(id: String): Conversation? = conversations[id]

    /** Ordered by `seq`. */
    @Synchronized
    fun messages(conversationId: String): List<Message> =
        messages[conversationId]?.values.orEmpty().sortedWith(compareBy({ it.seq }, { it.id }))

    @Synchronized
    fun message(id: String): Message? = messages.values.firstNotNullOfOrNull { it[id] }

    /** The server's messages by `seq`, then the user's unconfirmed ones in the order they were written. */
    @Synchronized
    fun timeline(conversationId: String): List<TimelineItem> =
        messages(conversationId).map { TimelineItem.Received(it) } +
            outbox.items(conversationId).map { TimelineItem.Outgoing(it) }

    /** The conversation is known without holes up to this `seq`; null before its history was ever loaded. */
    @Synchronized
    fun syncedSeq(conversationId: String): Long? = synced[conversationId]

    /** The operator has read the user's messages up to this `seq` ("Oxundu"). */
    @Synchronized
    fun operatorReadSeq(conversationId: String): Long? = operatorRead[conversationId]

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
        changed = true
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
            changed = true
        }
    }

    /** A message from the socket. Answers the `after_seq` to fetch when it leaves a gap (40 → 42), otherwise null. */
    @Synchronized
    fun putMessage(message: Message): Long? {
        insert(message)
        val conversationId = message.conversationId
        val upTo = advance(conversationId) ?: return null
        return if (message.seq > upTo + 1) upTo else null
    }

    @Synchronized
    fun updateConversation(update: RealtimeEvent.ConversationUpdate): Boolean {
        val known = conversations[update.id] ?: return false
        putConversation(
            known.copy(status = update.status, assignee = update.assignee, unreadCount = update.unreadCount ?: known.unreadCount),
        )
        return true
    }

    /**
     * The buttons of [messageId] stop working: the user answered it, or the server said it is answered or stale (409).
     * Answers the message, so the caller can reload it.
     */
    @Synchronized
    fun disableInteraction(messageId: String): Message? {
        val message = message(messageId) ?: return null
        val flow = message.flow
        if (flow != null && flow.interactive) insert(message.copy(flow = flow.copy(interactive = false)))
        return message
    }

    @Synchronized
    fun setOperatorRead(conversationId: String, upToSeq: Long) {
        if ((operatorRead[conversationId] ?: -1) >= upToSeq) return
        operatorRead[conversationId] = upToSeq
        conversationsDirty = true
        changed = true
    }

    /** The user has seen the conversation. */
    @Synchronized
    fun markRead(conversationId: String) {
        val known = conversations[conversationId] ?: return
        if (known.unreadCount != 0) putConversation(known.copy(unreadCount = 0))
    }

    @Synchronized
    fun setUnreadTotal(total: Int) {
        if (total == unreadTotal) return
        unreadTotal = total
        conversationsDirty = true
        changed = true
    }

    @Synchronized
    fun setConfig(config: MessengerConfig, body: String, etag: String?) {
        this.config = config
        configBody = body
        configEtag = etag
        configDirty = true
        changed = true
    }

    /** Writes what changed since the last commit and tells the listeners. */
    fun commit() {
        val notify = synchronized(this) {
            if (dir != null) save()
            changed.also { changed = false }
        }
        if (notify) listeners.forEach { it() }
    }

    // Disk

    /** The state the previous run left, shown before the network answers. */
    @Synchronized
    fun load() {
        dir ?: return
        val saved = conversationsFile?.read() as? JsonObject
        (saved?.get("conversations") as? JsonArray).orEmpty().forEach { element ->
            protocol.parseConversation(element.toString())?.let { conversations[it.id] = it }
        }
        unreadTotal = (saved?.get("unread_total") as? JsonPrimitive)?.intOrNull ?: 0
        (saved?.get("operator_read") as? JsonObject).orEmpty().forEach { (id, seq) ->
            (seq as? JsonPrimitive)?.longOrNull?.let { operatorRead[id] = it }
        }
        File(dir, MESSAGES_DIR).listFiles().orEmpty().forEach { file ->
            val page = JsonFile(file).read() as? JsonObject ?: return@forEach
            val conversationId = (page["conversation_id"] as? JsonPrimitive)?.contentOrNull ?: return@forEach
            (page["messages"] as? JsonArray).orEmpty().forEach { element ->
                protocol.parseMessage(element)?.let { messages.getOrPut(conversationId) { LinkedHashMap() }[it.id] = it }
            }
            (page["synced_seq"] as? JsonPrimitive)?.longOrNull?.let { synced[conversationId] = it }
        }
        val cachedConfig = configFile?.read() as? JsonObject
        (cachedConfig?.get("body") as? JsonPrimitive)?.contentOrNull?.let { body ->
            config = protocol.parseConfig(body)
            configBody = body.takeIf { config != null }
            configEtag = (cachedConfig["etag"] as? JsonPrimitive)?.contentOrNull.takeIf { config != null }
        }
        outbox.load()
    }

    /** Logout, or another user: nothing of the previous one may stay. [keepOutbox] when the same person continues. */
    fun clear(keepOutbox: Boolean = false) {
        synchronized(this) {
            conversations.clear()
            messages.clear()
            synced.clear()
            operatorRead.clear()
            config = null
            configBody = null
            configEtag = null
            unreadTotal = 0
            conversationsDirty = false
            configDirty = false
            messagesDirty.clear()
            changed = false
            if (!keepOutbox) outbox.clear()
            dir?.let { File(it, MESSAGES_DIR).deleteRecursively() }
            conversationsFile?.delete()
            configFile?.delete()
        }
        listeners.forEach { it() }
    }

    private fun insert(message: Message) {
        val conversationId = message.conversationId
        val known = messages.getOrPut(conversationId) { LinkedHashMap() }
        if (known[message.id] != message) {
            known[message.id] = message
            messagesDirty += conversationId
            changed = true
        }
        message.clientId?.let { if (outbox.remove(it) != null) changed = true }
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
                    put("operator_read", JsonObject(operatorRead.mapValues { JsonPrimitive(it.value) }))
                },
            )
            conversationsDirty = false
        }
        for (conversationId in messagesDirty) {
            val kept = messages(conversationId).takeLast(MAX_CACHED_MESSAGES)
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
            configFile?.write(buildJsonObject { put("etag", configEtag); put("body", configBody) })
            configDirty = false
        }
    }

    private fun messageFile(conversationId: String) =
        JsonFile(File(File(dir, MESSAGES_DIR), conversationId.replace(Regex("[^A-Za-z0-9_-]"), "_") + ".json"))

    internal companion object {
        /** Per conversation on disk; older history is loaded again from the server when scrolled to. */
        const val MAX_CACHED_MESSAGES = 200
        private const val MESSAGES_DIR = "messages"
    }
}
