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
import java.io.File

/**
 * A conversation the user is writing in that the server does not have yet (brief: no empty conversations): its id
 * stands in for the real one until the first message goes, which creates it.
 */
internal object Drafts {
    private const val PREFIX = "draft_"

    fun new(): String = PREFIX + java.util.UUID.randomUUID()

    fun isDraft(conversationId: String): Boolean = conversationId.startsWith(PREFIX)
}

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
    /** A file the user attached: kept on this device until the server has the message. */
    val upload: PendingUpload? = null,
    /** Where in the app the messenger was opened, for the conversation a draft's first message creates. */
    val openedFrom: String? = null,
) {
    val id: String get() = message.clientId

    enum class State {
        SENDING,

        /** Three attempts failed, or the server refused it: "Göndərilmədi · Yenidən cəhd et". */
        FAILED,
    }
}

/** An attached file on its way: uploaded first (POST /uploads), then sent as an `attachment` message. */
internal data class PendingUpload(
    val fileName: String,
    val mime: String,
    /** Bytes. */
    val size: Long,
    /** The file's name in the outbox's directory. */
    val storedAs: String,
    /** Set once the upload succeeded; a retry, or the next run, then only sends the message. */
    val uploadId: String? = null,
)

/**
 * Every message the user sends is written here before the first attempt and stays until the server confirms it, so
 * neither a lost connection nor a killed process loses it. A retry repeats its `client_id`, which the server handles
 * only once. After [MAX_ATTEMPTS] failed attempts a message is [PendingMessage.State.FAILED] until [retry].
 */
internal class Outbox(
    private val file: JsonFile?,
    private val protocol: ProtocolJson,
    /** Where attached files wait for their upload; null keeps none (a store without a directory). */
    private val filesDir: File? = null,
) {
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

    /** Confirmed by the server, or given up on; its staged file goes with it. */
    @Synchronized
    fun remove(clientId: String): PendingMessage? {
        val index = entries.indexOfFirst { it.id == clientId }
        if (index < 0) return null
        return entries.removeAt(index).also { removed ->
            save()
            removed.upload?.let { stagedFile(it)?.delete() }
        }
    }

    /** The draft [from] became conversation [to] on the server: its messages go there (and survive a restart so). */
    @Synchronized
    fun moveConversation(from: String, to: String) {
        if (entries.none { it.conversationId == from }) return
        entries.replaceAll { if (it.conversationId == from) it.copy(conversationId = to) else it }
        save()
    }

    /** Keeps an attachment's bytes until it is sent; the name it is stored under, or null when it could not be. */
    fun stage(clientId: String, data: ByteArray): String? {
        val dir = filesDir ?: return null
        val name = "upload-$clientId"
        return try {
            dir.mkdirs()
            val temp = File(dir, "$name.tmp")
            temp.writeBytes(data)
            val target = File(dir, name)
            if (!temp.renameTo(target)) {
                target.delete()
                temp.renameTo(target)
            }
            name.takeIf { target.isFile && target.length() == data.size.toLong() }
        } catch (e: java.io.IOException) {
            null
        }
    }

    /** Where a pending attachment's bytes are. */
    fun stagedFile(upload: PendingUpload): File? = filesDir?.let { File(it, upload.storedAs) }

    /** The file is on the server: the message now carries its id, kept on disk so a restart does not upload again. */
    @Synchronized
    fun uploaded(clientId: String, uploadId: String): PendingMessage? = update(clientId) { entry ->
        val attachment = entry.message as? ClientMessage.Attachment ?: return@update entry
        entry.copy(message = attachment.copy(uploadId = uploadId), upload = entry.upload?.copy(uploadId = uploadId))
    }

    /** Failed for a reason of this device (its staged file is gone): no attempt can help. */
    @Synchronized
    fun fail(clientId: String, code: String): PendingMessage? =
        update(clientId) { it.copy(state = PendingMessage.State.FAILED, errorCode = code) }

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
        val saved = file?.read() as? JsonObject
        (saved?.get("entries") as? JsonArray).orEmpty().mapNotNullTo(entries) { decode(it as? JsonObject) }
        // A file staged by a run that ended before its message was written down belongs to nothing.
        val kept = entries.mapNotNullTo(HashSet()) { it.upload?.storedAs }
        filesDir?.listFiles()?.filter { it.name !in kept }?.forEach { it.delete() }
    }

    @Synchronized
    fun clear() {
        entries.clear()
        file?.delete()
        filesDir?.deleteRecursively()
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
        put("opened_from", entry.openedFrom)
        put("fields", JsonObject(entry.fields.mapValues { JsonPrimitive(it.value) }))
        entry.upload?.let { upload ->
            put(
                "upload",
                buildJsonObject {
                    put("file_name", upload.fileName)
                    put("mime", upload.mime)
                    put("size", upload.size)
                    put("stored_as", upload.storedAs)
                    put("upload_id", upload.uploadId)
                },
            )
        }
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
            openedFrom = o.text("opened_from"),
            fields = (o["fields"] as? JsonObject).orEmpty().mapNotNull { (key, value) ->
                (value as? JsonPrimitive)?.takeIf { it.isString }?.let { key to it.content }
            }.toMap(),
            upload = (o["upload"] as? JsonObject)?.let { u ->
                PendingUpload(
                    fileName = u.text("file_name") ?: return null,
                    mime = u.text("mime") ?: return null,
                    size = (u["size"] as? JsonPrimitive)?.longOrNull ?: 0,
                    storedAs = u.text("stored_as") ?: return null,
                    uploadId = u.text("upload_id"),
                )
            },
        )
    }

    private fun JsonObject.text(key: String): String? =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull

    internal companion object {
        const val MAX_ATTEMPTS = 3
    }
}
