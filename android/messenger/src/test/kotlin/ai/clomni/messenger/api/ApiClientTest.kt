package ai.clomni.messenger.api

import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.MobileSession
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.ServerError
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ApiClientTest {

    private val server = MockWebServer()
    private val credentials = Credentials(MemorySecureStore(), ProtocolJson())
    private val sleeps = Collections.synchronizedList(mutableListOf<Long>())
    private var device = DeviceInfo("d_7f3e", "14", "3.2.1", "1.0.0", "az-AZ", "Asia/Baku", "SM-A546")
    private var now = 0L
    private val api = ApiClient(
        config = ApiConfiguration("app_8x2k", "android_sdk-3f9", server.url("/v1").toString(), "1.0.0"),
        credentials = credentials,
        protocol = ProtocolJson(),
        device = { device },
        sleep = { sleeps += it },
        clock = { now },
    )

    @After
    fun stop() = server.shutdown()

    private fun session(n: Int) = """{"session_token":"st_$n","expires_at":"2026-10-02T10:30:00Z","refresh_token":"rt_$n",
        "user":{"id":"usr_1","anonymous":false,"language":"az"},"ws_url":"wss://app.clomni.ai/v1/realtime"}"""

    private fun error(status: Int, code: String) =
        MockResponse().setResponseCode(status).setBody("""{"error":{"code":"$code","message":"m","request_id":"req_1"}}""")

    private fun json(body: String, status: Int = 200) = MockResponse().setResponseCode(status).setBody(body)

    private fun loggedIn(n: Int = 1) {
        credentials.session = ProtocolJson().parseSession(session(n))
    }

    private fun RecordedRequest.json(): JsonObject = Json.parseToJsonElement(body.readUtf8()).jsonObject

    private val messagePage = """{"messages":[],"has_more":false}"""

    @Test
    fun sessionIsOpenedWithTheAppKeys() {
        server.enqueue(json(session(1), 201))
        credentials.anonymousId = "usr_anon"
        val identity = SessionIdentity.User(UserIdentity("12345", "aysel@example.com"), "9b1c")
        val opened = api.open(identity)
        assertEquals("st_1", opened.sessionToken)
        assertEquals(opened, credentials.session)
        assertEquals(identity, credentials.identity)
        // Merged into the identified user: nothing anonymous is left to resume.
        assertNull(credentials.anonymousId)

        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/v1/mobile/sessions", request.path)
        assertEquals("app_8x2k", request.getHeader("X-Clomni-App-Id"))
        assertEquals("android_sdk-3f9", request.getHeader("X-Clomni-Api-Key"))
        assertEquals("android/1.0.0", request.getHeader("X-Clomni-SDK"))
        assertNull(request.getHeader("Authorization"))
        assertEquals(
            Json.parseToJsonElement(
                """{"user":{"user_id":"12345","email":"aysel@example.com","phone":null,"name":null,"user_hash":"9b1c"},
                   "anonymous_id":"usr_anon",
                   "device":{"device_id":"d_7f3e","platform":"android","os_version":"14","app_version":"3.2.1","sdk_version":"1.0.0",
                             "locale":"az-AZ","timezone":"Asia/Baku","model":"SM-A546"}}""",
            ),
            request.json(),
        )
    }

    @Test
    fun anonymousSessionSendsNoUserAndKeepsTheAnonymousId() {
        server.enqueue(json(session(1).replace("\"anonymous\":false", "\"anonymous\":true"), 201))
        device = device.copy(osVersion = null, model = null)
        api.open(SessionIdentity.Anonymous)
        val body = server.takeRequest().json()
        assertEquals(setOf("device"), body.keys)
        assertEquals(setOf("device_id", "platform", "app_version", "sdk_version", "locale", "timezone"), body.getValue("device").jsonObject.keys)
        assertEquals("usr_1", credentials.anonymousId)
        assertEquals(SessionIdentity.Anonymous, credentials.identity)
    }

    @Test
    fun aSessionAboutToExpireIsRenewedFirst() {
        loggedIn()
        // expires_at is 2026-10-02T10:30:00Z; 30 s before it, the token is renewed before use.
        now = java.time.Instant.parse("2026-10-02T10:29:30Z").toEpochMilli()
        server.enqueue(json(session(2), 201))
        server.enqueue(json(messagePage))
        api.listMessages("conv_1")
        assertEquals("/v1/mobile/sessions/refresh", server.takeRequest().path)
        assertEquals("Bearer st_2", server.takeRequest().getHeader("Authorization"))
    }

    @Test
    fun otherCallsUseTheSessionToken() {
        loggedIn()
        server.enqueue(json(messagePage))
        api.listMessages("conv 1/x", afterSeq = 40, limit = 50)
        val request = server.takeRequest()
        assertEquals("/v1/conversations/conv%201%2Fx/messages?after_seq=40&limit=50", request.path)
        assertEquals("Bearer st_1", request.getHeader("Authorization"))
        assertEquals("android/1.0.0", request.getHeader("X-Clomni-SDK"))
        assertNull(request.getHeader("X-Clomni-Api-Key"))
    }

    @Test
    fun noSessionIsAnError() {
        try {
            api.getUser()
            fail()
        } catch (e: ClomniError.NotLoggedIn) {
            // Log in first.
        }
        try {
            api.refreshSession()
            fail()
        } catch (e: ClomniError.NotLoggedIn) {
            // Nothing to refresh.
        }
        assertEquals(0, server.requestCount)
    }

    @Test
    fun expiredTokenIsRefreshedAndTheCallRepeatedOnce() {
        loggedIn()
        server.enqueue(error(401, "token_expired"))
        server.enqueue(json(session(2), 201))
        server.enqueue(json(messagePage))
        api.listMessages("conv_1")

        assertEquals("Bearer st_1", server.takeRequest().getHeader("Authorization"))
        val refresh = server.takeRequest()
        assertEquals("/v1/mobile/sessions/refresh", refresh.path)
        assertEquals("app_8x2k", refresh.getHeader("X-Clomni-App-Id"))
        assertEquals("""{"refresh_token":"rt_1"}""", refresh.body.readUtf8())
        assertEquals("Bearer st_2", server.takeRequest().getHeader("Authorization"))
        assertEquals("rt_2", credentials.session?.refreshToken)
    }

    @Test
    fun aSecondExpiryIsNotRefreshedAgain() {
        loggedIn()
        server.enqueue(error(401, "token_expired"))
        server.enqueue(json(session(2), 201))
        server.enqueue(error(401, "token_expired"))
        try {
            api.getUser()
            fail()
        } catch (e: ClomniError.Server) {
            assertEquals("token_expired", e.code)
        }
        assertEquals(3, server.requestCount)
    }

    @Test
    fun refusedRefreshForgetsTheSession() {
        loggedIn()
        server.enqueue(error(401, "token_expired"))
        server.enqueue(error(401, "invalid_token"))
        try {
            api.getUser()
            fail()
        } catch (e: ClomniError.Server) {
            assertEquals("invalid_token", e.code)
        }
        assertNull(credentials.session)
    }

    @Test
    fun otherUnauthorizedCodesAreNotRefreshed() {
        loggedIn()
        server.enqueue(error(401, "invalid_token"))
        try {
            api.getUser()
            fail()
        } catch (e: ClomniError.Server) {
            assertEquals(401, e.status)
        }
        assertEquals(1, server.requestCount)
    }

    @Test
    fun concurrentExpiriesRefreshOnce() {
        loggedIn()
        var refreshes = 0
        val bothExpired = CountDownLatch(2)
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path == "/v1/mobile/sessions/refresh" -> synchronized(this) {
                    refreshes++
                    // The refresh token is single-use: only rt_1 works, once.
                    if (refreshes == 1 && request.body.readUtf8().contains("rt_1")) json(session(2), 201) else error(401, "invalid_token")
                }
                request.getHeader("Authorization") == "Bearer st_2" -> json(messagePage)
                else -> {
                    // Both calls hold an expired token before either answer arrives.
                    bothExpired.countDown()
                    bothExpired.await(5, TimeUnit.SECONDS)
                    error(401, "token_expired")
                }
            }
        }
        val pool = Executors.newFixedThreadPool(2)
        val calls = List(2) {
            pool.submit {
                api.listMessages("conv_1")
            }
        }
        calls.forEach { it.get(10, TimeUnit.SECONDS) }
        pool.shutdown()
        assertEquals(1, refreshes)
        assertEquals("st_2", credentials.session?.sessionToken)
    }

    @Test
    fun rateLimitWaitsRetryAfter() {
        loggedIn()
        server.enqueue(error(429, "rate_limited").setHeader("Retry-After", "7"))
        server.enqueue(error(429, "rate_limited").setHeader("Retry-After", "soon"))
        server.enqueue(json(messagePage))
        api.listMessages("conv_1")
        assertEquals(listOf(7_000L, 1_000L), sleeps)
    }

    @Test
    fun rateLimitGivesUpAfterThreeWaits() {
        loggedIn()
        repeat(4) { server.enqueue(error(429, "rate_limited").setHeader("Retry-After", "2")) }
        try {
            api.listMessages("conv_1")
            fail()
        } catch (e: ClomniError.Server) {
            assertEquals("rate_limited", e.code)
        }
        assertEquals(listOf(2_000L, 2_000L, 2_000L), sleeps)
    }

    @Test
    fun serverErrorsBackOffExponentiallyAtMostThreeTimes() {
        loggedIn()
        repeat(4) { server.enqueue(error(503, "internal")) }
        try {
            api.getUser()
            fail()
        } catch (e: ClomniError.Server) {
            assertEquals(503, e.status)
        }
        assertEquals(listOf(1_000L, 2_000L, 4_000L), sleeps)
        assertEquals(4, server.requestCount)

        sleeps.clear()
        server.enqueue(MockResponse().setResponseCode(502).setBody("<html>Bad gateway</html>"))
        server.enqueue(json("""{"id":"usr_1","anonymous":false}"""))
        assertEquals("usr_1", api.getUser().id)
        assertEquals(listOf(1_000L), sleeps)
    }

    @Test
    fun errorBodiesAreRead() {
        loggedIn()
        server.enqueue(
            json(
                """{"error":{"code":"validation_failed","message":"phone is invalid","request_id":"req_9","fields":{"phone":"invalid"}}}""",
                400,
            ),
        )
        try {
            api.sendMessage("conv_1", ClientMessage.Text("a"))
            fail()
        } catch (e: ClomniError.Server) {
            assertEquals(ServerError("validation_failed", "phone is invalid", "req_9", mapOf("phone" to "invalid")), e.error)
        }
        server.enqueue(MockResponse().setResponseCode(404).setBody("Not Found"))
        try {
            api.getConversation("conv_1")
            fail()
        } catch (e: ClomniError.Server) {
            assertEquals(404, e.status)
            assertNull(e.error)
        }
    }

    @Test
    fun configUsesItsETag() {
        loggedIn()
        server.enqueue(json("""{"brand":{"name":"Apar","primary_color":"#1F9D63"}}""").setHeader("ETag", "W/\"7f3a\""))
        server.enqueue(MockResponse().setResponseCode(304))
        val first = api.getConfig("az", null) as ConfigResponse.Changed
        assertEquals("Apar", first.config.brand.name)
        assertEquals("W/\"7f3a\"", first.etag)
        assertEquals(ConfigResponse.NotModified, api.getConfig("az", first.etag))
        assertNull(server.takeRequest().getHeader("If-None-Match"))
        val second = server.takeRequest()
        assertEquals("/v1/mobile/config?lang=az", second.path)
        assertEquals("W/\"7f3a\"", second.getHeader("If-None-Match"))
    }

    @Test
    fun sendMessageCarriesTheClientMessage() {
        loggedIn()
        val message = ClientMessage.ButtonReply("msg_f09", "o_s", "node:S", "9a8b")
        server.enqueue(json(MESSAGE, 201))
        assertEquals("msg_u1", api.sendMessage("conv_5521", message).id)
        val request = server.takeRequest()
        assertEquals("/v1/conversations/conv_5521/messages", request.path)
        assertEquals(Json.parseToJsonElement(ProtocolJson().encode(message)), request.json())
    }

    @Test
    fun theRestOfTheApi() {
        loggedIn()
        val conversation = """{"id":"conv_1","status":"bot","assignee":null,"unread_count":0,"last_message":null,"created_at":"2026-10-01T10:30:00Z"}"""
        server.enqueue(json("""{"conversations":[$conversation],"next_cursor":null}"""))
        server.enqueue(json("""{"conversation":$conversation,"messages":[]}""", 201))
        server.enqueue(json(conversation))
        server.enqueue(MockResponse().setResponseCode(204))
        server.enqueue(MockResponse().setResponseCode(204))
        server.enqueue(json("""{"id":"usr_1","anonymous":false,"name":"Aysel"}"""))
        server.enqueue(MockResponse().setResponseCode(204))
        server.enqueue(MockResponse().setResponseCode(204))
        server.enqueue(json("""{"started":false,"conversation":null}"""))
        server.enqueue(MockResponse().setResponseCode(202))
        server.enqueue(json("""{"upload_id":"upl_1","url":"https://x/a.jpg","name":"a.jpg","size":3,"mime":"image/jpeg"}""", 201))
        server.enqueue(MockResponse().setResponseCode(204))

        assertEquals(listOf("conv_1"), api.listConversations(limit = 20, cursor = "c1").conversations.map { it.id })
        assertEquals("conv_1", api.createConversation("profile_support").conversation.id)
        assertEquals("conv_1", api.getConversation("conv_1").id)
        api.markRead("conv_1", 12)
        api.setTyping("conv_1", true)
        assertEquals("Aysel", api.updateUser(Json.parseToJsonElement("""{"name":"Aysel"}""").jsonObject).name)
        api.registerDevice("tok")
        runCatching { api.getConversation("conv/1") }
        assertEquals(false, api.triggerFlow("payment_failed", null, openMessenger = true, openedFrom = "checkout").started)
        api.trackEvent("ride_finished", null)
        val file = File.createTempFile("upload", ".jpg").apply { writeText("abc") }
        assertEquals("upl_1", api.upload(file, "a.jpg", "image/jpeg").uploadId)
        api.logout()

        val requests = List(12) { server.takeRequest() }
        assertEquals(
            listOf(
                "GET /v1/conversations?limit=20&cursor=c1",
                "POST /v1/conversations",
                "GET /v1/conversations/conv_1",
                "POST /v1/conversations/conv_1/read",
                "POST /v1/conversations/conv_1/typing",
                "PATCH /v1/users/me",
                "POST /v1/devices",
                "GET /v1/conversations/conv%2F1",
                "POST /v1/flows/trigger",
                "POST /v1/events",
                "POST /v1/uploads",
                "DELETE /v1/mobile/sessions",
            ),
            requests.map { "${it.method} ${it.path}" },
        )
        assertEquals("""{"opened_from":"profile_support"}""", requests[1].body.readUtf8())
        assertEquals("""{"up_to_seq":12}""", requests[3].body.readUtf8())
        assertEquals("""{"state":"on"}""", requests[4].body.readUtf8())
        assertEquals("""{"token":"tok","provider":"fcm","environment":"production"}""", requests[6].body.readUtf8())
        assertEquals("""{"event":"payment_failed","open_messenger":true,"opened_from":"checkout"}""", requests[8].body.readUtf8())
        assertTrue(requests[10].getHeader("Content-Type")!!.startsWith("multipart/form-data"))
        assertNull(credentials.session)
    }

    @Test
    fun socketRefreshUsesTheSameSingleUseToken() {
        loggedIn()
        server.enqueue(json(session(2), 201))
        api.refreshSession()
        assertEquals("""{"refresh_token":"rt_1"}""", server.takeRequest().body.readUtf8())
        assertEquals("st_2", credentials.session?.sessionToken)
    }

    @Test
    fun noAnswerIsANetworkError() {
        loggedIn()
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST))
        try {
            api.sendMessage("conv_1", ClientMessage.Text("a"))
            fail()
        } catch (e: ClomniError.Network) {
            // The outbox repeats it with the same client_id.
        }
        server.enqueue(json("""{"id":"msg_1"}""", 201))
        try {
            api.sendMessage("conv_1", ClientMessage.Text("a"))
            fail()
        } catch (e: ClomniError.UnreadableResponse) {
            assertTrue(e.message!!.contains("unreadable"))
        }
    }

    @Test
    fun logoutForgetsEverythingButTheDeviceEvenOffline() {
        loggedIn()
        credentials.identity = SessionIdentity.Anonymous
        credentials.anonymousId = "usr_1"
        val deviceId = credentials.deviceId
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START))
        api.logout()
        assertNull(credentials.session)
        assertNull(credentials.identity)
        assertNull(credentials.anonymousId)
        assertEquals(deviceId, credentials.deviceId)
        // Without a session there is nothing to end on the server.
        api.logout()
    }

    private companion object {
        const val MESSAGE = """{"id":"msg_u1","client_id":"9a8b","conversation_id":"conv_5521","type":"text","sender":{"type":"user"},
            "created_at":"2026-10-01T10:31:00Z","seq":9,"lang":"az","content":{"text":"Aktiv gediş"},"fallback_text":"Aktiv gediş"}"""
    }
}

