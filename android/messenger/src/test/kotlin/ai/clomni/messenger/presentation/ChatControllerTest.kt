package ai.clomni.messenger.presentation

import ai.clomni.messenger.api.ClomniError
import ai.clomni.messenger.core.ClomniChange
import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import ai.clomni.messenger.store.PendingMessage
import ai.clomni.messenger.store.PendingUpload
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executor
import java.util.concurrent.Future

/** A conversation the test fills in, recording what the controller asked for. */
private class FakeChat : ChatDataSource {
    var cachedConfig: MessengerConfig? = Fixture.aparConfig
    val conversations = mutableMapOf<String, Conversation>()
    val stored = mutableMapOf<String, List<Message>>()
    val outbox = mutableListOf<PendingMessage>()
    var answerable = mutableSetOf<String>()
    var loadFails = false
    val calls = mutableListOf<String>()
    val typingStates = mutableListOf<Boolean>()
    val observers = LinkedHashMap<UUID, (ClomniChange) -> Unit>()

    override val config: MessengerConfig? get() = cachedConfig

    fun set(messages: List<Message>, id: String = "conv_5521", answerable: Set<String> = emptySet(), loadFails: Boolean = false) {
        stored[id] = messages
        this.answerable = answerable.toMutableSet()
        this.loadFails = loadFails
    }

    fun push(change: ClomniChange) = observers.values.toList().forEach { it(change) }

    private fun <T> done(value: T): Future<T> = CompletableFuture.completedFuture(value)

    private fun <T> failed(error: Throwable): Future<T> = CompletableFuture<T>().apply { completeExceptionally(error) }

    override fun conversation(id: String): Conversation? = conversations[id]

    override fun refreshConversation(id: String): Future<Unit> {
        calls += "refreshConversation $id"
        conversations[id] = ChatFixture.conversation("bot", id = id)
        return done(Unit)
    }

    override fun messages(conversationId: String): List<Message> = stored[conversationId].orEmpty()

    override fun pending(conversationId: String): List<PendingMessage> = outbox.filter { it.conversationId == conversationId }

    override fun canAnswer(message: Message): Boolean = message.id in answerable

    override fun readByOperator(conversationId: String): Long? = null

    override fun localFile(pending: PendingMessage): File? = pending.upload?.let { File("/tmp/${it.storedAs}") }

    override fun loadMessages(conversationId: String): Future<Unit> {
        calls += "load $conversationId"
        return if (loadFails) failed(ClomniError.Network("offline")) else done(Unit)
    }

    override fun loadOlder(conversationId: String): Future<Boolean> {
        calls += "older $conversationId"
        return done(false)
    }

    override fun markRead(conversationId: String): Future<Unit> {
        calls += "read $conversationId"
        return done(Unit)
    }

    override fun setTyping(isTyping: Boolean, conversationId: String): Future<Unit> {
        typingStates += isTyping
        return done(Unit)
    }

    override fun sendText(text: String, conversationId: String): Future<PendingMessage> {
        calls += "text $text"
        return done(queue(ClientMessage.Text(text), conversationId, text))
    }

    override fun reply(message: Message, button: MessageContent.Button): Future<PendingMessage> {
        if (!answerable.remove(message.id)) return failed(ClomniError.Rejected("already answered"))
        calls += "reply ${message.id} ${button.id}"
        return done(queue(ClientMessage.ButtonReply(message.id, button.id, button.payload), message.conversationId, button.title))
    }

    override fun goBack(message: Message): Future<PendingMessage> {
        calls += "back ${message.id}"
        return done(queue(ClientMessage.back(message.id), message.conversationId, null))
    }

    override fun submitForm(message: Message, values: Map<String, JsonElement>): Future<PendingMessage> {
        calls += "form ${message.id} ${JsonObject(values.toSortedMap())}"
        return done(queue(ClientMessage.FormSubmit(message.id, "frm", values), message.conversationId, null))
    }

