package ai.clomni.messenger.api

import ai.clomni.messenger.protocol.MobileSession
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.ServerError
import ai.clomni.messenger.protocol.toJson
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID

/** The person `Clomni.loginUser` names; [userId] or [email] identifies them. */
internal data class UserIdentity(
    val userId: String? = null,
    val email: String? = null,
    val phone: String? = null,
    val name: String? = null,
)

/** Who a session is for. Kept with the session, so a refused refresh can be replaced by a new login. */
internal sealed interface SessionIdentity {
    object Anonymous : SessionIdentity {
        override fun toString() = "Anonymous"
    }

    /** [hash] = hex(HMAC-SHA256(identity_secret, user_id)), made on the customer's server. */
    data class User(val user: UserIdentity, val hash: String?) : SessionIdentity
}

/** The same person as [other]: a user is known by [UserIdentity.userId], or by email when there is none. */
internal fun SessionIdentity.samePerson(other: SessionIdentity?): Boolean = when (this) {
    SessionIdentity.Anonymous -> other == SessionIdentity.Anonymous
    is SessionIdentity.User -> other is SessionIdentity.User &&
        user.userId == other.user.userId && (user.userId != null || user.email == other.user.email)
}

/** Why a call or an action did not succeed. */
internal sealed class ClomniError(message: String) : Exception(message) {
    /** The server refused the request; [error] is its `Error` body when it sent one. */
    class Server(val status: Int, val error: ServerError?) :
        ClomniError("HTTP $status${error?.let { " ${it.code}: ${it.message}" }.orEmpty()}")

    /** No answer: offline, timeout, TLS. */
    class Network(reason: String) : ClomniError(reason)

    /** A success whose body could not be read. */
    class UnreadableResponse(status: Int) : ClomniError("HTTP $status: unreadable body")

    /** No session yet: log the user in first. */
    class NotLoggedIn : ClomniError("not logged in")

    /** Refused before sending: an empty text, a button already answered, a message not in the outbox. */
    class Rejected(reason: String) : ClomniError(reason)

    /** The server's error code, e.g. `already_answered`. */
    val code: String? get() = (this as? Server)?.error?.code
}

/**
 * The FCM token the app gave ([token]), and the user the server has it for ([registeredFor]): null until it has, and
 * after logout, which removes it there. The server keeps one token per device.
 */
internal data class PushRegistration(val token: String, val registeredFor: String? = null)

/**
 * What the SDK keeps about its login, in a [SecureStore]: the session (with the single-use refresh token), the
 * identity to log in again with, the anonymous user to resume or merge, and the device id.
 */
internal class Credentials(private val store: SecureStore, private val protocol: ProtocolJson) {
    private var sessionLoaded = false
    private var cachedSession: MobileSession? = null

    @get:Synchronized
    @set:Synchronized
    var session: MobileSession?
        get() {
            if (!sessionLoaded) {
                cachedSession = store.read(SESSION)?.let(protocol::parseSession)
                sessionLoaded = true
            }
            return cachedSession
        }
        set(value) {
            cachedSession = value
            sessionLoaded = true
            store.write(SESSION, value?.toJson()?.toString())
        }

    var identity: SessionIdentity?
        get() = store.read(IDENTITY)?.let(::decodeIdentity)
        set(value) = store.write(IDENTITY, value?.let(::encodeIdentity))

    /** The anonymous user an earlier session made on this device: resumed, or merged into the next identified one. */
    var anonymousId: String?
        get() = store.read(ANONYMOUS_ID)
        set(value) = store.write(ANONYMOUS_ID, value)

    /** Made on first use and kept for the life of the install, across logouts. */
    @get:Synchronized
    val deviceId: String
        get() = store.read(DEVICE_ID) ?: "d_${UUID.randomUUID()}".also { store.write(DEVICE_ID, it) }

    /** Kept next to the session (a cache may be cleared): the token outlives logouts, its registration does not. */
    var pushRegistration: PushRegistration?
        get() = store.read(PUSH)?.let { json ->
            val o = runCatching { Json.parseToJsonElement(json) as JsonObject }.getOrNull() ?: return null
            fun field(key: String) = (o[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
            PushRegistration(field("token") ?: return null, field("registered_for"))
        }
        set(value) = store.write(
            PUSH,
            value?.let { buildJsonObject { put("token", it.token); put("registered_for", it.registeredFor) }.toString() },
        )

    /** Logout: everything but the device id and the push token. */
    @Synchronized
    fun clear() {
        session = null
        identity = null
        anonymousId = null
    }

    private fun encodeIdentity(identity: SessionIdentity): String = when (identity) {
        SessionIdentity.Anonymous -> buildJsonObject { put("anonymous", true) }
        is SessionIdentity.User -> buildJsonObject {
            put(
                "user",
                buildJsonObject {
                    put("user_id", identity.user.userId)
                    put("email", identity.user.email)
                    put("phone", identity.user.phone)
                    put("name", identity.user.name)
                },
            )
            put("hash", identity.hash)
        }
    }.toString()

    private fun decodeIdentity(json: String): SessionIdentity? {
        val o = runCatching { Json.parseToJsonElement(json) as JsonObject }.getOrNull() ?: return null
        if (o.containsKey("anonymous")) return SessionIdentity.Anonymous
        val user = o["user"] as? JsonObject ?: return null
        fun JsonObject.field(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
        return SessionIdentity.User(
            UserIdentity(user.field("user_id"), user.field("email"), user.field("phone"), user.field("name")),
            o.field("hash"),
        )
    }

    private companion object {
        const val SESSION = "session"
        const val IDENTITY = "identity"
        const val ANONYMOUS_ID = "anonymous_id"
        const val DEVICE_ID = "device_id"
        const val PUSH = "push_registration"
    }
}
