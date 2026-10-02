package ai.clomni.messenger.protocol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

/** The repo's `protocol/` directory, passed in by Gradle (`clomni.protocol.dir`). */
internal object ProtocolFiles {
    /** The folders with an `index.json`, as the server's validator reads them. */
    val folders = listOf("fixtures", "examples/brief")

    val root: File = File(
        System.getProperty("clomni.protocol.dir") ?: error("clomni.protocol.dir is not set: run the tests through Gradle"),
    )

    data class Entry(val path: String, val schema: String, val valid: Boolean) {
        override fun toString(): String = path
    }

    fun read(path: String): String = File(root, path).readText()

    fun json(path: String): JsonElement = Json.parseToJsonElement(read(path))

    fun index(folder: String): List<Entry> = json("$folder/index.json").jsonArray.map {
        val entry = it.jsonObject
        Entry(
            path = "$folder/${entry.getValue("file").jsonPrimitive.content}",
            schema = entry.getValue("schema").jsonPrimitive.content,
            valid = entry["valid"]?.jsonPrimitive?.booleanOrNull ?: true,
        )
    }

    fun entries(): List<Entry> = folders.flatMap(::index)
}

/** A [ProtocolJson] whose debug log is kept for assertions. */
internal class RecordingProtocol {
    val warnings = mutableListOf<String>()
    val json = ProtocolJson { warnings += it }
}