    override fun sendFile(
        data: ByteArray,
        fileName: String,
        mime: String,
        caption: String?,
        conversationId: String,
    ): Future<PendingMessage> {
        if (data.size > 10) return failed(ClomniError.Rejected("file over 10 MB"))
        if (data.isEmpty()) return failed(ClomniError.Rejected("file not stored"))
        calls += "file $fileName"
        val entry = queue(ClientMessage.Attachment("", caption), conversationId, caption)
            .copy(upload = PendingUpload(fileName, mime, data.size.toLong(), "upload-1"))
        outbox[outbox.size - 1] = entry
        return done(entry)
    }

    override fun retry(clientId: String): Future<Unit> {
        calls += "retry $clientId"
        return done(Unit)
    }

    override fun draft(openedFrom: String?): String {
        calls += "draft"
        return "draft_new"
    }

    override fun observe(handler: (ClomniChange) -> Unit): UUID = UUID.randomUUID().also { observers[it] = handler }

    override fun stopObserving(token: UUID) {
        observers.remove(token)
    }

    private fun queue(content: ClientMessage, conversationId: String, preview: String?): PendingMessage {
        val entry = PendingMessage(conversationId, content, preview, 1_790_850_700_000L)
        outbox += entry
        return entry
    }
}

/** Timers the test fires by hand. */
private class Timers : Scheduler {
    val pending = mutableListOf<() -> Unit>()

    override fun after(delayMs: Long, action: () -> Unit): () -> Unit {
        pending += action
        return { pending.remove(action) }
    }

    fun fire() = pending.toList().also { pending.clear() }.forEach { it() }
}

class ChatControllerTest {
    private val source = FakeChat()
    private val timers = Timers()
    private val direct = Executor { it.run() }
    private var renders = 0

    private fun controller(worker: Executor = direct, main: Executor = direct) = ChatController(
        source, "conv_5521", "az", worker, main, timers,
        known = mapOf("name" to "Aysel"), timeZone = TimeZone.getTimeZone("UTC"), now = { 1_790_850_720_000L },
    ).also { it.onChange = { renders++ } }

    private fun bubbleTexts(chat: ChatController) = chat.screen.items.filterIsInstance<ChatItem.BubbleItem>()
        .mapNotNull { (it.bubble.body as? Bubble.TextBody)?.runs?.joinToString("") { run -> run.text } }

    @Test
    fun loadsCacheThenServerAndMarksRead() {
        source.set(listOf(ChatFixture.message("01-text-bot.json")))
        val chat = controller()
        assertEquals(HomeScreen.Phase.LOADING, chat.screen.phase)
        chat.load()
        assertEquals(HomeScreen.Phase.READY, chat.screen.phase)
        assertEquals(2, renders)
        assertEquals(listOf("refreshConversation conv_5521", "load conv_5521", "read conv_5521"), source.calls)
        assertEquals("Apar", chat.screen.header.title)
        assertEquals("Apar", chat.config?.brand?.name)
        chat.load()
        assertEquals("loading again does not listen twice", 1, source.observers.size)
        assertEquals("the conversation is known now", 1, source.calls.count { it.startsWith("refreshConversation") })
    }

    @Test
    fun failedFirstLoadOffersRetry() {
        source.set(emptyList(), loadFails = true)
        val chat = controller()
        chat.load()
        assertEquals(HomeScreen.Phase.FAILED, chat.screen.phase)
        source.set(listOf(ChatFixture.message("01-text-bot.json")))
        chat.retry()
        assertEquals(HomeScreen.Phase.READY, chat.screen.phase)
    }

