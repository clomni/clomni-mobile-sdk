package ai.clomni.messenger.api

import ai.clomni.messenger.protocol.MobileSession
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.protocol.toJson
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.UUID

/** Who the SDK logs in as: `Clomni.loginUser(...)` or `Clomni.loginUnidentifiedUser()`. */
internal sealed interface Identity {
    object Anonymous : Identity {
        override fun toString() = "Anonymous"
    }

    /** [userHash] = hex(HMAC-SHA256(identity_secret, user_id)), made on the customer's server. */
    data class User(
        val userId: String?,
        val email: String?,
        val phone: String? = null,
        val name: String? = null,
        val userHash: String? = null,
    ) : Identity

    /** The same person: a new hash or phone number does not make a new user. */
    fun sameAs(other: Identity?): Boolean = when (this) {
        Anonymous -> other == Anonymous
        is User -> other is User && userId == other.userId && (userId != null || email == other.email)
    }
}

/**
 * What the SDK keeps about its login, in a [SecureStore]: the session (with the single-use refresh token), the
 * identity to log in again with when the session cannot be refreshed, the anonymous user to resume or merge, and the
 * device id. Reads go through memory after the first one.
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

    var identity: Identity?
        get() = store.read(IDENTITY)?.let(::decodeIdentity)
        set(value) = store.write(IDENTITY, value?.let(::encodeIdentity))

    /** The anonymous user an earlier session created on this device: resumed, or merged into the next identified one. */
    var anonymousId: String?
        get() = store.read(ANONYMOUS_ID)
        set(value) = store.write(ANONYMOUS_ID, value)

    /** Made on first use and kept for the life of the install, across logouts. */
    @get:Synchronized
    val deviceId: String
        get() = store.read(DEVICE_ID) ?: "d_${UUID.randomUUID()}".also { store.write(DEVICE_ID, it) }

    /** Logout: everything but the device id. */
    @Synchronized
    fun clear() {
        session = null
        identity = null
        anonymousId = null
    }

    private fun encodeIdentity(identity: Identity): String = when (identity) {
        Identity.Anonymous -> buildJsonObject { put("anonymous", true) }
        is Identity.User -> buildJsonObject {
            put("user_id", identity.userId)
            put("email", identity.email)
            put("phone", identity.phone)
            put("name", identity.name)
            put("user_hash", identity.userHash)
        }
    }.toString()

    private fun decodeIdentity(json: String): Identity? {
        val o = runCatching { Json.parseToJsonElement(json) as JsonObject }.getOrNull() ?: return null
        fun field(key: String) = (o[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
        return if (o.containsKey("anonymous")) {
            Identity.Anonymous
        } else {
            Identity.User(field("user_id"), field("email"), field("phone"), field("name"), field("user_hash"))
        }
    }

    private companion object {
        const val SESSION = "session"
        const val IDENTITY = "identity"
        const val ANONYMOUS_ID = "anonymous_id"
        const val DEVICE_ID = "device_id"
    }
}
