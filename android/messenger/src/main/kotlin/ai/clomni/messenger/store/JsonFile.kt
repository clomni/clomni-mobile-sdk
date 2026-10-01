package ai.clomni.messenger.store

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import java.io.File

/** One JSON document on disk, replaced whole: written to a temporary file first, so a crash never leaves half of it. */
internal class JsonFile(private val file: File) {

    /** Null when missing or unreadable; an unreadable file is deleted (it is only a cache of the server). */
    fun read(): JsonElement? {
        if (!file.exists()) return null
        return try {
            Json.parseToJsonElement(file.readText())
        } catch (e: Exception) {
            file.delete()
            null
        }
    }

    fun write(element: JsonElement) {
        file.parentFile?.mkdirs()
        val temp = File(file.path + ".tmp")
        temp.writeText(element.toString())
        if (!temp.renameTo(file)) {
            file.delete()
            temp.renameTo(file)
        }
    }

    fun delete() {
        file.delete()
    }
}