    @Test
    fun buttonsBackAndASecondTap() {
        val step = ChatFixture.message("10-apar-level2-S-chips.json")
        source.set(listOf(step), answerable = setOf(step.id))
        val chat = controller()
        chat.load()
        assertEquals(ChatComposer.Mode.Locked("Yuxarıdan birini seçin"), chat.screen.composer.mode)
        chat.tap("o_t", step.id)
        chat.tap("o_u", step.id)
        chat.tap("missing", "msg_unknown")
        chat.tap("missing", step.id)
        assertEquals("the second tap finds the buttons gone", listOf("reply msg_f10 o_t"), source.calls.filter { it.startsWith("reply") })
        assertTrue(chat.screen.items.none { it is ChatItem.RepliesItem })
        assertTrue("the choice stays as the user's message", "Velosiped dayandı" in bubbleTexts(chat))
        source.set(listOf(step), answerable = setOf(step.id))
        chat.tap("back", step.id)
        assertTrue("back msg_f10" in source.calls)
        val text = ChatFixture.message("01-text-bot.json")
        source.set(listOf(text))
        chat.load()
        chat.tap("x", text.id)
        assertTrue("not quick replies: nothing", source.calls.none { it.startsWith("reply msg_f01") })
    }

    @Test
    fun formErrorsThenSubmit() {
        val form = ChatFixture.message("19-form-contact.json")
        source.set(listOf(form), answerable = setOf(form.id))
        val chat = controller()
        chat.load()
        val card = chat.screen.items.filterIsInstance<ChatItem.BubbleItem>().single().bubble.body as FormCard
        assertEquals("known details prefill the form", "Aysel", card.fields.first().initialValue)
        val errors = chat.submit(form.id, mapOf("name" to "", "phone" to "12"))
        assertEquals(mapOf("name" to "Bu sahəni doldurun", "phone" to "Telefon nömrəsi düzgün deyil"), errors)
        assertTrue(source.calls.none { it.startsWith("form") })
        assertEquals(emptyMap<String, String>(), chat.submit(form.id, mapOf("name" to "Aysel", "phone" to "050 123 45 67")))
        assertTrue(source.calls.toString(), """form msg_f19 {"email":"","name":"Aysel","phone":"+994501234567"}""" in source.calls)
        assertEquals(emptyMap<String, String>(), chat.submit("msg_unknown", emptyMap()))
        source.set(listOf(ChatFixture.message("01-text-bot.json")))
        chat.load()
        assertEquals("not a form", emptyMap<String, String>(), chat.submit("msg_f01", emptyMap()))
    }

    @Test
    fun sendingTextFilesAndRetry() {
        val chat = controller()
        chat.load()
        assertFalse(chat.send("   "))
        assertTrue(chat.send("Salam"))
        chat.textChanged("Sa")
        chat.textChanged("  ")
        assertEquals("off after sending, on while typing, off when cleared", listOf(false, true, false), source.typingStates)

        val refusals = mutableListOf<String?>()
        chat.sendFile(ByteArray(20), "big.jpg", "image/jpeg") { refusals += it }
        chat.sendFile(ByteArray(20), "big.pdf", "application/pdf") { refusals += it }
        chat.sendFile(ByteArray(0), "empty.pdf", "application/pdf") { refusals += it }
        chat.sendFile(ByteArray(5), "velo.jpg", "image/jpeg", "Velosiped") { refusals += it }
        assertEquals(
            listOf("Fayl çox böyükdür (maks. 10 MB)", "Fayl çox böyükdür (maks. 25 MB)", "Nəsə səhv getdi", null),
            refusals,
        )
        chat.attach({ refusals += it }) { null }
        chat.attach({ refusals += it }) { error("the picker's file is gone") }
        assertEquals("a file that cannot be read", listOf("Nəsə səhv getdi", "Nəsə səhv getdi"), refusals.takeLast(2))
        source.push(ClomniChange.Messages("conv_5521"))
        val images = chat.screen.items.mapNotNull { ((it as? ChatItem.BubbleItem)?.bubble?.body as? Bubble.ImageBody)?.localFile }
        assertEquals(listOf(File("/tmp/upload-1")), images)
        chat.retrySending("abc")
        assertEquals(
            listOf("text Salam", "file velo.jpg", "retry abc"),
            source.calls.filter { !it.startsWith("load") && !it.startsWith("read") && !it.startsWith("refresh") },
        )
    }

