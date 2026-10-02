package ai.clomni.messenger.core

import ai.clomni.messenger.api.ApiClient
import ai.clomni.messenger.api.ApiConfiguration
import ai.clomni.messenger.api.ClomniError
import ai.clomni.messenger.api.Credentials
import ai.clomni.messenger.api.DeviceInfo
import ai.clomni.messenger.api.MemorySecureStore
import ai.clomni.messenger.api.PushRegistration
import ai.clomni.messenger.api.SecureStore
import ai.clomni.messenger.api.SessionIdentity
import ai.clomni.messenger.api.UserIdentity
import ai.clomni.messenger.protocol.ConversationStatus
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.realtime.RealtimeClient
import ai.clomni.messenger.store.MessageStore
import ai.clomni.messenger.store.PendingMessage
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ExecutionException
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

/** The engine against [FakeMobileServer]: every edge case of brief 8·5.5 that the SDK takes part in. */
class ClomniEngineTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val fake = FakeMobileServer()
    private val phones = mutableListOf<Phone>()
    private val aysel = UserIdentity("12345", "aysel@example.com")

    /** One device: its own keys, files, engine and socket. */
    private inner class Phone(
        val vault: SecureStore = MemorySecureStore(),
        val dir: File = folder.newFolder(),
        retryMs: Long = 50,
    ) {
        val protocol = ProtocolJson()
        val credentials = Credentials(vault, protocol)
        // The SDK's own client: OkHttp does not repeat a request by itself, so every attempt is the outbox's.
        private val http = lazyOf(ApiClient.defaultClient())
        private val api = ApiClient(
            ApiConfiguration(FakeMobileServer.APP_ID, FakeMobileServer.API_KEY, fake.baseUrl, "1.0.0"),
            credentials,
            protocol,
            { DeviceInfo(credentials.deviceId, "14", "3.2.1", "1.0.0", "az-AZ", "Asia/Baku", "Pixel") },
            http,
            sleep = {},
        )
        val changes = CopyOnWriteArrayList<ClomniChange>()
        val engine = ClomniEngine(
            api,
            credentials,
            MessageStore(dir, protocol),
            protocol,
            http,
            timing = ClomniEngine.Timing(RealtimeClient.Timing(reconnectDelayMs = { 50L }), outboxRetryMs = { retryMs }),
        ).also { it.observe { change -> changes += change } }

        init {
            phones += this
        }

        val token: String? get() = credentials.session?.sessionToken

        /** The socket is open and the catch-up its `ready` started has finished. */
        fun caughtUp() {
            eventually("socket and catch-up of $token") { fake.hasSocket(token) && fake.called(token, "GET /v1/conversations") }
            engine.awaitIdle()
        }

        fun texts(conversationId: String) = engine.messages(conversationId).map { it.text }

        fun greeting(conversationId: String) = engine.messages(conversationId).first()
    }

    @After
    fun stop() {
        phones.forEach { it.engine.shutdown() }
        fake.close()
    }

    private fun <T> Future<T>.await(): T = get(10, TimeUnit.SECONDS)

    private fun rejected(action: () -> Future<*>) {
        try {
            action().await()
            fail("expected a refusal")
        } catch (e: ExecutionException) {
            assertTrue(e.cause.toString(), e.cause is ClomniError.Rejected)
        }
    }

    private fun eventually(what: String, check: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 5_000
        while (!check()) {
            if (System.currentTimeMillis() > deadline) throw AssertionError("timed out waiting for: $what")
            Thread.sleep(20)
        }
    }

    private val Message.text: String get() = (content as? MessageContent.Text)?.text ?: fallbackText

    private fun Message.button(id: String) = (content as MessageContent.QuickReplies).buttons.first { it.id == id }

    private fun sends(conversationId: String) = fake.count("POST /v1/conversations/$conversationId/messages")

    private fun frameText(frame: JsonObject): String? =
        (frame["data"] as? JsonObject)?.get("content")?.jsonObject?.get("text")?.jsonPrimitive?.content

    /** A logged-in device with a conversation open and its socket connected. */
    private fun ready(phone: Phone = Phone()): Pair<Phone, String> {
        phone.engine.loginUnidentifiedUser().await()
        phone.engine.connect().await()
        val conversation = phone.engine.startConversation("profile_support").await().id
        phone.caughtUp()
        return phone to conversation
    }

    @Test
    fun aConversationLiveOverTheSocket() {
        val (phone, conversation) = ready()
        assertEquals("Salam! Nə ilə kömək edək?", (phone.greeting(conversation).content as MessageContent.QuickReplies).text)
        fake.botSays(conversation, "Operator tezliklə qoşulacaq")
        eventually("the bot's message") { "Operator tezliklə qoşulacaq" in phone.texts(conversation) }
        assertEquals(listOf(1L, 2L), phone.engine.messages(conversation).map { it.seq })
        assertEquals(listOf(conversation), phone.engine.conversations().map { it.id })
        assertTrue(phone.changes.toString(), ClomniChange.Session in phone.changes)
        assertTrue(phone.changes.toString(), ClomniChange.Messages(conversation) in phone.changes)
    }

    @Test
    fun aButtonPressedTwiceIsSentOnce() {
        val (phone, conversation) = ready()
        val greeting = phone.greeting(conversation)
        assertTrue(phone.engine.canAnswer(greeting))
        val sent = phone.engine.reply(greeting, greeting.button("yes")).await()
        assertEquals("Bəli", sent.preview)
        // The buttons are dead at once: the second tap sends nothing.
        assertFalse(phone.engine.canAnswer(greeting))
        rejected { phone.engine.reply(greeting, greeting.button("yes")) }
        rejected { phone.engine.goBack(greeting) }
        eventually("the answer") { phone.engine.pending(conversation).isEmpty() && "Bəli" in phone.texts(conversation) }
        assertEquals(1, fake.userMessages(conversation).size)
        assertEquals(1, sends(conversation))
        eventually("the server's answered copy") { phone.greeting(conversation).flow?.interactive == false }
    }

    @Test
    fun aButtonAnsweredOnAnotherDeviceIsRefusedWith409() {
        val a = Phone()
        val b = Phone()
        a.engine.loginUser(aysel, "hash").await()
        b.engine.loginUser(aysel, "hash").await()
        a.engine.connect().await()
        b.engine.connect().await()
        val conversation = a.engine.startConversation(null).await().id
        b.engine.loadMessages(conversation).await()
        a.caughtUp()
        b.caughtUp()
        // B hears nothing for a while, so its buttons still look live.
        fake.deliver = { token, _ -> token != b.token }
        a.engine.reply(a.greeting(conversation), a.greeting(conversation).button("yes")).await()
        eventually("A's answer") { fake.userMessages(conversation).size == 1 }
        assertTrue(b.engine.canAnswer(b.greeting(conversation)))

        b.engine.reply(b.greeting(conversation), b.greeting(conversation).button("no")).await()
        eventually("B gives up its answer and reloads") {
            b.engine.pending(conversation).isEmpty() && b.greeting(conversation).flow?.interactive == false
        }
        assertEquals(listOf("Bəli"), fake.userMessages(conversation).map { it.getValue("content").jsonObject.getValue("text").jsonPrimitive.content })
        assertTrue(b.texts(conversation).toString(), "Bəli" in b.texts(conversation))
        assertFalse(b.engine.canAnswer(b.greeting(conversation)))
        assertEquals(2, sends(conversation))
    }

    @Test
    fun anOldQuestionsButtonIsRefusedAsStale() {
        val (phone, conversation) = ready()
        // A second question the device does not hear about: to it, the first still looks current.
        fake.deliver = { _, frame -> frameText(frame) != "İkinci sual" }
        fake.botSays(conversation, "İkinci sual", listOf("a" to "A", "b" to "B"))
        val first = phone.greeting(conversation)
        phone.engine.reply(first, first.button("yes")).await()
        eventually("the stale answer is dropped and the conversation reloaded") {
            phone.engine.pending(conversation).isEmpty() && phone.engine.messages(conversation).size == 2
        }
        assertEquals(emptyList<JsonObject>(), fake.userMessages(conversation))
        assertEquals(false, phone.greeting(conversation).flow?.interactive)
        assertTrue(phone.engine.canAnswer(phone.engine.messages(conversation).last()))
    }

    /** Brief: no empty conversations. Opening a new one and leaving it sends nothing; its first message creates it. */
    @Test
    fun aNewConversationIsCreatedByItsFirstMessage() {
        val phone = Phone()
        phone.engine.loginUnidentifiedUser().await()
        phone.engine.connect().await()
        phone.caughtUp()
        fun creates() = fake.log.count { it == "POST /v1/conversations" }
        val left = phone.engine.draft("profile_support")
        phone.engine.loadMessages(left).await()
        phone.engine.refreshConversation(left).await()
        phone.engine.setTyping(true, left).await()
        phone.engine.markRead(left).await()
        assertEquals("opened and left: nothing", 0, creates())
        assertTrue(fake.log.toString(), fake.log.none { "draft_" in it })

        val draft = phone.engine.draft("profile_support")
        phone.changes.clear()
        phone.engine.sendText("Salam", draft).await()
        phone.engine.sendText("Gedişim bitmədi", draft).await()
        eventually("both sent") { phone.engine.pending(draft).isEmpty() && creates() == 1 && phone.engine.conversations().isNotEmpty() }
        phone.engine.awaitIdle()
        val conversation = phone.engine.conversations().single().id
        assertEquals("one create, then the messages", 1, creates())
        assertEquals(listOf("Salam", "Gedişim bitmədi"), fake.userMessages(conversation).map { it.getValue("content").jsonObject.getValue("text").jsonPrimitive.content })
        assertTrue(phone.changes.toString(), ClomniChange.Started(draft, conversation) in phone.changes)
        // A message sent to the draft after it was created (its screen not moved yet) goes to the same conversation.
        phone.engine.sendText("Və bu", draft).await()
        eventually("the third") { fake.userMessages(conversation).size == 3 }
        assertEquals(1, creates())
    }

    /** Offline: the draft's message waits, fails, and on retry creates the conversation once. */
    @Test
    fun aDraftsFirstMessageWaitsForTheNetwork() {
        val phone = Phone()
        phone.engine.loginUnidentifiedUser().await()
        phone.engine.connect().await()
        phone.caughtUp()
        val draft = phone.engine.draft(null)
        fake.offline = true
        val sent = phone.engine.sendText("Salam", draft).await()
        eventually("failed") { phone.engine.pending(draft).singleOrNull()?.state == PendingMessage.State.FAILED }
        assertEquals("the message stays on the draft's screen", "Salam", phone.engine.pending(draft).single().preview)
        fake.offline = false
        phone.engine.retry(sent.id).await()
        eventually("sent") { phone.engine.pending(draft).isEmpty() && phone.engine.conversations().isNotEmpty() }
        phone.engine.refreshConversations().await()
        val conversation = phone.engine.conversations().single().id
        assertEquals(listOf("Salam"), fake.userMessages(conversation).map { it.getValue("content").jsonObject.getValue("text").jsonPrimitive.content })
    }

    @Test
    fun threeFailedAttemptsMakeAMessageFailedUntilRetried() {
        val (phone, conversation) = ready()
        fake.offline = true
        val sent = phone.engine.sendText("Salam", conversation).await()
        eventually("the message fails") { phone.engine.pending(conversation).singleOrNull()?.state == PendingMessage.State.FAILED }
        assertEquals(3, phone.engine.pending(conversation).single().attempts)
        assertEquals(3, sends(conversation))
        fake.offline = false
        // A failed message does not go by itself, not even after the connection is back.
        phone.engine.applicationWillEnterForeground().await()
        assertEquals(PendingMessage.State.FAILED, phone.engine.pending(conversation).single().state)

        phone.engine.retry(sent.id).await()
        eventually("the retried message") { phone.engine.pending(conversation).isEmpty() }
        assertEquals(1, fake.userMessages(conversation).size)
        assertTrue("Salam" in phone.texts(conversation))
        rejected { phone.engine.retry(sent.id) }
    }

    @Test
    fun aShortOutageIsBridgedByTheNextAttempt() {
        val (phone, conversation) = ready(Phone(retryMs = 400))
        fake.offline = true
        phone.engine.sendText("Salam", conversation).await()
        eventually("the first attempt fails") { phone.engine.pending(conversation).singleOrNull()?.attempts == 1 }
        assertEquals(PendingMessage.State.SENDING, phone.engine.pending(conversation).single().state)
        fake.offline = false
        eventually("the next attempt delivers it") { phone.engine.pending(conversation).isEmpty() }
        assertEquals(1, fake.userMessages(conversation).size)
    }

    @Test
    fun aMessageWhoseAnswerIsLostIsSentAgainAndArrivesOnce() {
        // No socket here: only the repeated send can confirm the message.
        val phone = Phone()
        phone.engine.loginUnidentifiedUser().await()
        val conversation = phone.engine.startConversation(null).await().id
        // The server stores the message, but its answer never reaches the device.
        fake.dropAnswers = 1
        val sent = phone.engine.sendText("Gedişim bitmədi", conversation).await()
        eventually("the repeated send is confirmed") { phone.engine.pending(conversation).isEmpty() }
        assertEquals(2, sends(conversation))
        assertEquals(1, fake.userMessages(conversation).size)
        assertEquals(1, phone.engine.messages(conversation).count { it.clientId == sent.id })
    }

    @Test
    fun aMessageThatComesBackOverRestAndTheSocketIsKeptOnce() {
        val (phone, conversation) = ready()
        fake.dropAnswers = 1
        val sent = phone.engine.sendText("Gedişim bitmədi", conversation).await()
        eventually("confirmed") { phone.engine.pending(conversation).isEmpty() }
        val other = phone.engine.sendText("Və ikinci", conversation).await()
        eventually("confirmed") { phone.engine.pending(conversation).isEmpty() && "Və ikinci" in phone.texts(conversation) }
        Thread.sleep(100)
        assertEquals(2, fake.userMessages(conversation).size)
        assertEquals(1, phone.engine.messages(conversation).count { it.clientId == sent.id })
        assertEquals(1, phone.engine.messages(conversation).count { it.clientId == other.id })
        assertEquals(listOf(1L, 2L, 3L), phone.engine.messages(conversation).map { it.seq })
    }

    @Test
    fun theOutboxSurvivesTheProcess() {
        val vault = MemorySecureStore()
        val dir = folder.newFolder()
        val (first, conversation) = ready(Phone(vault, dir, retryMs = 60_000))
        fake.offline = true
        first.engine.sendText("Salam", conversation).await()
        eventually("the first attempt fails") { first.engine.pending(conversation).singleOrNull()?.attempts == 1 }
        first.engine.shutdown()

        fake.offline = false
        val second = Phone(vault, dir)
        second.engine.loginUnidentifiedUser().await()
        eventually("the next run sends it") { second.engine.pending(conversation).isEmpty() && "Salam" in second.texts(conversation) }
        assertEquals(1, fake.userMessages(conversation).size)
    }

    @Test
    fun theCacheShowsBeforeTheNetworkAnswers() {
        val vault = MemorySecureStore()
        val dir = folder.newFolder()
        val (first, conversation) = ready(Phone(vault, dir))
        first.engine.shutdown()

        fake.offline = true
        val second = Phone(vault, dir)
        second.engine.awaitIdle()
        assertEquals(listOf(conversation), second.engine.conversations().map { it.id })
        assertEquals(first.texts(conversation), second.texts(conversation))
        // The stored session needs no network to log in; the first call that does fails and the cache stays.
        second.engine.loginUnidentifiedUser().await()
        try {
            second.engine.refreshConversations().await()
            fail()
        } catch (e: ExecutionException) {
            assertTrue(e.cause is ClomniError.Network)
        }
        assertEquals(listOf(conversation), second.engine.conversations().map { it.id })
    }

    @Test
    fun aDroppedSocketCatchesUpAfterReconnecting() {
        val (phone, conversation) = ready()
        fake.acceptSockets = false
        fake.closeSockets()
        fake.botSays(conversation, "Bir")
        fake.botSays(conversation, "İki")
        Thread.sleep(200)
        assertFalse("Bir" in phone.texts(conversation))
        fake.acceptSockets = true
        eventually("the missed messages") { phone.texts(conversation).containsAll(listOf("Bir", "İki")) }
        assertTrue(fake.log.toString(), fake.log.any { it.startsWith("GET /v1/conversations/$conversation/messages?after_seq=1") })
        assertEquals(listOf(1L, 2L, 3L), phone.engine.messages(conversation).map { it.seq })
    }

    @Test
    fun aGapOnTheSocketIsFilledOverRest() {
        val (phone, conversation) = ready()
        fake.deliver = { _, frame -> frameText(frame) != "İki" }
        fake.botSays(conversation, "İki")
        fake.botSays(conversation, "Üç")
        eventually("41 between 40 and 42") { phone.engine.messages(conversation).map { it.seq } == listOf(1L, 2L, 3L) }
        assertTrue(fake.log.toString(), "GET /v1/conversations/$conversation/messages?after_seq=1&limit=100" in fake.log)
        assertEquals(listOf("İki", "Üç"), phone.texts(conversation).drop(1))
    }

    @Test
    fun bothDevicesOfAUserSeeEverything() {
        val a = Phone()
        val b = Phone()
        a.engine.loginUser(aysel, "hash").await()
        b.engine.loginUser(aysel, "hash").await()
        a.engine.connect().await()
        b.engine.connect().await()
        val conversation = a.engine.startConversation(null).await().id
        b.engine.loadMessages(conversation).await()
        a.caughtUp()
        b.caughtUp()

        a.engine.reply(a.greeting(conversation), a.greeting(conversation).button("yes")).await()
        eventually("B sees the answer and dead buttons") {
            b.greeting(conversation).flow?.interactive == false && "Bəli" in b.texts(conversation)
        }
        assertFalse(b.engine.canAnswer(b.greeting(conversation)))

        // A conversation B starts reaches A, which fetches it.
        val other = b.engine.startConversation(null).await().id
        b.engine.sendText("Başqa sual", other).await()
        eventually("A learns the new conversation") {
            a.engine.conversations().any { it.id == other } && "Başqa sual" in a.texts(other)
        }
    }

    @Test
    fun anAnonymousVisitorLogsIn() {
        val phone = Phone()
        phone.engine.loginUnidentifiedUser().await()
        val conversation = phone.engine.startConversation(null).await().id
        phone.engine.sendText("Salam", conversation).await()
        eventually("sent") { phone.engine.pending(conversation).isEmpty() }
        val anonymous = phone.credentials.session!!.userId
        assertEquals(anonymous, phone.credentials.anonymousId)

        // Next launch on the same device: the stored session, no new one.
        phone.engine.loginUnidentifiedUser().await()
        assertEquals(1, fake.log.count { it == "POST /v1/mobile/sessions" })
        // Its session lost, the same device resumes the same visitor.
        phone.credentials.session = null
        phone.engine.loginUnidentifiedUser().await()
        assertEquals(anonymous, phone.credentials.session!!.userId)
        assertEquals(2, fake.log.count { it == "POST /v1/mobile/sessions" })

        // Logging in: the visitor's conversation moves to the user and stays on screen.
        phone.engine.loginUser(aysel, "hash").await()
        val user = phone.credentials.session!!.userId
        assertNotEquals(anonymous, user)
        assertEquals(user, fake.ownerOf(conversation))
        assertNull(phone.credentials.anonymousId)
        phone.engine.refreshConversations().await()
        assertEquals(listOf(conversation), phone.engine.conversations().map { it.id })
        assertTrue("Salam" in phone.texts(conversation))

        // Another user on the same device without a logout: nothing of the first one stays.
        phone.engine.loginUser(UserIdentity("67890"), null).await()
        assertEquals(emptyList<Any>(), phone.engine.conversations())
        assertEquals(emptyList<Message>(), phone.engine.messages(conversation))
    }

    @Test
    fun anEmptyTextIsNotSent() {
        val (phone, conversation) = ready()
        rejected { phone.engine.sendText("", conversation) }
        rejected { phone.engine.sendText("  \n ", conversation) }
        rejected { phone.engine.sendText("a".repeat(4_001), conversation) }
        assertEquals(emptyList<PendingMessage>(), phone.engine.pending(conversation))
        assertEquals(0, sends(conversation))

        assertEquals("Salam", phone.engine.sendText("  Salam  ", conversation).await().preview)
        eventually("sent") { "Salam" in phone.texts(conversation) }
    }

    @Test
    fun expiredTokensAreRefreshed() {
        val (phone, conversation) = ready()
        val refresh = "POST /v1/mobile/sessions/refresh"
        fake.expireSessions()
        // REST: 401 token_expired, one refresh, and the send goes through.
        phone.engine.sendText("Salam", conversation).await()
        eventually("sent after a refresh") { phone.engine.pending(conversation).isEmpty() }
        assertEquals(1, fake.count(refresh))

        // The socket: an expired token is refused at the handshake, refreshed, and the socket comes back.
        fake.expireSessions()
        fake.closeSockets()
        eventually("the socket with a fresh token") { fake.count(refresh) == 2 && fake.hasSocket(phone.token) }
    }

    @Test
    fun theStoredSessionIsReusedForTheSamePerson() {
        val phone = Phone()
        val sessions = { fake.log.count { it == "POST /v1/mobile/sessions" } }
        phone.engine.loginUser(aysel, "hash").await()
        phone.engine.loginUser(aysel.copy(name = "Aysel"), "new-hash").await()
        assertEquals(1, sessions())
        assertEquals(
            SessionIdentity.User(aysel.copy(name = "Aysel"), "new-hash"),
            phone.credentials.identity,
        )
        // Expired: reused all the same, and refreshed on its first call.
        fake.expireSessions()
        phone.engine.loginUser(aysel, "new-hash").await()
        phone.engine.refreshConversations().await()
        assertEquals(1, sessions())
        assertEquals(1, fake.count("POST /v1/mobile/sessions/refresh"))
        // Another person, or an anonymous visitor: a new session.
        phone.engine.loginUser(UserIdentity(email = "leyla@example.com"), null).await()
        phone.engine.loginUnidentifiedUser().await()
        assertEquals(3, sessions())
    }

    @Test
    fun aRefusedRefreshLogsInAgain() {
        val phone = Phone()
        phone.engine.loginUser(aysel, "hash").await()
        val conversation = phone.engine.startConversation(null).await().id
        // The server forgot every token: the call is refused, the stored identity logs in again, the call is repeated.
        fake.forgetSessions()
        phone.engine.sendText("Salam", conversation).await()
        eventually("sent after a new login") { phone.engine.pending(conversation).isEmpty() }
        assertEquals(2, fake.log.count { it == "POST /v1/mobile/sessions" })
        assertEquals(1, fake.userMessages(conversation).size)
    }

    @Test
    fun logoutLeavesNothing() {
        val (phone, conversation) = ready()
        fake.offline = true
        phone.engine.sendText("Göndərilməyəcək", conversation).await()
        eventually("failed") { phone.engine.pending(conversation).singleOrNull()?.state == PendingMessage.State.FAILED }
        fake.offline = false
        val deviceId = phone.credentials.deviceId
        val token = phone.token

        phone.engine.logout().await()
        assertEquals(emptyList<Any>(), phone.engine.conversations())
        assertEquals(emptyList<Message>(), phone.engine.messages(conversation))
        assertEquals(emptyList<PendingMessage>(), phone.engine.pending(conversation))
        assertNull(phone.credentials.session)
        assertNull(phone.credentials.identity)
        assertEquals(deviceId, phone.credentials.deviceId)
        assertFalse(phone.engine.isLoggedIn)
        assertTrue("DELETE /v1/mobile/sessions" in fake.log)
        assertEquals(emptyList<String>(), phone.dir.list()!!.toList())
        eventually("the socket closed") { !fake.hasSocket(token) }
        assertTrue(ClomniChange.Session in phone.changes)
    }

    @Test
    fun configIsCheckedWithItsETag() {
        val phone = Phone()
        phone.engine.loginUnidentifiedUser().await()
        phone.changes.clear()
        assertEquals("Apar", phone.engine.refreshConfig().await()?.brand?.name)
        assertEquals("Apar", phone.engine.refreshConfig("az").await()?.brand?.name)
        assertEquals(listOf("GET /v1/mobile/config", "GET /v1/mobile/config?lang=az"), fake.log.filter { it.startsWith("GET /v1/mobile/config") })
        assertEquals(1, phone.changes.count { it == ClomniChange.Config })
        assertEquals("Apar", phone.engine.config?.brand?.name)
    }

    /** config.changed refetches the config in the language it was asked in, not in the server's default. */
    @Test
    fun configChangedKeepsTheLanguage() {
        val (phone, _) = ready()
        phone.engine.refreshConfig("ru").await()
        fake.configChanged()
        eventually("the refetch") { fake.count("GET /v1/mobile/config") == 2 }
        assertEquals(
            listOf("GET /v1/mobile/config?lang=ru", "GET /v1/mobile/config?lang=ru"),
            fake.log.filter { it.startsWith("GET /v1/mobile/config") },
        )
    }

    @Test
    fun readReceiptsAndTypingAreNotRepeated() {
        val (phone, conversation) = ready()
        phone.engine.markRead(conversation).await()
        phone.engine.markRead(conversation).await()
        phone.engine.setTyping(true, conversation).await()
        phone.engine.setTyping(true, conversation).await()
        phone.engine.setTyping(false, conversation).await()
        phone.engine.setTyping(false, conversation).await()
        assertEquals(1, fake.count("POST /v1/conversations/$conversation/read"))
        assertEquals(2, fake.count("POST /v1/conversations/$conversation/typing"))
        phone.engine.markRead("conv_unknown").await()
    }

    @Test
    fun severalScreensHearEveryChange() {
        val (phone, conversation) = ready()
        val badge = CopyOnWriteArrayList<ClomniChange>()
        val token = phone.engine.observe { badge += it }
        phone.engine.sendText("Salam", conversation).await()
        eventually("both hear the message") {
            ClomniChange.Messages(conversation) in badge && ClomniChange.Messages(conversation) in phone.changes
        }
        phone.engine.stopObserving(token)
        phone.engine.awaitIdle()
        badge.clear()
        phone.changes.clear()
        phone.engine.sendText("Yenə", conversation).await()
        eventually("the first still hears") { ClomniChange.Messages(conversation) in phone.changes }
        phone.engine.awaitIdle()
        assertTrue("stopped listening", badge.isEmpty())
    }

    /** A file is kept on the device, uploaded, then sent as an attachment; the staged copy goes once the server has it. */
    @Test
    fun aFileIsUploadedThenSent() {
        val (phone, conversation) = ready()
        fake.drops["POST /v1/uploads"] = 1
        val data = ByteArray(2_000) { 7 }
        val pending = phone.engine.sendFile(data, "velo.jpg", "image/jpeg", "Velosiped", conversation).await()
        assertEquals("velo.jpg", pending.upload?.fileName)
        assertEquals(2_000L, pending.upload?.size)
        val local = phone.engine.localFile(pending)!!
        assertTrue(local.readBytes().contentEquals(data))

        eventually("sent") { phone.engine.pending(conversation).isEmpty() }
        assertEquals("the upload is repeated like a message", 2, fake.count("POST /v1/uploads"))
        val body = fake.sentBodies.last()
        assertEquals(pending.id, body.getValue("client_id").jsonPrimitive.content)
        assertEquals("attachment", body.getValue("type").jsonPrimitive.content)
        val content = body.getValue("content").jsonObject
        assertTrue(content.getValue("upload_id").jsonPrimitive.content.startsWith("upl_"))
        assertEquals("Velosiped", content.getValue("caption").jsonPrimitive.content)
        assertFalse("the staged copy is gone", local.exists())
        assertEquals(1, fake.userMessages(conversation).size)
    }

    /** Uploaded but not yet sent when the app closed: the next run sends the message without uploading again. */
    @Test
    fun anUploadedFileIsNotUploadedAgainAfterARestart() {
        val vault = MemorySecureStore()
        val dir = folder.newFolder()
        val (before, conversation) = ready(Phone(vault, dir, retryMs = 60_000))
        fake.drops["POST /v1/conversations/$conversation/messages"] = 1
        val pending = before.engine.sendFile("pdf".toByteArray(), "qaime.pdf", "application/pdf", null, conversation).await()
        eventually("the send fails once") { before.engine.pending(conversation).singleOrNull()?.attempts == 1 }
        val uploaded = before.engine.pending(conversation).single().upload?.uploadId
        assertTrue(uploaded.orEmpty().startsWith("upl_"))
        before.engine.shutdown()

        val after = Phone(vault, dir)
        after.engine.awaitIdle()
        assertEquals(listOf(pending.id), after.engine.pending(conversation).map { it.id })
        assertEquals(uploaded, after.engine.pending(conversation).single().upload?.uploadId)
        after.engine.loginUnidentifiedUser().await()
        eventually("the next run sends it") { after.engine.pending(conversation).isEmpty() }
        assertEquals(1, fake.count("POST /v1/uploads"))
        assertEquals(uploaded, fake.sentBodies.last().getValue("content").jsonObject.getValue("upload_id").jsonPrimitive.content)
        assertEquals(1, fake.userMessages(conversation).size)
    }

    @Test
    fun filesOverTheLimitAreRefused() {
        val (phone, conversation) = ready()
        try {
            phone.engine.sendFile(ByteArray(10 * 1_048_576 + 1), "big.jpg", "image/jpeg", null, conversation).await()
            fail("over the 10 MB image limit")
        } catch (e: ExecutionException) {
            assertEquals("file over 10 MB", (e.cause as ClomniError.Rejected).message)
        }
        fake.offline = true
        val pdf = phone.engine.sendFile(ByteArray(12 * 1_048_576), "big.pdf", "application/pdf", null, conversation).await()
        assertEquals("other files may be up to 25 MB", "application/pdf", pdf.upload?.mime)
        val staged = phone.engine.localFile(pdf)!!
        assertTrue(staged.exists())
        phone.engine.discard(pdf.id).await()
        assertFalse("discarding deletes it", staged.exists())
        assertTrue(phone.engine.pending(conversation).isEmpty())
    }

    /** The staged file disappeared (storage cleared): the message fails for good instead of retrying forever. */
    @Test
    fun aFileThatIsGoneFails() {
        val (phone, conversation) = ready(Phone(retryMs = 60_000))
        fake.offline = true
        val pending = phone.engine.sendFile("x".toByteArray(), "a.txt", "text/plain", null, conversation).await()
        eventually("first attempt") { phone.engine.pending(conversation).singleOrNull()?.attempts == 1 }
        phone.engine.localFile(pending)!!.delete()
        fake.offline = false
        // The next attempt, without waiting for the pause.
        phone.engine.applicationWillEnterForeground().await()
        eventually("failed") { phone.engine.pending(conversation).singleOrNull()?.state == PendingMessage.State.FAILED }
        assertEquals("file_missing", phone.engine.pending(conversation).single().errorCode)
        assertEquals("only the offline attempt reached for the server", 1, fake.count("POST /v1/uploads"))
    }

    @Test
    fun aConversationOpenedFromAPush() {
        val other = Phone()
        other.engine.loginUser(aysel, "hash").await()
        val conversation = other.engine.startConversation(null).await().id
        val phone = Phone()
        phone.engine.loginUser(aysel, "hash").await()
        assertNull(phone.engine.conversation(conversation))
        phone.engine.refreshConversation(conversation).await()
        assertEquals(ConversationStatus.BOT, phone.engine.conversation(conversation)?.status)
        assertTrue(ClomniChange.Conversations in phone.changes)
    }

    // Push token (brief 8·12: onNewToken → setDeviceToken)

    private fun registrations() = fake.count("POST /v1/devices")

    private fun userOf(phone: Phone) = phone.credentials.session!!.userId

    @Test
    fun theTokenWaitsForALogin() {
        val phone = Phone()
        phone.engine.setDeviceToken("tok_a").await()
        assertEquals(0, registrations())
        phone.engine.loginUser(aysel, "hash").await()
        assertEquals("tok_a", fake.pushTarget(userOf(phone)))
        val body = kotlinx.serialization.json.Json.parseToJsonElement(
            fake.sentDeviceBodies.last(),
        ).jsonObject
        assertEquals(
            mapOf("token" to "tok_a", "provider" to "fcm", "environment" to "production"),
            body.mapValues { it.value.jsonPrimitive.content },
        )
    }

    @Test
    fun theSameTokenIsSentOnce() {
        val vault = MemorySecureStore()
        val dir = folder.newFolder()
        val phone = Phone(vault, dir)
        phone.engine.loginUser(aysel, "hash").await()
        phone.engine.setDeviceToken("tok_a").await()
        assertEquals(1, registrations())
        // FCM hands the app its token at every start; foreground and connect look too.
        phone.engine.setDeviceToken("tok_a").await()
        phone.engine.applicationWillEnterForeground().await()
        phone.engine.connect().await()
        phone.engine.disconnect().await()
        assertEquals(1, registrations())
        phone.engine.shutdown()

        // The next run reuses the session, and the registration with it.
        val again = Phone(vault, dir)
        again.engine.loginUser(aysel, "hash").await()
        again.engine.setDeviceToken("tok_a").await()
        assertEquals(1, registrations())
        assertEquals("tok_a", fake.pushTarget(userOf(again)))
    }

    @Test
    fun aNewTokenIsSentAgain() {
        val phone = Phone()
        phone.engine.loginUnidentifiedUser().await()
        phone.engine.setDeviceToken("tok_a").await()
        phone.engine.setDeviceToken("tok_b").await()
        assertEquals("tok_b", fake.pushTarget(userOf(phone)))
        assertEquals(2, registrations())
    }

    @Test
    fun anotherUserGetsTheTokenAtLogin() {
        val phone = Phone()
        phone.engine.loginUnidentifiedUser().await()
        val visitor = userOf(phone)
        phone.engine.setDeviceToken("tok_a").await()
        assertEquals("tok_a", fake.pushTarget(visitor))

        // The visitor logs in: the conversations and the pushes move to the user.
        phone.engine.loginUser(aysel, "hash").await()
        val user = userOf(phone)
        assertEquals("tok_a", fake.pushTarget(user))
        assertNull(fake.pushTarget(visitor))

        // Someone else logs in on the same phone.
        phone.engine.loginUser(UserIdentity("67890"), "hash").await()
        assertEquals("tok_a", fake.pushTarget(userOf(phone)))
        assertNull(fake.pushTarget(user))
        assertEquals(3, registrations())
    }

    @Test
    fun logoutStopsPushesUntilTheNextLogin() {
        val phone = Phone()
        phone.engine.loginUser(aysel, "hash").await()
        val user = userOf(phone)
        phone.engine.setDeviceToken("tok_a").await()
        phone.engine.logout().await()
        assertNull(fake.pushTarget(user))
        phone.engine.applicationWillEnterForeground().await()
        assertEquals("nobody to register for", 1, registrations())

        // The token stays on the device: the same user is registered again.
        phone.engine.loginUser(aysel, "hash").await()
        assertEquals("tok_a", fake.pushTarget(userOf(phone)))
        assertEquals(2, registrations())
    }

    @Test
    fun aFailedRegistrationIsRepeatedLater() {
        val phone = Phone()
        phone.engine.loginUser(aysel, "hash").await()
        val user = userOf(phone)
        fake.drops["POST /v1/devices"] = 1
        phone.engine.setDeviceToken("tok_a").await()
        assertNull(fake.pushTarget(user))
        phone.engine.applicationWillEnterForeground().await()
        assertEquals("tok_a", fake.pushTarget(user))

        // Refused the same way, and repeated at the next connect.
        fake.refusals["POST /v1/devices"] = 400
        phone.engine.setDeviceToken("tok_b").await()
        assertEquals("tok_a", fake.pushTarget(user))
        phone.engine.connect().await()
        assertEquals("tok_b", fake.pushTarget(user))
    }

    /** A new token, or a logout, that comes while a registration is out waits for it and then wins. */
    @Test
    fun whatComesDuringTheRequestFollowsIt() {
        val phone = Phone()
        phone.engine.loginUser(aysel, "hash").await()
        val user = userOf(phone)
        val hold = java.util.concurrent.CountDownLatch(1)
        fake.holdDevices = hold
        val first = phone.engine.setDeviceToken("tok_a")
        eventually("the registration is out") { registrations() == 1 }
        val second = phone.engine.setDeviceToken("tok_b")
        hold.countDown()
        first.await()
        second.await()
        assertEquals("tok_b", fake.pushTarget(user))
        assertEquals(PushRegistration("tok_b", user), phone.credentials.pushRegistration)

        val again = java.util.concurrent.CountDownLatch(1)
        fake.holdDevices = again
        val third = phone.engine.setDeviceToken("tok_c")
        eventually("the third is out") { registrations() == 3 }
        val logout = phone.engine.logout()
        again.countDown()
        third.await()
        logout.await()
        assertNull("the logout came after: the server has no token for anyone", fake.pushTarget(user))
        assertEquals(PushRegistration("tok_c", null), phone.credentials.pushRegistration)
    }

    @Test
    fun theOtherWaysToAnswerAndSend() {
        val (phone, conversation) = ready()
        val greeting = phone.greeting(conversation)
        rejected { phone.engine.goBack(greeting) }
        rejected { phone.engine.submitForm(greeting, emptyMap()) }
        rejected { phone.engine.submitRating(greeting, 5, null) }

        val file = folder.newFile("velo.jpg").apply { writeText("jpeg") }
        val upload = phone.engine.upload(file, "velo.jpg", "image/jpeg").await()
        val attachment = phone.engine.sendAttachment(upload.uploadId, "Velosiped", conversation).await()
        assertEquals("Velosiped", attachment.preview)
        eventually("the attachment") { phone.engine.pending(conversation).isEmpty() }

        assertNull(phone.engine.startFlow("payment_failed", null, openMessenger = true, openedFrom = null).await())
        phone.engine.track("ride_finished", JsonObject(mapOf("minutes" to JsonPrimitive(18)))).await()
        assertEquals("Aysel", phone.engine.updateUser(JsonObject(mapOf("name" to JsonPrimitive("Aysel")))).await().name)
        phone.engine.setDeviceToken("fcm-token").await()
        assertEquals(
            listOf("POST /v1/uploads", "POST /v1/flows/trigger", "POST /v1/events", "PATCH /v1/users/me", "POST /v1/devices"),
            fake.log.filter { it.startsWith("POST /v1/uploads") || it.contains("/flows/") || it.contains("/events") || it.contains("/users/") || it.contains("/devices") },
        )

        phone.engine.discard("nothing").await()
        assertEquals(false, phone.engine.loadOlder(conversation).await())
        assertFalse(phone.engine.isAppDisabled)
    }
}
