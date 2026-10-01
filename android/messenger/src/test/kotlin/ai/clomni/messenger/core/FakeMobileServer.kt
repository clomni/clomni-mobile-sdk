package ai.clomni.messenger.core

import ai.clomni.messenger.protocol.Iso8601
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import java.util.Collections

/**
 * An in-memory Clomni server that keeps to protocol/openapi.yaml where the SDK can tell: sessions with single-use
 * refresh tokens, anonymous users resumed per device and merged on login, one `seq` counter per conversation, a
 * `client_id` handled once, 409 for an answered or stale button, `after_seq` paging, and the socket.
 *
 * Knobs make the network misbehave: [offline], [dropAnswers], [acceptSockets], [deliver].
 */
internal class FakeMobileServer : Dispatcher() {
    val http = MockWebServer().also { it.dispatcher = this }
    val baseUrl: String get() = http.url("/v1").toString()

    /** Every request, as "METHOD /path?query". */
    val log: MutableList<String> = Collections.synchronizedList(mutableListOf())

    /** Every request with the session token it carried. */
    private val calls: MutableList<Pair<String?, String>> = Collections.synchronizedList(mutableListOf())

    /** Whether the device holding [token] has made [request] ("METHOD /path?query"). */
    fun called(token: String?, request: String): Boolean = synchronized(calls) { calls.any { it.first == token && it.second == request } }

    /** No request is answered: the connection drops once it is read (the device's network is down). */
    @Volatile var offline = false

    /** The next N sends are stored, but their answer never reaches the device. */
    @Volatile var dropAnswers = 0

    /** False: socket handshakes are refused (503). */
    @Volatile var acceptSockets = true

    /** Whether the socket of [token] carries [frame]. */
    @Volatile var deliver: (token: String, frame: JsonObject) -> Boolean = { _, _ -> true }

    private class User(val id: String, val anonymous: Boolean, val userId: String?, val email: String?, val deviceId: String?)

    private class Session(val token: String, val refresh: String, val userId: String) {
        var expired = false
    }

    private class Conv(val id: String, var userId: String) {
        val messages = mutableListOf<JsonObject>()
        val answered = mutableSetOf<String>()
        var seq = 0L
    }

    private val users = mutableListOf<User>()
    private val sessions = mutableMapOf<String, Session>()
    private val refreshTokens = mutableMapOf<String, String>()
    private val conversations = mutableMapOf<String, Conv>()
    private val sent = mutableMapOf<String, JsonObject>()
    /** Open sockets with the token they were opened with: a refresh later does not close them. */
    private class Live(val token: String, val userId: String, val socket: WebSocket)

    private val sockets = mutableListOf<Live>()
    private var counter = 0

    fun close() {
        synchronized(this) { sockets.forEach { it.socket.close(1001, null) } }
        http.shutdown()
    }

    // Test controls

    @Synchronized
    fun expireSessions() = sessions.values.forEach { it.expired = true }

    /** Every token and refresh token stops working, as after a server-side reset. */
    @Synchronized
    fun forgetSessions() {
        sessions.clear()
        refreshTokens.clear()
    }

    @Synchronized
    fun closeSockets() {
        sockets.forEach { it.socket.close(1001, "going away") }
        sockets.clear()
    }

    @Synchronized
    fun hasSocket(token: String?): Boolean = sockets.any { it.token == token }

    /** A bot message; with [buttons] (id to title) it is quick replies waiting for an answer. */
    @Synchronized
    fun botSays(conversationId: String, text: String, buttons: List<Pair<String, String>> = emptyList()): JsonObject {
        val conv = conversations.getValue(conversationId)
        val message = if (buttons.isEmpty()) {
            newMessage(conv, "bot", "text", buildJsonObject { put("text", text) }, text)
        } else {
            val content = buildJsonObject {
                put("text", text)
                put(
                    "buttons",
                    JsonArray(buttons.map { (id, title) -> buildJsonObject { put("id", id); put("title", title); put("icon", JsonNull); put("payload", "node:$id") } }),
                )
                put("layout", "vertical")
                put("input_disabled", true)
            }
            newMessage(conv, "bot", "quick_replies", content, text, interactive = true)
        }
        broadcast(conv.userId, "message.created", message)
        return message
    }

    /** The messages a user can see in [conversationId], in `seq` order. */
    @Synchronized
    fun messages(conversationId: String): List<JsonObject> = conversations.getValue(conversationId).messages.toList()