class CredentialsTest {

    private val store = MemorySecureStore()

    @Test
    fun keptAcrossInstancesAndClearedOnLogout() {
        val credentials = Credentials(store, ProtocolJson())
        val session = MobileSession("st_1", 1_000L, "rt_1", "usr_1", true, null, "wss://x/v1/realtime")
        val identity = SessionIdentity.User(UserIdentity("12345", "aysel@example.com", "+99450", "Aysel"), "9b1c")
        credentials.session = session
        credentials.identity = identity
        credentials.anonymousId = "usr_anon"
        val deviceId = credentials.deviceId
        assertTrue(deviceId.startsWith("d_"))

        val again = Credentials(store, ProtocolJson())
        assertEquals(session, again.session)
        assertEquals(identity, again.identity)
        assertEquals("usr_anon", again.anonymousId)
        assertEquals(deviceId, again.deviceId)

        again.clear()
        val afterLogout = Credentials(store, ProtocolJson())
        assertNull(afterLogout.session)
        assertNull(afterLogout.identity)
        assertNull(afterLogout.anonymousId)
        assertEquals(deviceId, afterLogout.deviceId)

        afterLogout.identity = SessionIdentity.Anonymous
        assertEquals(SessionIdentity.Anonymous, Credentials(store, ProtocolJson()).identity)
        afterLogout.identity = SessionIdentity.User(UserIdentity(email = "a@x.az"), null)
        assertEquals(SessionIdentity.User(UserIdentity(email = "a@x.az"), null), Credentials(store, ProtocolJson()).identity)
        store.write("identity", "not json")
        assertNull(Credentials(store, ProtocolJson()).identity)
        store.write("identity", """{"hash":"x"}""")
        assertNull(Credentials(store, ProtocolJson()).identity)
    }

