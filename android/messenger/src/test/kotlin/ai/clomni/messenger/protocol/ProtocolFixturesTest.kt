package ai.clomni.messenger.protocol

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.File
import kotlin.reflect.KClass

/**
 * Every file of `protocol/fixtures` and `protocol/examples/brief`, through the parser its index entry names.
 * A valid file must land on the type below; a `"valid": false` one must not crash the SDK.
 */
@RunWith(Parameterized::class)
class ProtocolFixturesTest(path: String) {
    private val entry = ProtocolFiles.entries().first { it.path == path }

    private val protocol = RecordingProtocol()

    @Test
    fun parsesToTheExpectedType() {
        assertTrue("${entry.path}: no expectation in ProtocolFixturesTest.expected", entry.path in expected)
        val result = parse()
        assertEquals("${entry.path} (${entry.schema})", expected[entry.path], result?.let { it::class })
        if (entry.valid && entry.path !in loggedWhenValid) {
            assertEquals("${entry.path} logged", emptyList<String>(), protocol.warnings)
        }
    }

    private fun parse(): Any? {
        val json = ProtocolFiles.read(entry.path)
        val (schema, pointer) = entry.schema.split('#').let { it[0] to it.getOrNull(1) }
        return when {
            pointer != null -> {
                // A content object on its own, e.g. message.json#/$defs/quick_replies: the def is named after the type.
                assertEquals("message.json", schema)
                protocol.json.parseContent(pointer.removePrefix("/\$defs/"), Json.parseToJsonElement(json))
            }
            schema == "message.json" -> protocol.json.parseMessage(json)?.content
            schema == "event.json" -> protocol.json.parseEvent(json)?.data
            schema == "config.json" -> protocol.json.parseConfig(json)
            schema == "push.json" -> protocol.json.parsePush(json)
            schema == "client-message.json" -> {
                // Built the way the SDK builds it, the message encodes to the fixture, and the fixture reads back to it.
                val built = ClientMessageFixtures.all[entry.path]
                    ?: throw AssertionError("${entry.path}: no ClientMessage in ClientMessageFixtures")
                assertEquals(entry.path, Json.parseToJsonElement(json), Json.parseToJsonElement(protocol.json.encode(built)))
                assertEquals(entry.path, built, protocol.json.parseClientMessage(json))
                built
            }
            else -> throw AssertionError("${entry.path}: unknown schema ${entry.schema}")
        }
    }

    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun entries(): List<String> = ProtocolFiles.entries().map { it.path }

        /** Valid files that are still reported to the debug log: unknown on purpose. */
        val loggedWhenValid = setOf("fixtures/29-unknown-type.json", "fixtures/41-event-unknown.json")

