package ai.clomni.messenger.api

import ai.clomni.messenger.BuildConfig
import ai.clomni.messenger.log.ClomniLog
import ai.clomni.messenger.protocol.ClientMessage
import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.ConversationPage
import ai.clomni.messenger.protocol.ConversationWithMessages
import ai.clomni.messenger.protocol.FlowTriggerResult
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessagePage
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.MobileSession
import ai.clomni.messenger.protocol.MobileUser
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.ServerError
import ai.clomni.messenger.protocol.UploadedFile
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

/** The app's keys and where the API lives. */
internal data class ApiConfiguration(
    val appId: String,
    val apiKey: String,
    val baseUrl: String = DEFAULT_BASE_URL,
    val sdkVersion: String = BuildConfig.SDK_VERSION,
) {
    internal companion object {
        const val DEFAULT_BASE_URL = "https://app.clomni.ai/v1"
    }
}

/** The device fields of POST /mobile/sessions. */
internal data class DeviceInfo(
    val deviceId: String,
    val osVersion: String?,
    val appVersion: String?,
    val sdkVersion: String,
    val locale: String?,
    val timezone: String?,
    val model: String?,
)

/** GET /mobile/config: [Changed] carries the body to keep on disk with its ETag. */
internal sealed interface ConfigResponse {
    object NotModified : ConfigResponse

    data class Changed(val config: MessengerConfig, val body: String, val etag: String?) : ConfigResponse
}

/**
 * The Mobile API (protocol/openapi.yaml) over OkHttp. Calls block: the SDK makes them from its own worker thread.
 * Failures are [ClomniError]s: [ClomniError.Server] for an error status, [ClomniError.Network] for no answer.
 *
 * - Session endpoints authenticate with the app's keys, every other one with the session token from [credentials].
 * - A session within a minute of expiring is refreshed first. `401 token_expired`: the session is refreshed (once,
 *   however many calls hit it at the same time; the refresh token is single-use) and the call repeated once. A
 *   refresh the server refuses clears the session.
 * - `429`: waits `Retry-After` seconds and repeats, up to [MAX_RATE_LIMIT_RETRIES] times.
 * - `5xx`: repeats after 1, 2 and 4 seconds, then gives up.
 */