    @Synchronized
    fun userMessages(conversationId: String): List<JsonObject> =
        messages(conversationId).filter { it.getValue("sender").jsonObject["type"]?.jsonPrimitive?.content == "user" }

    @Synchronized
    fun ownerOf(conversationId: String): String = conversations.getValue(conversationId).userId

    fun count(request: String): Int = synchronized(log) { log.count { it.startsWith(request) } }

    // HTTP

    override fun dispatch(request: RecordedRequest): MockResponse {
        log += "${request.method} ${request.path}"
        calls += request.getHeader("Authorization")?.removePrefix("Bearer ") to "${request.method} ${request.path}"
        if (offline) return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)
        return synchronized(this) { route(request) }
    }

    private fun route(request: RecordedRequest): MockResponse {
        val url = request.requestUrl!!
        val path = url.encodedPath.removePrefix("/v1/")
        val method = request.method
        if (path == "mobile/sessions" && method == "POST") return createSession(request)
        if (path == "mobile/sessions/refresh") return refresh(request)
        if (path == "realtime") return socket(url.queryParameter("token"))
        val session = sessions[request.getHeader("Authorization")?.removePrefix("Bearer ")]
            ?: return error(401, "invalid_token")
        if (session.expired) return error(401, "token_expired")
        val parts = path.split("/")
        return when {
            path == "mobile/sessions" && method == "DELETE" -> {
                sessions.remove(session.token)
                sockets.filter { it.token == session.token }.forEach { it.socket.close(1000, null) }
                sockets.removeAll { it.token == session.token }
                MockResponse().setResponseCode(204)
            }
            path == "mobile/config" -> config(request)
            path == "conversations" && method == "GET" -> json(
                buildJsonObject {
                    put("conversations", JsonArray(conversations.values.filter { it.userId == session.userId }.map(::conversation)))
                    put("next_cursor", JsonNull)
                },
            )
            path == "conversations" && method == "POST" -> createConversation(session)
            path == "uploads" -> json(
                buildJsonObject {
                    put("upload_id", "upl_${++counter}")
                    put("url", "https://app.clomni.ai/f/a.jpg")
                    put("name", "a.jpg")
                    put("size", request.bodySize)
                    put("mime", "image/jpeg")
                },
                201,
            )
            path == "flows/trigger" -> json(buildJsonObject { put("started", false); put("conversation", JsonNull) })
            path == "users/me" -> json(buildJsonObject { put("id", session.userId); put("anonymous", false); put("name", "Aysel") })
            path == "events" -> MockResponse().setResponseCode(202)
            parts[0] == "devices" -> MockResponse().setResponseCode(204)
            parts[0] == "conversations" -> {
                val conv = conversations[parts[1]]?.takeIf { it.userId == session.userId }
                    ?: return error(404, "conversation_not_found")
                when (parts.getOrNull(2)) {
                    null -> json(conversation(conv))
                    "messages" -> if (method == "GET") page(conv, request) else send(session, conv, request)
                    else -> MockResponse().setResponseCode(204)
                }
            }
            else -> error(404, "not_found")
        }
    }

    private fun createSession(request: RecordedRequest): MockResponse {
        if (request.getHeader("X-Clomni-App-Id") != APP_ID || request.getHeader("X-Clomni-Api-Key") != API_KEY) {
            return error(401, "invalid_api_key")
        }
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        val deviceId = body.getValue("device").jsonObject.getValue("device_id").jsonPrimitive.content
        val anonymousId = body["anonymous_id"]?.jsonPrimitive?.content
        val identity = body["user"] as? JsonObject
        val user = if (identity != null) {
            val userId = identity["user_id"]?.jsonPrimitive?.contentOrNull
            val email = identity["email"]?.jsonPrimitive?.contentOrNull
            val known = users.firstOrNull { !it.anonymous && (if (userId != null) it.userId == userId else it.email == email) }
                ?: User("usr_${++counter}", false, userId, email, null).also { users += it }
            // Logging in after browsing anonymously: the anonymous user's conversations become the user's.
            users.firstOrNull { it.anonymous && it.id == anonymousId }?.let { anonymous ->
                conversations.values.filter { it.userId == anonymous.id }.forEach { it.userId = known.id }
                users.remove(anonymous)
            }
            known
        } else {
            users.firstOrNull { it.anonymous && it.id == anonymousId && it.deviceId == deviceId }
                ?: User("usr_${++counter}", true, null, null, deviceId).also { users += it }
        }
        return issue(user.id, user.anonymous)
    }

    private fun refresh(request: RecordedRequest): MockResponse {
        val refreshToken = Json.parseToJsonElement(request.body.readUtf8()).jsonObject.getValue("refresh_token").jsonPrimitive.content
        val token = refreshTokens.remove(refreshToken) ?: return error(401, "invalid_token")
        val old = sessions.remove(token) ?: return error(401, "invalid_token")
        return issue(old.userId, users.first { it.id == old.userId }.anonymous)
    }

    private fun issue(userId: String, anonymous: Boolean): MockResponse {
        val n = ++counter
        val session = Session("st_$n", "rt_$n", userId)
        sessions[session.token] = session
        refreshTokens[session.refresh] = session.token
        return json(
            buildJsonObject {
                put("session_token", session.token)
                put("expires_at", "2030-01-01T00:00:00Z")
                put("refresh_token", session.refresh)
                put("user", buildJsonObject { put("id", userId); put("anonymous", anonymous); put("language", "az") })
                put("ws_url", http.url("/v1/realtime").toString().replace("http://", "ws://"))
            },
            201,
        )
    }

    private fun socket(token: String?): MockResponse {
        if (!acceptSockets) return MockResponse().setResponseCode(503)
        val session = sessions[token] ?: return error(401, "invalid_token")
        if (session.expired) return error(401, "token_expired")
        return MockResponse().withWebSocketUpgrade(
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    synchronized(this@FakeMobileServer) {
                        sockets += Live(session.token, session.userId, webSocket)
                        val ready = frame("ready", buildJsonObject { put("user_id", session.userId); put("heartbeat_sec", 25) })
                        send(session.token, webSocket, ready)
                    }
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(1000, null)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = forget(webSocket)

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = forget(webSocket)

                private fun forget(webSocket: WebSocket) {
                    synchronized(this@FakeMobileServer) { sockets.removeAll { it.socket === webSocket } }
                }
            },
        )
    }

    private fun config(request: RecordedRequest): MockResponse {
        val etag = "W/\"cfg1\""
        if (request.getHeader("If-None-Match") == etag) return MockResponse().setResponseCode(304)
        return json(buildJsonObject { put("brand", buildJsonObject { put("name", "Apar"); put("primary_color", "#1F9D63") }) })
            .setHeader("ETag", etag)
    }

    private fun createConversation(session: Session): MockResponse {
        val conv = Conv("conv_${++counter}", session.userId)
        conversations[conv.id] = conv
        val greeting = newMessage(
            conv,
            "bot",
            "quick_replies",
            buildJsonObject {
                put("text", "Salam! Nə ilə kömək edək?")
                put(
                    "buttons",
                    JsonArray(
                        listOf("yes" to "Bəli", "no" to "Xeyr").map { (id, title) ->
                            buildJsonObject { put("id", id); put("title", title); put("icon", JsonNull); put("payload", "node:$id") }
                        },
                    ),
                )
                put("layout", "vertical")
                put("input_disabled", true)
            },
            "Salam!",
            interactive = true,
        )
        return json(buildJsonObject { put("conversation", conversation(conv)); put("messages", JsonArray(listOf(greeting))) }, 201)
    }

    private fun page(conv: Conv, request: RecordedRequest): MockResponse {
        val url = request.requestUrl!!
        val limit = url.queryParameter("limit")?.toInt() ?: 50
        val all = conv.messages.sortedBy { it.seq }
        val after = url.queryParameter("after_seq")?.toLong()
        val before = url.queryParameter("before_seq")?.toLong()
        val (page, more) = when {
            after != null -> all.filter { it.seq > after }.let { it.take(limit) to (it.size > limit) }
            before != null -> all.filter { it.seq < before }.let { it.takeLast(limit) to (it.size > limit) }
            else -> all.takeLast(limit) to (all.size > limit)
        }
        return json(buildJsonObject { put("messages", JsonArray(page)); put("has_more", more) })
    }

    private fun send(session: Session, conv: Conv, request: RecordedRequest): MockResponse {
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        val clientId = body.getValue("client_id").jsonPrimitive.content
        val content = body.getValue("content").jsonObject
        val key = "${session.userId}/$clientId"
        val message = sent[key] ?: run {
            val text = when (body.getValue("type").jsonPrimitive.content) {
                "button_reply" -> answer(conv, content) ?: return@run null
                else -> content["text"]?.jsonPrimitive?.content ?: ""
            }
            newMessage(conv, "user", "text", buildJsonObject { put("text", text) }, text, clientId = clientId).also {
                sent[key] = it
                broadcast(conv.userId, "message.created", it)
            }
        } ?: return conflict
        if (dropAnswers > 0) {
            dropAnswers--
            return MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)
        }
        return json(message, 201)
    }

    private var conflict = error(409, "already_answered")

    /** The chosen button's title, or null with [conflict] set when the answer is refused. */
    private fun answer(conv: Conv, content: JsonObject): String? {
        val replyTo = content.getValue("reply_to").jsonPrimitive.content
        val target = conv.messages.firstOrNull { it.id == replyTo }
        if (replyTo in conv.answered) {
            conflict = error(409, "already_answered")
            return null
        }
        val latest = conv.messages.lastOrNull { it.interactive == true }
        if (target == null || target !== latest) {
            conflict = error(409, "stale_interaction")
            target?.let { replace(conv, it.withInteractive(false)) }
            return null
        }
        conv.answered += replyTo
        val answered = target.withInteractive(false)
        replace(conv, answered)
        broadcast(conv.userId, "message.updated", answered)
        val buttonId = content.getValue("button_id").jsonPrimitive.content
        return target.getValue("content").jsonObject.getValue("buttons").jsonArray
            .map { it.jsonObject }
            .firstOrNull { it.getValue("id").jsonPrimitive.content == buttonId }
            ?.getValue("title")?.jsonPrimitive?.content ?: buttonId
    }

    // Pieces

    private fun newMessage(
        conv: Conv,
        sender: String,
        type: String,
        content: JsonObject,
        fallback: String,
        clientId: String? = null,
        interactive: Boolean? = null,
    ): JsonObject {
        val seq = ++conv.seq
        val message = buildJsonObject {
            put("id", "msg_${++counter}")
            put("client_id", clientId)
            put("conversation_id", conv.id)
            put("type", type)
            put("sender", buildJsonObject { put("type", sender) })
            put("created_at", Iso8601.format(BASE_TIME + seq * 1_000))
            put("seq", seq)
            put("lang", "az")
            put(
                "flow",
                interactive?.let {
                    buildJsonObject { put("flow_id", "flw_test"); put("node_id", "N$seq"); put("version", 1); put("interactive", it) }
                } ?: JsonNull,
            )
            put("content", content)
            put("fallback_text", fallback)
        }
        conv.messages += message
        return message
    }

    private fun replace(conv: Conv, message: JsonObject) {
        val index = conv.messages.indexOfFirst { it.id == message.id }
        conv.messages[index] = message
    }

    private fun conversation(conv: Conv) = buildJsonObject {
        put("id", conv.id)
        put("status", "bot")
        put("assignee", JsonNull)
        put("unread_count", 0)
        put("last_message", conv.messages.lastOrNull() ?: JsonNull)
        put("flow", JsonNull)
        put("opened_from", JsonNull)
        put("created_at", Iso8601.format(BASE_TIME))
    }

    private fun broadcast(userId: String, event: String, data: JsonObject) {
        val frame = frame(event, data)
        sockets.filter { it.userId == userId }.forEach { send(it.token, it.socket, frame) }
    }

    private fun send(token: String, socket: WebSocket, frame: JsonObject) {
        if (deliver(token, frame)) socket.send(frame.toString())
    }

    private fun frame(event: String, data: JsonElement) = buildJsonObject {
        put("event", event)
        put("data", data)
        put("ts", Iso8601.format(BASE_TIME))
    }

    private fun json(body: JsonElement, status: Int = 200) =
        MockResponse().setResponseCode(status).setHeader("Content-Type", "application/json").setBody(body.toString())

    private fun error(status: Int, code: String) =
        json(buildJsonObject { put("error", buildJsonObject { put("code", code); put("message", code); put("request_id", "req_1") }) }, status)

    companion object {
        const val APP_ID = "app_test"
        const val API_KEY = "android_sdk-test"
        private const val BASE_TIME = 1_790_000_000_000L
    }
}

internal val JsonObject.id: String get() = getValue("id").jsonPrimitive.content

internal val JsonObject.seq: Long get() = getValue("seq").jsonPrimitive.long

internal val JsonObject.interactive: Boolean?
    get() = (this["flow"] as? JsonObject)?.get("interactive")?.jsonPrimitive?.boolean

internal fun JsonObject.withInteractive(interactive: Boolean): JsonObject {
    val flow = (this["flow"] as? JsonObject) ?: return this
    return JsonObject(this + ("flow" to JsonObject(flow + ("interactive" to JsonPrimitive(interactive)))))
}