        /** The type each file parses to; null means the SDK drops it. */
        val expected: Map<String, KClass<*>?> = mapOf(
            "fixtures/01-text-bot.json" to MessageContent.Text::class,
            "fixtures/02-text-operator-markdown.json" to MessageContent.Text::class,
            "fixtures/03-text-user.json" to MessageContent.Text::class,
            "fixtures/04-text-long.json" to MessageContent.Text::class,
            "fixtures/05-text-emoji-only.json" to MessageContent.Text::class,
            "fixtures/06-text-unsafe-link.json" to MessageContent.Text::class,
            "fixtures/07-language-select.json" to MessageContent.QuickReplies::class,
            "fixtures/08-language-select-answered.json" to MessageContent.QuickReplies::class,
            "fixtures/09-apar-level1-A.json" to MessageContent.QuickReplies::class,
            "fixtures/10-apar-level2-S-chips.json" to MessageContent.QuickReplies::class,
            "fixtures/11-apar-level3-U.json" to MessageContent.QuickReplies::class,
            "fixtures/12-apar-level4-handoff.json" to MessageContent.QuickReplies::class,
            "fixtures/50-apar-end.json" to MessageContent.Text::class,
            "fixtures/13-button-title-over-80.json" to MessageContent.QuickReplies::class,
            "fixtures/14-ten-buttons.json" to MessageContent.QuickReplies::class,
            "fixtures/15-quick-replies-no-text.json" to MessageContent.QuickReplies::class,
            "fixtures/16-image.json" to MessageContent.Image::class,
            "fixtures/17-image-no-dimensions.json" to MessageContent.Image::class,
            "fixtures/18-file-pdf.json" to MessageContent.File::class,
            "fixtures/19-form-contact.json" to MessageContent.Form::class,
            "fixtures/20-form-all-field-types.json" to MessageContent.Form::class,
            "fixtures/21-form-submitted.json" to MessageContent.Form::class,
            "fixtures/22-system-waiting-in-queue.json" to MessageContent.System::class,
            "fixtures/23-system-operator-joined.json" to MessageContent.System::class,
            "fixtures/24-system-conversation-closed.json" to MessageContent.System::class,
            "fixtures/25-system-unknown-event.json" to MessageContent.System::class,
            "fixtures/26-card.json" to MessageContent.Card::class,
            "fixtures/27-carousel.json" to MessageContent.Card::class,
            "fixtures/28-rating.json" to MessageContent.Rating::class,
            "fixtures/29-unknown-type.json" to MessageContent.Unknown::class,
            "fixtures/30-unknown-fields.json" to MessageContent.Text::class,
            "fixtures/31-operator-no-avatar.json" to MessageContent.Text::class,
            "fixtures/32-other-language-ru.json" to MessageContent.Text::class,
            "fixtures/33-event-ready.json" to RealtimeEvent.Payload.Ready::class,
            "fixtures/34-event-message-created.json" to RealtimeEvent.Payload.MessageCreated::class,
            "fixtures/35-event-message-updated.json" to RealtimeEvent.Payload.MessageUpdated::class,
            "fixtures/36-event-typing.json" to RealtimeEvent.Payload.Typing::class,
            "fixtures/37-event-read.json" to RealtimeEvent.Payload.Read::class,
            "fixtures/38-event-conversation-updated.json" to RealtimeEvent.Payload.ConversationUpdated::class,
            "fixtures/39-event-unread-changed.json" to RealtimeEvent.Payload.UnreadChanged::class,
            "fixtures/40-event-config-changed.json" to RealtimeEvent.Payload.ConfigChanged::class,
            "fixtures/41-event-unknown.json" to RealtimeEvent.Payload.Unknown::class,
            "fixtures/42-config-apar.json" to MessengerConfig::class,
            "fixtures/43-config-minimal.json" to MessengerConfig::class,
            "fixtures/44-push-message.json" to PushPayload::class,
            "fixtures/45-client-text.json" to ClientMessage.Text::class,
            "fixtures/46-client-button-reply.json" to ClientMessage.ButtonReply::class,
            "fixtures/47-client-back.json" to ClientMessage.ButtonReply::class,
            "fixtures/48-client-form-submit.json" to ClientMessage.FormSubmit::class,
            "fixtures/49-client-attachment.json" to ClientMessage.Attachment::class,
            "fixtures/51-client-button-end.json" to ClientMessage.ButtonReply::class,
            "fixtures/52-client-rating.json" to ClientMessage.RatingSubmit::class,
            // "valid": false: none of these may crash; this is what the SDK makes of each (the same as iOS).
            "fixtures/90-invalid-quick-replies-empty.json" to MessageContent.Unknown::class,
            "fixtures/91-invalid-missing-seq.json" to null,
            "fixtures/92-invalid-push-body-too-long.json" to PushPayload::class,
            "fixtures/93-invalid-client-text-empty.json" to ClientMessage.Text::class,
            "fixtures/94-invalid-select-without-options.json" to MessageContent.Unknown::class,
            "fixtures/95-invalid-lang.json" to MessageContent.Text::class,
            "fixtures/96-invalid-config-color.json" to MessengerConfig::class,
            "fixtures/97-invalid-event-ready-without-data.json" to RealtimeEvent.Payload.Unknown::class,
            "fixtures/98-invalid-card-button-both.json" to MessageContent.Card::class,
            "examples/brief/s5-language-select.json" to MessageContent.QuickReplies::class,
            "examples/brief/s5-button-reply.json" to ClientMessage.ButtonReply::class,
            "examples/brief/s5.1-envelope.json" to MessageContent.Text::class,
            "examples/brief/s5.2-text.json" to MessageContent.Text::class,
            "examples/brief/s5.2-quick-replies.json" to MessageContent.QuickReplies::class,
            "examples/brief/s5.2-image.json" to MessageContent.Image::class,
            "examples/brief/s5.2-file.json" to MessageContent.File::class,
            "examples/brief/s5.2-form.json" to MessageContent.Form::class,
            "examples/brief/s5.2-system.json" to MessageContent.System::class,
            "examples/brief/s5.2-card.json" to MessageContent.Card::class,
            "examples/brief/s5.2-rating.json" to MessageContent.Rating::class,
            "examples/brief/s6.3-config.json" to MessengerConfig::class,
            "examples/brief/s6.5-push.json" to PushPayload::class,
        )
    }
}

/** What the server's validator checks too: no file escapes the index, and the index names no missing file. */
class ProtocolIndexTest {

    @Test
    fun everyFileIsListedInItsIndex() {
        for (folder in ProtocolFiles.folders) {
            val listed = ProtocolFiles.index(folder).map { it.path.substringAfterLast('/') }.toSet()
            val onDisk = File(ProtocolFiles.root, folder).list { _, name -> name.endsWith(".json") && name != "index.json" }!!
            assertEquals("$folder: files missing from index.json", emptyList<String>(), onDisk.filter { it !in listed }.sorted())
            assertEquals("$folder: index.json lists missing files", emptyList<String>(), listed.filter { it !in onDisk }.sorted())
        }
    }

    @Test
    fun expectationsMatchTheIndex() {
        val indexed = ProtocolFiles.entries().map { it.path }.toSet()
        assertEquals(
            "expectations for files no index lists",
            emptyList<String>(),
            ProtocolFixturesTest.expected.keys.filter { it !in indexed }.sorted(),
        )
        assertEquals(
            "client messages for files no index lists",
            emptyList<String>(),
            ClientMessageFixtures.all.keys.filter { it !in indexed }.sorted(),
        )
    }
}