internal class ApiClient(
    private val config: ApiConfiguration,
    private val credentials: Credentials,
    private val protocol: ProtocolJson,
    private val device: () -> DeviceInfo,
    /** Built on first use, on the SDK's worker: building one reads the system's certificates (disk). */
    private val http: Lazy<OkHttpClient> = lazy(::defaultClient),
    private val sleep: (Long) -> Unit = Thread::sleep,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val base: HttpUrl = config.baseUrl.trimEnd('/').toHttpUrl()
    private val refreshLock = Any()

    val sdkHeader: String get() = "android/${config.sdkVersion}"

    /**
     * A new session for [identity]. The anonymous user kept from earlier goes along: resumed for an anonymous visitor,
     * merged into an identified user (whose conversations it then joins).
     */
    fun open(identity: SessionIdentity): MobileSession {
        val body = buildJsonObject {
            if (identity is SessionIdentity.User) {
                put(
                    "user",
                    buildJsonObject {
                        identity.user.userId?.let { put("user_id", it) }
                        put("email", identity.user.email)
                        put("phone", identity.user.phone)
                        put("name", identity.user.name)
                        put("user_hash", identity.hash)
                    },
                )
            }
            credentials.anonymousId?.let { put("anonymous_id", it) }
            put("device", device().toJson())
        }
        val session = read(call("POST", "mobile/sessions", body, Auth.APP), protocol::parseSession)
        credentials.session = session
        credentials.identity = identity
        credentials.anonymousId = if (session.anonymous) session.userId else null
        return session
    }

    /** The socket's handshake was refused (401): refresh the session the way a `token_expired` answer would. */
    fun refreshSession() {
        val token = credentials.session?.sessionToken ?: throw ClomniError.NotLoggedIn()
        refresh(token)
    }

    /** Ends the session on the server (best effort) and forgets it here; the device id stays. */
    fun logout() {
        try {
            if (credentials.session != null) call("DELETE", "mobile/sessions")
        } catch (e: ClomniError) {
            // Logged out on the device all the same; the session expires on its own.
        } finally {
            credentials.clear()
        }
    }

    fun getConfig(lang: String?, etag: String?): ConfigResponse {
        val response =
            call("GET", "mobile/config", query = mapOf("lang" to lang), headers = mapOf("If-None-Match" to etag))
        if (response.status == 304) return ConfigResponse.NotModified
        return ConfigResponse.Changed(read(response, protocol::parseConfig), response.body, response.etag)
    }

    fun listConversations(limit: Int? = null, cursor: String? = null): ConversationPage = read(
        call("GET", "conversations", query = mapOf("limit" to limit?.toString(), "cursor" to cursor)),
        protocol::parseConversationPage,
    )

    fun createConversation(openedFrom: String?): ConversationWithMessages = read(
        call("POST", "conversations", buildJsonObject { openedFrom?.let { put("opened_from", it) } }),
        protocol::parseConversationWithMessages,
    )

    fun getConversation(id: String): Conversation =
        read(call("GET", "conversations", segments = listOf(id)), protocol::parseConversation)

    fun listMessages(
        conversationId: String,
        beforeSeq: Long? = null,
        afterSeq: Long? = null,
        limit: Int? = null,
    ): MessagePage = read(
        call(
            "GET",
            "conversations",
            segments = listOf(conversationId, "messages"),
            query = mapOf(
                "before_seq" to beforeSeq?.toString(),
                "after_seq" to afterSeq?.toString(),
                "limit" to limit?.toString(),
            ),
        ),
        protocol::parseMessagePage,
    )

    /** The user's own message as the server stored it; a repeated `client_id` answers with the same one. */
    fun sendMessage(conversationId: String, message: ClientMessage): Message = read(
        call("POST", "conversations", RawJson(protocol.encode(message)), segments = listOf(conversationId, "messages")),
        protocol::parseMessage,
    )

    fun markRead(conversationId: String, upToSeq: Long) {
        val body = buildJsonObject { put("up_to_seq", upToSeq) }
        call("POST", "conversations", body, segments = listOf(conversationId, "read"))
    }

    fun setTyping(conversationId: String, typing: Boolean) {
        call(
            "POST",
            "conversations",
            buildJsonObject { put("state", if (typing) "on" else "off") },
            segments = listOf(conversationId, "typing"),
        )
    }

    fun upload(file: File, name: String, mime: String): UploadedFile {
        val body = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("file", name, file.asRequestBody(mime.toMediaType()))
            .build()
        return read(call("POST", "uploads", body), protocol::parseUpload)
    }

    fun getUser(): MobileUser = read(call("GET", "users/me"), protocol::parseUser)

    /** Only the fields in [fields] change; `custom_attributes` are merged into the existing ones. */
    fun updateUser(fields: JsonObject): MobileUser = read(call("PATCH", "users/me", fields), protocol::parseUser)

    fun registerDevice(token: String, provider: String = "fcm", environment: String = "production") {
        call(
            "POST",
            "devices",
            buildJsonObject {
                put("token", token)
                put("provider", provider)
                put("environment", environment)
            },
        )
    }

    /** [openedFrom] (additive, as for POST /conversations): where in the app the flow was started. */
    fun triggerFlow(event: String, data: JsonObject?, openMessenger: Boolean, openedFrom: String? = null): FlowTriggerResult = read(
        call(
            "POST",
            "flows/trigger",
            buildJsonObject {
                put("event", event)
                data?.let { put("data", it) }
                put("open_messenger", openMessenger)
                openedFrom?.let { put("opened_from", it) }
            },
        ),
        protocol::parseFlowTrigger,
    )

    fun trackEvent(event: String, data: JsonObject?) {
        call("POST", "events", buildJsonObject { put("event", event); data?.let { put("data", it) } })
    }

    // Transport

    private enum class Auth { APP, SESSION }

    private class Response(val status: Int, val body: String, val etag: String?, val retryAfter: String?)

    /** A JSON body that is already a string. */
    private class RawJson(val json: String)

    private fun call(
        method: String,
        path: String,
        body: Any? = null,
        auth: Auth = Auth.SESSION,
        segments: List<String> = emptyList(),
        query: Map<String, String?> = emptyMap(),
        headers: Map<String, String?> = emptyMap(),
    ): Response {
        val url = base.newBuilder().addPathSegments(path).apply {
            segments.forEach { addPathSegment(it) }
            query.forEach { (name, value) -> if (value != null) addQueryParameter(name, value) }
        }.build()
        var refreshed = false
        var rateLimited = 0
        var serverErrors = 0
        while (true) {
            val token = if (auth == Auth.SESSION) validToken() else null
            val request = Request.Builder().url(url).method(method, body?.let(::requestBody)).apply {
                header("X-Clomni-SDK", sdkHeader)
                if (token != null) {
                    header("Authorization", "Bearer $token")
                } else {
                    header("X-Clomni-App-Id", config.appId)
                    header("X-Clomni-Api-Key", config.apiKey)
                }
                headers.forEach { (name, value) -> if (value != null) header(name, value) }
            }.build()
            val response = try {
                http.value.newCall(request).execute().use {
                    Response(it.code, it.body?.string().orEmpty(), it.header("ETag"), it.header("Retry-After"))
                }
            } catch (e: IOException) {
                throw ClomniError.Network(e.message ?: e.javaClass.simpleName)
            }
            val status = response.status
            when {
                status in 200..299 || status == 304 -> return response
                status == 401 && token != null && !refreshed && error(response)?.code == "token_expired" -> {
                    refresh(token)
                    refreshed = true
                }
                status == 429 && rateLimited < MAX_RATE_LIMIT_RETRIES -> {
                    rateLimited++
                    sleep((response.retryAfter?.trim()?.toLongOrNull() ?: 1L).coerceAtLeast(1L) * 1_000)
                }
                status >= 500 && serverErrors < MAX_SERVER_RETRIES -> {
                    sleep(1_000L shl serverErrors)
                    serverErrors++
                }
                else -> throw ClomniError.Server(status, error(response).also(::report))
            }
        }
    }

    /** The session token, refreshed first when it is about to expire. */
    private fun validToken(): String {
        val session = credentials.session ?: throw ClomniError.NotLoggedIn()
        if (session.expiresAt - clock() > RENEW_BEFORE_MS) return session.sessionToken
        refresh(session.sessionToken)
        return credentials.session?.sessionToken ?: throw ClomniError.NotLoggedIn()
    }

    /** Swaps the single-use refresh token for a new session, unless another call already did it for [expiredToken]. */
    private fun refresh(expiredToken: String) {
        synchronized(refreshLock) {
            val current = credentials.session ?: throw ClomniError.NotLoggedIn()
            if (current.sessionToken != expiredToken) return
            try {
                val body = buildJsonObject { put("refresh_token", current.refreshToken) }
                val response = call("POST", "mobile/sessions/refresh", body, Auth.APP)
                credentials.session = read(response, protocol::parseSession)
            } catch (e: ClomniError.Server) {
                if (e.status == 401 || e.status == 403) credentials.session = null
                throw e
            }
        }
    }

    private fun requestBody(body: Any): RequestBody = when (body) {
        is RequestBody -> body
        is RawJson -> body.json.toRequestBody(JSON)
        else -> body.toString().toRequestBody(JSON)
    }

    private fun error(response: Response): ServerError? = protocol.parseServerError(response.body)

    /** The integration's own mistakes, as brief 8·6.6 words them for the developer. */
    private fun report(error: ServerError?) {
        when (error?.code) {
            "invalid_api_key" -> ClomniLog.error { "api_key səhvdir və ya bu platforma üçün deyil" }
            "identity_verification_failed" -> ClomniLog.error { "user_hash səhvdir. identity_secret və user_id-ni yoxlayın" }
            "app_disabled" -> ClomniLog.warning { "this App SDK inbox is switched off in Clomni: the messenger does not open" }
        }
    }

    /** A success whose body does not parse: the caller may repeat it, as after no answer. */
    private fun <T> read(response: Response, parse: (String) -> T?): T =
        parse(response.body) ?: throw ClomniError.UnreadableResponse(response.status)

    private fun DeviceInfo.toJson() = buildJsonObject {
        put("device_id", deviceId)
        put("platform", "android")
        osVersion?.let { put("os_version", it) }
        appVersion?.let { put("app_version", it) }
        put("sdk_version", sdkVersion)
        locale?.let { put("locale", it) }
        timezone?.let { put("timezone", it) }
        model?.let { put("model", it) }
    }

    internal companion object {
        const val MAX_RATE_LIMIT_RETRIES = 3
        const val MAX_SERVER_RETRIES = 3
        private const val RENEW_BEFORE_MS = 60_000L
        private val JSON = "application/json; charset=utf-8".toMediaType()

        /**
         * OkHttp's own repeat after a dropped connection is off: the SDK's rules above (and the outbox's
         * `client_id`) are the only repeats, so a `POST /conversations` or `/flows/trigger` is never made twice.
         */
        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .retryOnConnectionFailure(false)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            .build()
    }
}