    @Test
    fun samePerson() {
        val aysel = SessionIdentity.User(UserIdentity("12345", "aysel@example.com"), "a")
        assertTrue(aysel.samePerson(SessionIdentity.User(UserIdentity("12345", phone = "+99450"), "b")))
        assertTrue(!aysel.samePerson(SessionIdentity.User(UserIdentity("67890", "aysel@example.com"), "a")))
        val byEmail = SessionIdentity.User(UserIdentity(email = "a@x.az"), null)
        assertTrue(byEmail.samePerson(SessionIdentity.User(UserIdentity(email = "a@x.az", name = "A"), "h")))
        assertTrue(!byEmail.samePerson(SessionIdentity.User(UserIdentity(email = "b@x.az"), null)))
        assertTrue(SessionIdentity.Anonymous.samePerson(SessionIdentity.Anonymous))
        assertTrue(!SessionIdentity.Anonymous.samePerson(aysel))
        assertTrue(!aysel.samePerson(SessionIdentity.Anonymous))
        assertTrue(!aysel.samePerson(null))
    }

    @Test
    fun errorsSayWhatHappened() {
        val refused = ClomniError.Server(409, ai.clomni.messenger.protocol.ServerError("already_answered", "answered", "req_1", emptyMap()))
        assertEquals("already_answered", refused.code)
        assertEquals("HTTP 409 already_answered: answered", refused.message)
        assertEquals("HTTP 502", ClomniError.Server(502, null).message)
        assertNull(ClomniError.Network("offline").code)
        assertEquals("empty text", ClomniError.Rejected("empty text").message)
    }
}
