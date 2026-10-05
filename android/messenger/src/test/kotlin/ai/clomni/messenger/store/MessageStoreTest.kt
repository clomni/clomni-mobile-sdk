package ai.clomni.messenger.store

import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.protocol.Assignee
import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.ConversationStatus
import ai.clomni.messenger.protocol.FlowRef
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.RealtimeEvent
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import ai.clomni.messenger.protocol.ServerError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

internal fun message(
    seq: Long,
    id: String = "msg_$seq",
    conversationId: String = "conv_1",
    clientId: String? = null,
    text: String = "m$seq",
    interactive: Boolean? = null,
) = Message(
    id = id,
    clientId = clientId,
    conversationId = conversationId,
    type = "text",
    sender = Sender(if (clientId != null) SenderType.USER else SenderType.BOT),
    createdAt = 1_000_000L + seq * 1_000,
    seq = seq,
    lang = "az",
    flow = interactive?.let { FlowRef("flw_a", "N$seq", 1, it) },
    content = MessageContent.Text(text),
    fallbackText = text,
)

internal fun conversation(id: String = "conv_1", last: Message? = null, createdAt: Long = 0, unread: Int = 0) =
    Conversation(id, ConversationStatus.BOT, null, unread, last, null, null, createdAt)

internal fun pending(clientId: String, conversationId: String = "conv_1", text: String = "t-$clientId") =
    PendingMessage(conversationId, ClientMessage.Text(text, clientId), text, createdAt = clientId.length.toLong())

class MessageStoreTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val protocol = ProtocolJson()
    private val store = MessageStore(null, protocol)

    private fun seqs(conversationId: String = "conv_1") = store.messages(conversationId).map { it.seq }

    @Test
    fun oneCopyPerIdOrderedBySeq() {
        store.putMessages("conv_1", listOf(message(3), message(1)), syncedThrough = 3)
        store.putMessage(message(2))
        store.putMessage(message(3))
        store.putMessages("conv_1", listOf(message(2), message(1)), syncedThrough = null)
        assertEquals(listOf(1L, 2L, 3L), seqs())
        // message.updated: the newer copy wins.
        store.putMessage(message(2, text = "edited"))
        assertEquals("edited", (store.message("msg_2")!!.content as MessageContent.Text).text)
        assertEquals(3, store.messages("conv_1").size)
        assertNull(store.message("msg_9"))
    }

    @Test
    fun serverCopyReplacesThePendingMessage() {
        store.outbox.add(pending("c1", text = "Salam"))
        store.outbox.add(pending("c2", text = "Necəsən"))
        store.putMessages("conv_1", listOf(message(1)), syncedThrough = 1)
        assertEquals(listOf("c1", "c2"), store.pending("conv_1").map { it.id })
        store.commit()

        store.putMessage(message(2, clientId = "c1", text = "Salam"))
        assertEquals(listOf("c2"), store.pending("conv_1").map { it.id })
        assertEquals(listOf("msg_1", "msg_2"), store.messages("conv_1").map { it.id })
        assertEquals(listOf(ClomniChange.Messages("conv_1")), store.commit())
    }

    @Test
    fun aGapAsksForTheMissingRange() {
        store.putMessages("conv_1", (31L..40L).map { message(it) }, syncedThrough = 40)
        assertEquals(40L, store.syncedSeq("conv_1"))
        assertNull(store.putMessage(message(41)))
        assertEquals(41L, store.syncedSeq("conv_1"))
        // 42 never came over the socket: fetched once after 41; the mark is already at what was received.
        assertEquals(41L, store.putMessage(message(43)))
        assertEquals(43L, store.syncedSeq("conv_1"))
        store.putMessages("conv_1", listOf(message(42), message(43)), syncedThrough = 43)
        assertEquals(43L, store.syncedSeq("conv_1"))
        assertNull(store.putMessage(message(44)))
        assertEquals((31L..44L).toList(), seqs())
    }

    @Test
    fun aGapTheSocketFillsItself() {
        store.putMessages("conv_1", listOf(message(40)), syncedThrough = 40)
        assertEquals(40L, store.putMessage(message(42)))
        assertNull(store.putMessage(message(41)))
        assertEquals(42L, store.syncedSeq("conv_1"))
        // An older page never moves the mark back.
        store.putMessages("conv_1", listOf(message(39)), syncedThrough = 39)
        assertEquals(42L, store.syncedSeq("conv_1"))
    }

    @Test
    fun aSeqTheServerNeverShowsIsNotAskedForAgain() {
        store.putMessages("conv_1", listOf(message(40)), syncedThrough = 40)
        assertEquals(40L, store.putMessage(message(42)))
        // after_seq=40 answers 42 alone: 41 is not the user's to see.
        store.putMessages("conv_1", listOf(message(42)), syncedThrough = 42)
        assertNull(store.putMessage(message(43)))
        assertEquals(43L, store.syncedSeq("conv_1"))
    }

    @Test
    fun leavingAndComingBackAsksOnlyForWhatIsNewAndNeverDoubles() {
        // REST had 1-3 (the user's message is 3); the flow's two answers came over the socket, past a seq the user
        // never sees (4).
        store.putMessages("conv_1", (1L..3L).map { message(it) }, syncedThrough = 3)
        assertEquals(3L, store.putMessage(message(5)))
        assertNull(store.putMessage(message(6)))
        assertEquals("the next catch-up is after_seq=6, not 3", 6L, store.syncedSeq("conv_1"))
        // The catch-up and a replayed socket event bring the same messages again, one under another id.
        store.putMessages("conv_1", listOf(message(5), message(6, id = "msg_6_copy")), syncedThrough = 6)
        assertNull(store.putMessage(message(6, id = "msg_6_copy")))
        assertEquals(listOf(1L, 2L, 3L, 5L, 6L), seqs())
        assertEquals(6L, store.syncedSeq("conv_1"))
    }

    @Test
    fun aConversationNeverLoadedHasNoGaps() {
        assertNull(store.putMessage(message(42)))
        assertNull(store.syncedSeq("conv_1"))
        store.putMessages("conv_1", emptyList(), syncedThrough = 0)
        assertEquals(0L, store.syncedSeq("conv_1"))
    }

    @Test
    fun conversations() {
        store.putConversations(listOf(conversation("conv_1", createdAt = 5), conversation("conv_2", createdAt = 1)))
        store.putMessage(message(1, conversationId = "conv_2"))
        assertEquals(listOf("conv_2", "conv_1"), store.conversations().map { it.id })
        assertEquals("msg_1", store.conversation("conv_2")?.lastMessage?.id)

        // A list fetched before the socket's newer message does not take it back.
        store.putMessage(message(7, conversationId = "conv_2"))
        store.putConversation(conversation("conv_2", last = message(1, conversationId = "conv_2"), unread = 2))
        assertEquals(7L, store.conversation("conv_2")?.lastMessage?.seq)
        assertEquals(2, store.conversation("conv_2")?.unreadCount)

        val update = RealtimeEvent.ConversationUpdate("conv_2", ConversationStatus.OPEN, Assignee("Leyla", null, true), null)
        assertTrue(store.apply(update))
        assertEquals(ConversationStatus.OPEN, store.conversation("conv_2")?.status)
        assertEquals("Leyla", store.conversation("conv_2")?.assignee?.name)
        assertEquals(2, store.conversation("conv_2")?.unreadCount)
        assertFalse(store.apply(update.copy(id = "conv_9")))

        store.markSeen("conv_2")
        assertEquals(0, store.conversation("conv_2")?.unreadCount)
        store.markSeen("conv_9")
    }

    @Test
    fun onlyTheLatestUnansweredInteractiveMessageCanBeAnswered() {
        store.putMessages(
            "conv_1",
            listOf(message(1, interactive = true), message(2, interactive = false), message(3, interactive = true), message(4)),
            syncedThrough = 4,
        )
        assertFalse(store.canAnswer(store.message("msg_1")!!))
        assertFalse(store.canAnswer(store.message("msg_2")!!))
        assertFalse(store.canAnswer(store.message("msg_4")!!))
        assertTrue(store.canAnswer(store.message("msg_3")!!))
        store.markAnswered("msg_3")
        assertTrue(store.isAnswered("msg_3"))
        assertFalse(store.canAnswer(store.message("msg_3")!!))
        // Not yet in the store (it is not loaded): only its own flag counts.
        assertTrue(store.canAnswer(message(9, conversationId = "conv_9", interactive = true)))
    }

    /**
     * Operator, 2026-10-04 (72): only the last, unanswered bot message shows its choices; once the user's choice (or
     * anything else) follows, they are gone, also in a history loaded afresh with nothing marked on this device.
     */
    @Test
    fun choicesOnlyOnTheLastUnansweredMessage() {
        val buttons = listOf(MessageContent.Button("b1", "Sifarişim haqqında", null, "p1"))
        fun choices(seq: Long) = message(seq, interactive = true)
            .copy(content = MessageContent.QuickReplies("Nə ilə kömək edək?", buttons, MessageContent.QuickRepliesLayout.VERTICAL, true, false))
        val system = message(4).copy(content = MessageContent.System(MessageContent.SystemEvent.WaitingInQueue, "Növbədəsiniz", 2))
        // Reloaded: two steps, the first answered by the user's bubble; the second one waits.
        store.putMessages("conv_1", listOf(choices(1), message(2, clientId = "c_2", text = "Sifarişim haqqında"), choices(3)), syncedThrough = 3)
        assertFalse(store.canAnswer(store.message("msg_1")!!))
        assertTrue(store.canAnswer(store.message("msg_3")!!))
        // A system line after it does not answer it.
        store.putMessages("conv_1", listOf(system), syncedThrough = 4)
        assertTrue(store.canAnswer(store.message("msg_3")!!))
        // The user's choice arrives from the server (another device, or a reload after it): the choices are gone.
        store.putMessages("conv_1", listOf(message(5, clientId = "c_5", text = "Sifariş haradadır?")), syncedThrough = 5)
        assertFalse(store.canAnswer(store.message("msg_3")!!))
    }

    @Test
    fun keptOnDiskForTheNextLaunch() {
        val dir = folder.newFolder()
        val first = MessageStore(dir, protocol)
        first.putConversation(conversation("conv_1"))
        first.putMessages("conv_1", (1L..150L).map { message(it, interactive = it == 150L) }, syncedThrough = 150)
        first.putMessages("conv/2", listOf(message(1, conversationId = "conv/2")), syncedThrough = null)
        val body = """{"brand":{"name":"Apar","primary_color":"#1F9D63"}}"""
        first.setConfig(protocol.parseConfig(body)!!, body, "W/\"1\"")
        first.setUnreadTotal(3)
        first.markReadByOperator("conv_1", 149)
        first.markAnswered("msg_150")
        first.outbox.add(pending("c1"))
        first.commit()

        // The first frame reads the look alone, before (or without) the whole cache.
        val early = MessageStore(dir, protocol)
        assertEquals("#1F9D63", early.cachedConfig()?.brand?.primaryColor)
        assertTrue(early.conversations().isEmpty())

        val second = MessageStore(dir, protocol)
        second.load()
        assertEquals(listOf("conv_1"), second.conversations().map { it.id })
        assertEquals(150L, second.conversation("conv_1")?.lastMessage?.seq)
        assertEquals((51L..150L).toList(), second.messages("conv_1").map { it.seq })
        assertEquals(first.messages("conv_1").takeLast(100), second.messages("conv_1"))
        assertEquals(listOf("msg_1"), second.messages("conv/2").map { it.id })
        assertEquals(150L, second.syncedSeq("conv_1"))
        assertNull(second.syncedSeq("conv/2"))
        assertEquals("Apar", second.config?.brand?.name)
        assertEquals("W/\"1\"", second.configEtag)
        assertEquals(3, second.unreadTotal)
        assertEquals(149L, second.readByOperator("conv_1"))
        assertFalse(second.canAnswer(second.message("msg_150")!!))
        assertEquals(listOf("c1"), second.outbox.all().map { it.id })
        assertTrue(second.commit().containsAll(listOf(ClomniChange.Config, ClomniChange.Conversations, ClomniChange.Unread(3))))
    }

    @Test
    fun brokenFilesAreIgnored() {
        val dir = folder.newFolder()
        File(dir, "conversations.json").writeText("{not json")
        File(dir, "config.json").writeText("""{"etag":"x","body":"[]"}""")
        File(dir, "messages").mkdirs()
        File(dir, "messages/conv_1.json").writeText("""{"messages":[]}""")
        File(dir, "messages/conv_2.json").writeText("""[1,2]""")
        val store = MessageStore(dir, protocol)
        store.load()
        assertEquals(emptyList<Conversation>(), store.conversations())
        assertNull(store.config)
        assertNull(store.configEtag)
        assertFalse(File(dir, "conversations.json").exists())
    }

    @Test
    fun aDamagedCacheIsReadAsFarAsItGoes() {
        val dir = folder.newFolder()
        File(dir, "outbox.json").writeText(
            """{"entries":[1,{"message":"x"},{"message":{"client_id":"c1","type":"text","content":{"text":"a"}}},
               {"conversation_id":"conv_1","message":{"client_id":"c2","type":"text","content":{"text":"b"}},"created_at":"x",
                "attempts":"y","fields":{"a":1,"b":"c"},"state":"failed","error_code":"e"}]}""",
        )
        File(dir, "conversations.json").writeText(
            """{"conversations":[1,{"id":"x"}],"unread_total":"2","read_by_operator":{"conv_1":"x","conv_2":4},"answered":[1,"msg_1"]}""",
        )
        File(dir, "messages").mkdirs()
        File(dir, "messages/a.json").writeText("""{"conversation_id":"conv_1","messages":[1,{"id":"x"}],"synced_seq":"x"}""")
        File(dir, "config.json").writeText("""{"etag":5,"body":"{}"}""")
        val store = MessageStore(dir, protocol)
        store.load()

        val kept = store.outbox.all().single()
        assertEquals("c2", kept.id)
        assertEquals(PendingMessage.State.FAILED, kept.state)
        assertEquals(0L, kept.createdAt)
        assertEquals(0, kept.attempts)
        assertEquals("e", kept.errorCode)
        assertEquals(mapOf("b" to "c"), kept.fields)
        assertEquals(emptyList<Conversation>(), store.conversations())
        // Our own file: a number written as a string still reads.
        assertEquals(2, store.unreadTotal)
        assertEquals(4L, store.readByOperator("conv_2"))
        assertNull(store.readByOperator("conv_1"))
        assertTrue(store.isAnswered("msg_1"))
        assertEquals(emptyList<Message>(), store.messages("conv_1"))
        assertNull(store.syncedSeq("conv_1"))
        assertEquals("", store.config?.brand?.name)
        assertEquals("5", store.configEtag)

        // Without a directory there is nothing to read or delete.
        val memory = MessageStore(null, protocol)
        memory.load()
        memory.clear()
        assertTrue(memory.commit().contains(ClomniChange.Unread(0)))
    }

    @Test
    fun logoutLeavesNothing() {
        val dir = folder.newFolder()
        val store = MessageStore(dir, protocol)
        store.putConversation(conversation())
        store.putMessages("conv_1", listOf(message(1, interactive = true)), syncedThrough = 1)
        store.setConfig(protocol.parseConfig("{}")!!, "{}", "e")
        store.setUnreadTotal(1)
        store.markAnswered("msg_1")
        store.outbox.add(pending("c1"))
        store.commit()

        store.clear()
        assertTrue(store.outbox.all().isEmpty())
        assertEquals(emptyList<Conversation>(), store.conversations())
        assertEquals(emptyList<Message>(), store.messages("conv_1"))
        assertNull(store.config)
        assertEquals(0, store.unreadTotal)
        assertFalse(store.isAnswered("msg_1"))
        assertEquals(listOf<String>(), dir.list()!!.toList())
        assertTrue(store.commit().contains(ClomniChange.Unread(0)))

        val reloaded = MessageStore(dir, protocol)
        reloaded.load()
        assertEquals(emptyList<Conversation>(), reloaded.conversations())
    }

    @Test
    fun commitAnswersOnlyRealChanges() {
        store.putConversation(conversation())
        store.putMessages("conv_1", listOf(message(1)), syncedThrough = null)
        assertEquals(listOf(ClomniChange.Conversations, ClomniChange.Messages("conv_1")), store.commit())
        store.putMessage(message(1))
        store.putConversation(conversation(last = message(1)))
        store.setUnreadTotal(0)
        store.markAnswered("msg_9")
        assertEquals(emptyList<ClomniChange>(), store.commit())
        store.markReadByOperator("conv_1", 0)
        store.markReadByOperator("conv_1", 0)
        store.setUnreadTotal(2)
        store.markAnswered("msg_1")
        store.changed(ClomniChange.Messages("conv_7"))
        assertEquals(
            listOf(
                ClomniChange.Read("conv_1", 0),
                ClomniChange.Unread(2),
                ClomniChange.Messages("conv_1"),
                ClomniChange.Messages("conv_7"),
            ),
            store.commit(),
        )
    }
}

class OutboxTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val protocol = ProtocolJson()

    @Test
    fun failsAfterThreeAttemptsAndCanBeRetried() {
        val outbox = Outbox(null, protocol)
        outbox.add(pending("c1"))
        outbox.add(pending("c2"))
        assertEquals("c1", outbox.next()?.id)
        assertEquals(PendingMessage.State.SENDING, outbox.recordFailure("c1")?.state)
        assertEquals(PendingMessage.State.SENDING, outbox.recordFailure("c1")?.state)
        val failed = outbox.recordFailure("c1")!!
        assertEquals(PendingMessage.State.FAILED, failed.state)
        assertEquals(3, failed.attempts)
        // A failed message does not hold up the next one.
        assertEquals("c2", outbox.next()?.id)

        assertTrue(outbox.retry("c1"))
        assertEquals(pending("c1"), outbox.entry("c1"))
        assertFalse(outbox.retry("c1"))
        assertEquals("c1", outbox.next()?.id)
        assertNull(outbox.recordFailure("c9"))
        assertNull(outbox.refuse("c9", null))
        outbox.add(pending("c3"))
        val refused = outbox.refuse("c3", null)!!
        assertEquals(PendingMessage.State.FAILED, refused.state)
        assertNull(refused.errorCode)
        assertEquals(emptyMap<String, String>(), refused.fields)
        assertNull(outbox.remove("c9"))
        assertFalse(outbox.retry("c9"))
    }

    @Test
    fun aRefusedMessageFailsAtOnceWithTheReason() {
        val outbox = Outbox(null, protocol)
        outbox.add(pending("c1"))
        val failed = outbox.refuse("c1", ServerError("validation_failed", "phone", "req_1", mapOf("phone" to "invalid")))!!
        assertEquals(PendingMessage.State.FAILED, failed.state)
        assertEquals("validation_failed", failed.errorCode)
        assertEquals(mapOf("phone" to "invalid"), failed.fields)
        assertNull(outbox.next())
        assertTrue(outbox.retry("c1"))
        assertEquals(pending("c1"), outbox.entry("c1"))
    }

    @Test
    fun survivesTheProcess() {
        val file = JsonFile(File(folder.newFolder(), "outbox.json"))
        val outbox = Outbox(file, protocol)
        outbox.add(pending("c1", "conv_2"))
        outbox.add(PendingMessage("conv_1", ClientMessage.back("msg_f10", "c2"), null, 9))
        outbox.refuse("c2", ServerError("validation_failed", "bad", null, mapOf("a" to "b")))
        outbox.add(pending("c1", "conv_2").copy(preview = "replaced"))

        val again = Outbox(file, protocol)
        again.load()
        assertEquals(outbox.all(), again.all())
        assertEquals(listOf("c1"), again.entries("conv_2").map { it.id })
        assertEquals("replaced", again.entry("c1")?.preview)

        again.remove("c1")
        again.clear()
        val empty = Outbox(file, protocol)
        empty.load()
        assertTrue(empty.all().isEmpty())
    }

    /** An attachment's bytes wait in the outbox's folder; its upload id, once known, survives the process. */
    @Test
    fun attachmentsAreStagedAndRemembered() {
        val dir = folder.newFolder()
        val file = JsonFile(File(dir, "outbox.json"))
        val files = File(dir, "uploads")
        val outbox = Outbox(file, protocol, files)
        val message = ClientMessage.Attachment("", "Velosiped", "c1")
        val stored = outbox.stage("c1", byteArrayOf(1, 2, 3))!!
        val upload = PendingUpload("velo.jpg", "image/jpeg", 3, stored)
        outbox.add(PendingMessage("conv_1", message, "Velosiped", 5, upload = upload))
        assertTrue(outbox.stagedFile(upload)!!.readBytes().contentEquals(byteArrayOf(1, 2, 3)))

        val sent = outbox.uploaded("c1", "upl_9")!!
        assertEquals(ClientMessage.Attachment("upl_9", "Velosiped", "c1"), sent.message)
        assertEquals("upl_9", sent.upload?.uploadId)
        assertNull(outbox.uploaded("missing", "upl_1"))
        outbox.add(pending("c2"))
        assertEquals("only an attachment takes an upload id", pending("c2"), outbox.uploaded("c2", "upl_2"))

        // A file the previous run staged but never wrote down is cleaned away.
        File(files, "upload-orphan").writeText("x")
        val again = Outbox(file, protocol, files)
        again.load()
        assertEquals(outbox.all(), again.all())
        assertFalse(File(files, "upload-orphan").exists())
        assertTrue(File(files, stored).exists())

        assertEquals("file_missing", again.fail("c1", "file_missing")?.errorCode)
        assertEquals(PendingMessage.State.FAILED, again.entry("c1")?.state)
        again.remove("c1")
        assertFalse("removing an attachment deletes its file", File(files, stored).exists())
        again.stage("c3", byteArrayOf(4))
        again.clear()
        assertFalse(files.exists())

        // Without a folder nothing can be staged.
        assertNull(Outbox(null, protocol).stage("c4", byteArrayOf(1)))
        assertNull(Outbox(null, protocol).stagedFile(upload))
    }

    @Test
    fun aBrokenUploadRecordDropsItsEntry() {
        val dir = folder.newFolder()
        val file = JsonFile(File(dir, "outbox.json"))
        file.write(
            kotlinx.serialization.json.Json.parseToJsonElement(
                """{"entries":[
                  {"conversation_id":"conv_1","message":{"client_id":"c1","type":"attachment","content":{"upload_id":""}},
                   "created_at":1,"upload":{"mime":"image/jpeg","stored_as":"upload-c1"}},
                  {"conversation_id":"conv_1","message":{"client_id":"c2","type":"attachment","content":{"upload_id":""}},
                   "created_at":2,"upload":{"file_name":"a.pdf","mime":"application/pdf","size":"big","stored_as":"upload-c2"}}
                ]}""",
            ),
        )
        val outbox = Outbox(file, protocol, File(dir, "uploads"))
        outbox.load()
        assertEquals(listOf("c2"), outbox.all().map { it.id })
        assertEquals(PendingUpload("a.pdf", "application/pdf", 0, "upload-c2"), outbox.entry("c2")?.upload)
    }
}
