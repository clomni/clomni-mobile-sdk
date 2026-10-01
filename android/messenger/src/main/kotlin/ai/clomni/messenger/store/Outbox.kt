package ai.clomni.messenger.store

import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.ServerError
import kotlinx.serialization.json.Json
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

/** A message the user sent that the server has not confirmed yet. */
internal data class OutboxItem(
    val conversationId: String,
    val message: ClientMessage,
    /** What the user's bubble shows meanwhile: the text, or the title of the button pressed. */
    val preview: String?,
    val createdAt: Long,
    val state: State = State.PENDING,
    val attempts: Int = 0,
    /** Why the server refused it, when it did (e.g. `validation_failed` with the form's field errors). */
    val error: ServerError? = null,
) {
    val clientId: String get() = message.clientId

    enum class State {
        /** Waiting to be sent, or between attempts. */
        PENDING,

        /** "Göndərilmədi · Yenidən cəhd et": sent again only when the user asks ([Outbox.retry]). */
        FAILED,
    }
}

/**
 * Every message the user sends is written here before the first attempt and stays until the server confirms it, so
 * neither a lost connection nor a killed process loses it. A retry repeats its `client_id`, which the server handles
 * only once. After [MAX_ATTEMPTS] failed attempts an item is [OutboxItem.State.FAILED].
 */
internal class Outbox(private val file: JsonFile?, private val protocol: ProtocolJson) {
    private val items = mutableListOf<OutboxItem>()

    @Synchronized
    fun all(): List<OutboxItem> = items.toList()

    @Synchronized
    fun items(conversationId: String): List<OutboxItem> = items.filter { it.conversationId == conversationId }

    @Synchronized
    fun get(clientId: String): OutboxItem? = items.firstOrNull { it.clientId == clientId }

    /** The oldest item waiting to be sent: messages leave in the order they were written. */
    @Synchronized
    fun next(): OutboxItem? = items.firstOrNull { it.state == OutboxItem.State.PENDING }

    @Synchronized
    fun add(item: OutboxItem) {
        items.removeAll { it.clientId == item.clientId }
        items += item
        save()
    }

    /** Confirmed by the server, or given up on: gone from the outbox. */
    @Synchronized
    fun remove(clientId: String): OutboxItem? {
        val index = items.indexOfFirst { it.clientId == clientId }
        if (index < 0) return null
        return items.removeAt(index).also { save() }
    }

    /** One attempt failed. [final] (the server refused the message itself) fails it at once. */
    @Synchronized
    fun recordFailure(clientId: String, error: ServerError? = null, final: Boolean = false): OutboxItem? {
        val index = items.indexOfFirst { it.clientId == clientId }
        if (index < 0) return null
        val item = items[index]
        val attempts = item.attempts + 1
        val failed = final || attempts >= MAX_ATTEMPTS
        items[index] = item.copy(
            attempts = attempts,
            error = error ?: item.error,
            state = if (failed) OutboxItem.State.FAILED else OutboxItem.State.PENDING,
        )
        save()
        return items[index]
    }

    /** "Yenidən cəhd et": a failed item goes back to the queue with fresh attempts. */
    @Synchronized
    fun retry(clientId: String): Boolean {
        val index = items.indexOfFirst { it.clientId == clientId && it.state == OutboxItem.State.FAILED }
        if (index < 0) return false
        items[index] = items[index].copy(state = OutboxItem.State.PENDING, attempts = 0, error = null)
        save()
        return true
    }

    @Synchronized
    fun load() {
        items.clear()
        val saved = file?.read() as? JsonObject ?: return
        (saved["items"] as? JsonArray).orEmpty().mapNotNullTo(items) { decode(it as? JsonObject) }
    }

    @Synchronized
    fun clear() {
        items.clear()
        file?.delete()
    }

    private fun save() {
        file?.write(buildJsonObject { put("items", JsonArray(items.map(::encode))) })
    }

    private fun encode(item: OutboxItem) = buildJsonObject {
        put("conversation_id", item.conversationId)
        put("message", Json.parseToJsonElement(protocol.encode(item.message)))
        put("preview", item.preview)
        put("created_at", item.createdAt)
        put("state", item.state.name.lowercase())
        put("attempts", item.attempts)
        put(
            "error",
            item.error?.let { error ->
                buildJsonObject {
                    put("code", error.code)
                    put("message", error.message)
                    put("request_id", error.requestId)
                    put("fields", JsonObject(error.fields.mapValues { JsonPrimitive(it.value) }))
                }
            } ?: JsonNull,
        )
    }

    private fun decode(o: JsonObject?): OutboxItem? {
        o ?: return null
        val message = (o["message"] as? JsonObject)?.let { protocol.parseClientMessage(it.toString()) } ?: return null
        return OutboxItem(
            conversationId = o.text("conversation_id") ?: return null,
            message = message,
            preview = o.text("preview"),
            createdAt = (o["created_at"] as? JsonPrimitive)?.longOrNull ?: 0,
            state = if (o.text("state") == "failed") OutboxItem.State.FAILED else OutboxItem.State.PENDING,
            attempts = (o["attempts"] as? JsonPrimitive)?.intOrNull ?: 0,
            error = (o["error"] as? JsonObject)?.let { protocol.parseServerError(buildJsonObject { put("error", it) }.toString()) },
        )
    }

    private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull

    internal companion object {
        const val MAX_ATTEMPTS = 3
    }
}
