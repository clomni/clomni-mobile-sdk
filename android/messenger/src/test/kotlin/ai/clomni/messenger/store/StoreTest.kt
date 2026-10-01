package ai.clomni.messenger.store

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

class StoreTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val protocol = ProtocolJson()
    private val store = Store(null, protocol)

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
    fun serverCopyReplacesTheOptimisticBubble() {
        store.outbox.add(OutboxItem("conv_1", ClientMessage.Text("Salam", "c1"), "Salam", 1))
        store.outbox.add(OutboxItem("conv_1", ClientMessage.Text("Necəsən", "c2"), "Necəsən", 2))
        store.putMessages("conv_1", listOf(message(1)), syncedThrough = 1)
        assertEquals(
            listOf("msg_1", "c1", "c2"),
            store.timeline("conv_1").map {
                when (it) {
                    is TimelineItem.Received -> it.message.id
                    is TimelineItem.Outgoing -> it.item.clientId
                }
            },
        )
        store.putMessage(message(2, clientId = "c1", text = "Salam"))
        assertEquals(listOf("c2"), store.outbox.all().map { it.clientId })
        assertEquals(3, store.timeline("conv_1").size)
        assertEquals(TimelineItem.Received(message(2, clientId = "c1", text = "Salam")), store.timeline("conv_1")[1])
    }

    @Test
    fun aGapAsksForTheMissingRange() {
        store.putMessages("conv_1", (31L..40L).map { message(it) }, syncedThrough = 40)
        assertEquals(40L, store.syncedSeq("conv_1"))
        assertNull(store.putMessage(message(41)))
        assertEquals(41L, store.syncedSeq("conv_1"))
        // 42 never came over the socket.
        assertEquals(41L, store.putMessage(message(43)))
        assertEquals(41L, store.syncedSeq("conv_1"))
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
        assertTrue(store.updateConversation(update))
        assertEquals(ConversationStatus.OPEN, store.conversation("conv_2")?.status)
        assertEquals("Leyla", store.conversation("conv_2")?.assignee?.name)
        assertEquals(2, store.conversation("conv_2")?.unreadCount)
        assertFalse(store.updateConversation(update.copy(id = "conv_9")))

        store.markRead("conv_2")
        assertEquals(0, store.conversation("conv_2")?.unreadCount)
        store.markRead("conv_9")
    }

    @Test
    fun answeredButtonsStopWorking() {
        store.putMessages("conv_1", listOf(message(1, interactive = true), message(2)), syncedThrough = 2)
        assertEquals(1L, store.disableInteraction("msg_1")?.seq)
        assertEquals(false, store.message("msg_1")?.flow?.interactive)
        assertEquals(message(2), store.disableInteraction("msg_2"))
        assertNull(store.disableInteraction("msg_9"))
    }

    @Test
    fun keptOnDiskForTheNextLaunch() {
        val dir = folder.newFolder()
        val first = Store(dir, protocol)
        first.putConversation(conversation("conv_1"))
        first.putMessages("conv_1", (1L..250L).map { message(it, interactive = it == 250L) }, syncedThrough = 250)
        first.putMessages("conv/2", listOf(message(1, conversationId = "conv/2")), syncedThrough = null)
        first.setConfig(protocol.parseConfig("""{"brand":{"name":"Apar","primary_color":"#1F9D63"}}""")!!, """{"brand":{"name":"Apar","primary_color":"#1F9D63"}}""", "W/\"1\"")
        first.setUnreadTotal(3)
        first.setOperatorRead("conv_1", 249)
        first.outbox.add(OutboxItem("conv_1", ClientMessage.Text("Salam", "c1"), "Salam", 1))
        first.commit()

        val second = Store(dir, protocol)
        second.load()
        assertEquals(listOf("conv_1"), second.conversations().map { it.id })
        assertEquals(250L, second.conversation("conv_1")?.lastMessage?.seq)
        assertEquals((51L..250L).toList(), second.messages("conv_1").map { it.seq })
        assertEquals(first.messages("conv_1").takeLast(200), second.messages("conv_1"))
        assertEquals(listOf("msg_1"), second.messages("conv/2").map { it.id })
        assertEquals(250L, second.syncedSeq("conv_1"))
        assertNull(second.syncedSeq("conv/2"))
        assertEquals("Apar", second.config?.brand?.name)
        assertEquals("W/\"1\"", second.configEtag)
        assertEquals(3, second.unreadTotal)
        assertEquals(249L, second.operatorReadSeq("conv_1"))
        assertEquals(listOf("c1"), second.outbox.all().map { it.clientId })
    }

    @Test
    fun brokenFilesAreIgnored() {
        val dir = folder.newFolder()
        File(dir, "conversations.json").writeText("{not json")
        File(dir, "config.json").writeText("""{"etag":"x","body":"[]"}""")
        File(dir, "messages").mkdirs()
        File(dir, "messages/conv_1.json").writeText("""{"messages":[]}""")
        File(dir, "messages/conv_2.json").writeText("""[1,2]""")
        val store = Store(dir, protocol)
        store.load()
        assertEquals(emptyList<Conversation>(), store.conversations())
        assertNull(store.config)
        assertNull(store.configEtag)
        assertFalse(File(dir, "conversations.json").exists())
    }

    @Test
    fun logoutLeavesNothing() {
        val dir = folder.newFolder()
        val store = Store(dir, protocol)
        var notified = 0
        store.addListener { notified++ }
        store.putConversation(conversation())
        store.putMessages("conv_1", listOf(message(1)), syncedThrough = 1)
        store.setConfig(protocol.parseConfig("{}")!!, "{}", "e")
        store.setUnreadTotal(1)
        store.outbox.add(OutboxItem("conv_1", ClientMessage.Text("a", "c1"), "a", 1))
        store.commit()
        assertEquals(1, notified)

        store.clear(keepOutbox = true)
        assertEquals(2, notified)
        assertEquals(listOf("c1"), store.outbox.all().map { it.clientId })
        store.clear()
        assertTrue(store.outbox.all().isEmpty())
        assertEquals(emptyList<Conversation>(), store.conversations())
        assertEquals(emptyList<Message>(), store.messages("conv_1"))
        assertNull(store.config)
        assertEquals(0, store.unreadTotal)
        assertEquals(listOf<String>(), dir.list()!!.toList())

        val reloaded = Store(dir, protocol)
        reloaded.load()
        assertEquals(emptyList<Conversation>(), reloaded.conversations())
    }

    @Test
    fun listenersHearOnlyRealChanges() {
        var notified = 0
        store.addListener { notified++ }
        store.putMessages("conv_1", listOf(message(1)), syncedThrough = null)
        store.commit()
        store.putMessage(message(1))
        store.setUnreadTotal(0)
        store.setOperatorRead("conv_1", 0)
        store.setOperatorRead("conv_1", 0)
        store.commit()
        store.commit()
        assertEquals(2, notified)
    }
}

class OutboxTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val protocol = ProtocolJson()

    private fun item(clientId: String, conversationId: String = "conv_1") =
        OutboxItem(conversationId, ClientMessage.Text("t-$clientId", clientId), "t-$clientId", createdAt = clientId.length.toLong())

    @Test
    fun failsAfterThreeAttemptsAndCanBeRetried() {
        val outbox = Outbox(null, protocol)
        outbox.add(item("c1"))
        outbox.add(item("c2"))
        assertEquals("c1", outbox.next()?.clientId)
        assertEquals(OutboxItem.State.PENDING, outbox.recordFailure("c1")?.state)
        assertEquals(OutboxItem.State.PENDING, outbox.recordFailure("c1")?.state)
        val failed = outbox.recordFailure("c1")!!
        assertEquals(OutboxItem.State.FAILED, failed.state)
        assertEquals(3, failed.attempts)
        // A failed message does not hold up the next one.
        assertEquals("c2", outbox.next()?.clientId)

        assertTrue(outbox.retry("c1"))
        assertEquals(OutboxItem(item("c1").conversationId, item("c1").message, "t-c1", 2), outbox.get("c1"))
        assertFalse(outbox.retry("c1"))
        assertEquals("c1", outbox.next()?.clientId)
        assertNull(outbox.recordFailure("c9"))
        assertNull(outbox.remove("c9"))
        assertFalse(outbox.retry("c9"))
    }

    @Test
    fun aRefusedMessageFailsAtOnce() {
        val outbox = Outbox(null, protocol)
        outbox.add(item("c1"))
        val error = ServerError("validation_failed", "phone", "req_1", mapOf("phone" to "invalid"))
        val failed = outbox.recordFailure("c1", error, final = true)!!
        assertEquals(OutboxItem.State.FAILED, failed.state)
        assertEquals(error, failed.error)
        assertNull(outbox.next())
    }

    @Test
    fun survivesTheProcess() {
        val file = JsonFile(File(folder.newFolder(), "outbox.json"))
        val outbox = Outbox(file, protocol)
        outbox.add(item("c1", "conv_2"))
        outbox.add(OutboxItem("conv_1", ClientMessage.back("msg_f10", "c2"), "← Geri", 9))
        outbox.recordFailure("c2", ServerError("validation_failed", "bad", null, mapOf("a" to "b")), final = true)
        outbox.add(item("c1", "conv_2").copy(preview = "replaced"))

        val again = Outbox(file, protocol)
        again.load()
        assertEquals(outbox.all().sortedBy { it.clientId }, again.all().sortedBy { it.clientId })
        assertEquals(listOf("c1"), again.items("conv_2").map { it.clientId })
        assertEquals("replaced", again.get("c1")?.preview)

        again.remove("c1")
        again.clear()
        val empty = Outbox(file, protocol)
        empty.load()
        assertTrue(empty.all().isEmpty())
    }
}
