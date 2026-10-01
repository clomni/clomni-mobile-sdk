package ai.clomni.messenger.store

import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.ServerError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** A message on its way to the server, shown as the user's bubble until the server's copy replaces it. */
internal data class PendingMessage(
    val conversationId: String,
    val message: ClientMessage,
    /** What the bubble shows: the text, the button's title, the caption. Null for the back button and a form. */
    val preview: String?,
    val createdAt: Long,
    val state: State = State.SENDING,
    val attempts: Int = 0,
    /** The server's reason when it refused the message, e.g. `validation_failed` with [fields]. */
    val errorCode: String? = null,
    val fields: Map<String, String> = emptyMap(),
) {
    val id: String get() = message.clientId

    enum class State {
        SENDING,

        /** Three attempts failed, or the server refused it: "Göndərilmədi · Yenidən cəhd et". */
        FAILED,
    }
}

/**
 * Every message the user sends is written here before the first attempt and stays until the server confirms it, so
 * neither a lost connection nor a killed process loses it. A retry repeats its `client_id`, which the server handles
 * only once. After [MAX_ATTEMPTS] failed attempts a message is [PendingMessage.State.FAILED] until [retry].
 */
internal class Outbox(private val file: JsonFile?, private val protocol: ProtocolJson) {
    private val entries = mutableListOf<PendingMessage>()

    @Synchronized
    fun all(): List<PendingMessage> = entries.toList()

    @Synchronized
    fun entries(conversationId: String): List<PendingMessage> = entries.filter { it.conversationId == conversationId }

    @Synchronized
    fun entry(clientId: String): PendingMessage? = entries.firstOrNull { it.id == clientId }

    /** The oldest message waiting to be sent: they leave in the order they were written. */
    @Synchronized
    fun next(): PendingMessage? = entries.firstOrNull { it.state == PendingMessage.State.SENDING }

    @Synchronized
    fun add(entry: PendingMessage) {
        entries.removeAll { it.id == entry.id }
        entries += entry
        save()
    }

    /** Confirmed by the server, or given up on. */
    @Synchronized
    fun remove(clientId: String): PendingMessage? {
        val index = entries.indexOfFirst { it.id == clientId }
        if (index < 0) return null
        return entries.removeAt(index).also { save() }
    }

    /** One attempt got no answer; the third makes the message failed. */
    @Synchronized
    fun recordFailure(clientId: String): PendingMessage? = update(clientId) {
        val attempts = it.attempts + 1
        it.copy(attempts = attempts, state = if (attempts >= MAX_ATTEMPTS) PendingMessage.State.FAILED else it.state)
    }

    /** The server refused the message itself: failed at once, with its reason. */
    @Synchronized
    fun refuse(clientId: String, error: ServerError?): PendingMessage? = update(clientId) {
        it.copy(state = PendingMessage.State.FAILED, errorCode = error?.code, fields = error?.fields.orEmpty())
    }

    /** "Yenidən cəhd et": a failed message goes back to the queue with fresh attempts. */
    @Synchronized
    fun retry(clientId: String): Boolean {
        if (entry(clientId)?.state != PendingMessage.State.FAILED) return false
        update(clientId) {
            it.copy(state = PendingMessage.State.SENDING, attempts = 0, errorCode = null, fields = emptyMap())
        }
        return true
    }

    @Synchronized
    fun load() {
        entries.clear()
        val saved = file?.read() as? JsonObject ?: return
        (saved["entries"] as? JsonArray).orEmpty().mapNotNullTo(entries) { decode(it as? JsonObject) }
    }

    @Synchronized
    fun clear() {
        entries.clear()
        file?.delete()
    }

    private fun update(clientId: String, change: (PendingMessage) -> PendingMessage): PendingMessage? {
        val index = entries.indexOfFirst { it.id == clientId }
        if (index < 0) return null
        entries[index] = change(entries[index])
        save()
        return entries[index]
    }

    private fun save() {
        file?.write(buildJsonObject { put("entries", JsonArray(entries.map(::encode))) })
    }

    private fun encode(entry: PendingMessage) = buildJsonObject {
        put("conversation_id", entry.conversationId)
        put("message", Json.parseToJsonElement(protocol.encode(entry.message)))
        put("preview", entry.preview)
        put("created_at", entry.createdAt)
        put("state", entry.state.name.lowercase())
        put("attempts", entry.attempts)
        put("error_code", entry.errorCode)
        put("fields", JsonObject(entry.fields.mapValues { JsonPrimitive(it.value) }))
    }

    private fun decode(o: JsonObject?): PendingMessage? {
        o ?: return null
        val message = (o["message"] as? JsonObject)?.let { protocol.parseClientMessage(it.toString()) } ?: return null
        return PendingMessage(
            conversationId = o.text("conversation_id") ?: return null,
            message = message,
            preview = o.text("preview"),
            createdAt = (o["created_at"] as? JsonPrimitive)?.longOrNull ?: 0,
            state = if (o.text("state") == "failed") PendingMessage.State.FAILED else PendingMessage.State.SENDING,
            attempts = (o["attempts"] as? JsonPrimitive)?.intOrNull ?: 0,
            errorCode = o.text("error_code"),
            fields = (o["fields"] as? JsonObject).orEmpty().mapNotNull { (key, value) ->
                (value as? JsonPrimitive)?.takeIf { it.isString }?.let { key to it.content }
            }.toMap(),
        )
    }

    private fun JsonObject.text(key: String): String? =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull

    internal companion object {
        const val MAX_ATTEMPTS = 3
    }
}
