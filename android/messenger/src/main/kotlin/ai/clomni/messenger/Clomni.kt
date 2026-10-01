package ai.clomni.messenger

import ai.clomni.messenger.api.ApiConfiguration
import ai.clomni.messenger.api.UserIdentity
import ai.clomni.messenger.ui.MessengerRuntime
import android.content.Context
import android.os.Handler
import android.os.Looper
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** The logged-in user of the app, for [Clomni.loginUser]; every field is optional but one of [userId] or [email]. */
public data class ClomniUser(
    val userId: String? = null,
    val email: String? = null,
    val phone: String? = null,
    val name: String? = null,
)

/**
 * The messenger's opening API (brief 8·9; the same names as iOS). Nothing here adds anything to the app's screens:
 * the messenger opens only when the app calls [present] (or [startFlow] with `openMessenger`), and the floating
 * button shows only after [setLauncherVisible] or when the panel turns it on. Calls may come from any thread.
 * The final public shape is CM-076's.
 */
public object Clomni {
    private val main by lazy { Handler(Looper.getMainLooper()) }

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else main.post(action)
    }

    /**
     * Prepares the connection and push. [region] "eu" is app.clomni.ai; [baseUrl] overrides it (e.g. a staging
     * server). Call it once, from `Application.onCreate`.
     */
    @JvmStatic
    @JvmOverloads
    public fun initialize(context: Context, appId: String, apiKey: String, region: String = "eu", baseUrl: String? = null) {
        val url = baseUrl ?: when (region.lowercase()) {
            "eu" -> ApiConfiguration.DEFAULT_BASE_URL
            else -> ApiConfiguration.DEFAULT_BASE_URL.also { MessengerRuntime.log("unknown region \"$region\", using eu") }
        }
        onMain { MessengerRuntime.initialize(context, appId, apiKey, url) }
    }

    /** [userHash] = hex(HMAC-SHA256(identity_secret, user_id)), computed on the app's server. */
    @JvmStatic
    public fun loginUser(user: ClomniUser, userHash: String?) {
        val identity = UserIdentity(user.userId, user.email, user.phone, user.name)
        onMain { MessengerRuntime.login(identity) { it.loginUser(identity, userHash) } }
    }

    @JvmStatic
    public fun loginUnidentifiedUser() {
        onMain { MessengerRuntime.login(null) { it.loginUnidentifiedUser() } }
    }

    /** Ends the session and deletes the messenger's data on this device. */
    @JvmStatic
    public fun logout() {
        onMain { MessengerRuntime.logout() }
    }

    /** Home. [source] (where in the app, e.g. "profile_support") becomes a new conversation's `opened_from`. */
    @JvmStatic
    @JvmOverloads
    public fun present(source: String? = null) {
        onMain { MessengerRuntime.coordinator?.present(source) ?: notReady() }
    }

    /** Straight into a new conversation and its flow. */
    @JvmStatic
    @JvmOverloads
    public fun presentNewConversation(source: String? = null) {
        onMain { MessengerRuntime.coordinator?.presentNewConversation(source) ?: notReady() }
    }

    @JvmStatic
    public fun presentConversation(id: String) {
        onMain { MessengerRuntime.coordinator?.presentConversation(id) ?: notReady() }
    }

    /** Closes the messenger from code; the app is where it was. */
    @JvmStatic
    public fun dismiss() {
        onMain { MessengerRuntime.coordinator?.dismiss() }
    }

    /**
     * The flow bound to an app event (`ride_problem`, `payment_failed`) in a new conversation, with [data] (strings,
     * numbers, booleans, nulls, lists and maps of them): opened on screen when [openMessenger], otherwise announced by
     * a push or the unread count.
     */
    @JvmStatic
    @JvmOverloads
    public fun startFlow(event: String, data: Map<String, Any?> = emptyMap(), openMessenger: Boolean = false, source: String? = null) {
        val json = try {
            JsonObject(data.mapValues { json(it.value) })
        } catch (e: IllegalArgumentException) {
            return MessengerRuntime.log("startFlow: ${e.message}")
        }
        onMain {
            MessengerRuntime.coordinator?.startFlow(event, json.takeIf { it.isNotEmpty() }, openMessenger, source) ?: notReady()
        }
    }

    /** The floating button, off by default; the panel can turn it on too. The app's choice wins. */
    @JvmStatic
    public fun setLauncherVisible(visible: Boolean) {
        onMain { MessengerRuntime.setLauncherVisible(visible) }
    }

    /** Lifts the launcher above the app's bottom navigation, in dp. */
    @JvmStatic
    public fun setBottomPadding(dp: Int) {
        onMain { MessengerRuntime.setBottomPadding(dp) }
    }

    /** Hears the unread count at once, then on every change (on the main thread): for the app's own badge. */
    @JvmStatic
    public fun addUnreadCountListener(listener: UnreadCountListener) {
        onMain { MessengerRuntime.addUnreadCountListener(listener) }
    }

    @JvmStatic
    public fun removeUnreadCountListener(listener: UnreadCountListener) {
        onMain { MessengerRuntime.removeUnreadCountListener(listener) }
    }

    /** With the `source` passed to [present]. */
    @JvmStatic
    public var onMessengerOpened: ((String?) -> Unit)?
        get() = MessengerRuntime.events.messengerOpened
        set(value) {
            MessengerRuntime.events.messengerOpened = value
        }

    @JvmStatic
    public var onMessengerClosed: (() -> Unit)?
        get() = MessengerRuntime.events.messengerClosed
        set(value) {
            MessengerRuntime.events.messengerClosed = value
        }

    @JvmStatic
    public var onConversationStarted: ((String) -> Unit)?
        get() = MessengerRuntime.events.conversationStarted
        set(value) {
            MessengerRuntime.events.conversationStarted = value
        }

    @JvmStatic
    public var onUnreadCountChanged: ((Int) -> Unit)?
        get() = MessengerRuntime.events.unreadCountChanged
        set(value) {
            MessengerRuntime.events.unreadCountChanged = value
        }

    /** A flow reached its end, with the flow's id. */
    @JvmStatic
    public var onFlowCompleted: ((String) -> Unit)?
        get() = MessengerRuntime.events.flowCompleted
        set(value) {
            MessengerRuntime.events.flowCompleted = value
        }

    private fun notReady() = MessengerRuntime.log("call Clomni.initialize first")

    /** The app's own values as JSON; anything JSON cannot carry is refused. */
    internal fun json(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is String -> JsonPrimitive(value)
        is Number -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
        is Map<*, *> -> JsonObject(value.entries.associate { (k, v) -> k.toString() to json(v) })
        is Iterable<*> -> JsonArray(value.map(::json))
        is Array<*> -> JsonArray(value.map(::json))
        else -> throw IllegalArgumentException("data holds a ${value::class.java.simpleName}, which JSON cannot carry")
    }
}

/** The unread count for the app's own badge ([Clomni.addUnreadCountListener]). */
public fun interface UnreadCountListener {
    public fun onUnreadCountChanged(count: Int)
}