    @Test
    fun typingShowsAndHides() {
        source.set(listOf(ChatFixture.message("03-text-user.json")))
        val chat = controller()
        chat.load()
        val leyla = Sender(SenderType.OPERATOR, name = "Leyla")
        source.push(ClomniChange.Typing("conv_5521", leyla, true))
        source.push(ClomniChange.Typing("conv_other", leyla, true))
        assertTrue("typing shows", chat.screen.items.last() is ChatItem.TypingItem)
        assertEquals(1, timers.pending.size)
        timers.fire()
        assertFalse("hidden after the timeout", chat.screen.items.last() is ChatItem.TypingItem)

        // A message from the one typing ends it at once.
        source.push(ClomniChange.Typing("conv_5521", leyla, true))
        source.set(
            listOf(
                ChatFixture.message("03-text-user.json"),
                ChatFixture.message("31-operator-no-avatar.json", "created_at" to "2026-10-01T10:31:00Z"),
            ),
        )
        source.push(ClomniChange.Messages("conv_5521"))
        assertFalse("the message replaced the indicator", chat.screen.items.last() is ChatItem.TypingItem)
        assertTrue("and its timer", timers.pending.isEmpty())

        // A message from someone else leaves it.
        val bot = Sender(SenderType.BOT)
        source.push(ClomniChange.Typing("conv_5521", bot, true))
        source.set(source.stored.getValue("conv_5521") + ChatFixture.message("03-text-user.json", "id" to "msg_u2", "seq" to 31))
        source.push(ClomniChange.Messages("conv_5521"))
        assertTrue(chat.screen.items.last() is ChatItem.TypingItem)

        source.push(ClomniChange.Typing("conv_5521", leyla, false))
        assertFalse("off is off", chat.screen.items.last() is ChatItem.TypingItem)
        assertTrue(timers.pending.isEmpty())
    }

    @Test
    fun otherChangesAndStop() {
        val chat = controller()
        chat.load()
        val before = renders
        source.push(ClomniChange.Unread(3))
        source.push(ClomniChange.Messages("conv_other"))
        source.push(ClomniChange.Read("conv_other", 3))
        assertEquals("not this conversation's business", before, renders)
        source.push(ClomniChange.Read("conv_5521", 3))
        source.push(ClomniChange.Conversations)
        source.push(ClomniChange.Config)
        source.push(ClomniChange.Session)
        assertEquals(before + 4, renders)
        chat.isOffline = true
        assertEquals("İnternet yoxdur", chat.screen.offline)
        val older = mutableListOf<Boolean>()
        chat.loadOlder { older += it }
        assertEquals(listOf(false), older)
        source.push(ClomniChange.Typing("conv_5521", Sender(SenderType.BOT), true))
        chat.stop()
        assertTrue(source.observers.isEmpty())
        assertEquals(false, source.typingStates.last())
        assertTrue("the typing timer is cancelled", timers.pending.isEmpty())
    }

    /** "Yeni söhbət başlat": the screen moves to an empty draft at once; its first message creates it. */
    @Test
    fun startingANewConversationInPlace() {
        source.set(listOf(ChatFixture.message("24-system-conversation-closed.json")))
        val chat = controller()
        chat.load()
        source.push(ClomniChange.Typing("conv_5521", Sender(SenderType.BOT), true))
        chat.startNewConversation()
        assertEquals("draft_new", chat.conversationId)
        assertTrue(chat.screen.items.isEmpty())
        assertTrue(timers.pending.isEmpty())
        assertEquals(false, source.typingStates.last())
        source.push(ClomniChange.Messages("conv_5521"))
        assertTrue("the old conversation is not this screen's any more", chat.screen.items.isEmpty())

        // Its first message created conversation conv_new: the screen goes on there.
        source.set(listOf(ChatFixture.message("03-text-user.json")), id = "conv_new")
        source.push(ClomniChange.Started("draft_new", "conv_new"))
        assertEquals("conv_new", chat.conversationId)
        assertTrue("load conv_new" in source.calls)
        assertEquals(listOf("Gedişim bitmədi, pul çıxılmağa davam edir"), bubbleTexts(chat))
    }

    @Test
    fun theEngineIsAChatSource() {
        val source: ChatDataSource? = null as ai.clomni.messenger.core.ClomniEngine?
        assertNull(source)
    }
}
