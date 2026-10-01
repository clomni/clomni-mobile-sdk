package ai.clomni.messenger.store

import ai.clomni.messenger.core.ClomniChange
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

/**
 * The user's conversations, their messages, the config and the [outbox], in memory and on disk, so the Messenger
 * shows the last known state the moment it opens.
 *
 * - A message is kept once per `id`, whether it came over REST, the socket or both; a newer copy (`message.updated`)
 *   replaces the old one. A message carrying the `client_id` of a pending message confirms it.
 * - Messages are ordered by `seq`. [syncedSeq] is how far a conversation is known without holes; a message beyond it
 *   ([putMessage] answers its value) means a gap the caller fills with `after_seq`.
 * - Mutations are collected and written by [commit], which answers what changed for the screens.
 */
internal class MessageStore(private val dir: File?, private val protocol: ProtocolJson) {
    val outbox = Outbox(dir?.let { JsonFile(File(it, "outbox.json")) }, protocol)
    private val conversationsFile = dir?.let { JsonFile(File(it, "conversations.json")) }
    private val configFile = dir?.let { JsonFile(File(it, "config.json")) }

    private val conversations = LinkedHashMap<String, Conversation>()
    private val messages = HashMap<String, MutableMap<String, Message>>()
    private val synced = HashMap<String, Long>()
    private val operatorRead = HashMap<String, Long>()
    private val answered = LinkedHashSet<String>()
    private var configBody: String? = null
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

    /** Only the latest interactive message of a conversation has live buttons, and only until it is answered. */
    @Synchronized
    fun canAnswer(message: Message): Boolean {
        if (message.flow?.interactive != true || message.id in answered) return false
        val latest = messages(message.conversationId).lastOrNull { it.flow?.interactive == true }
        return latest == null || latest.id == message.id
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

    /** A message from the socket. Answers the `after_seq` to fetch when it leaves a gap (40 → 42), otherwise null. */
    @Synchronized
    fun putMessage(message: Message): Long? {
        insert(message)
        val upTo = advance(message.conversationId) ?: return null
        return if (message.seq > upTo + 1) upTo else null
    }

    /** `conversation.updated`; false for a conversation not known yet. */
    @Synchronized
    fun apply(update: RealtimeEvent.ConversationUpdate): Boolean {
        val known = conversations[update.id] ?: return false
        val unread = update.unreadCount ?: known.unreadCount
        putConversation(known.copy(status = update.status, assignee = update.assignee, unreadCount = unread))
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

    @Synchronized
    fun setConfig(config: MessengerConfig, body: String, etag: String?) {
        this.config = config
        configBody = body
        configEtag = etag
        configDirty = true
        changes += ClomniChange.Config
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
        val cachedConfig = configFile?.read() as? JsonObject
        (cachedConfig?.get("body") as? JsonPrimitive)?.contentOrNull?.let { body ->
            config = protocol.parseConfig(body)
            configBody = body.takeIf { config != null }
            configEtag = (cachedConfig["etag"] as? JsonPrimitive)?.contentOrNull.takeIf { config != null }
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
        unreadTotal = 0
        conversationsDirty = false
        configDirty = false
        messagesDirty.clear()
        outbox.clear()
        dir?.let { File(it, MESSAGES_DIR).deleteRecursively() }
        conversationsFile?.delete()
        configFile?.delete()
        changes += listOf(ClomniChange.Config, ClomniChange.Conversations, ClomniChange.Unread(0))
    }

    private fun insert(message: Message) {
        val conversationId = message.conversationId
        val known = messages.getOrPut(conversationId) { LinkedHashMap() }
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
            configFile?.write(buildJsonObject { put("etag", configEtag); put("body", configBody) })
            configDirty = false
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
