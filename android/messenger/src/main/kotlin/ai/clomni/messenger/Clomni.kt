package ai.clomni.messenger

import ai.clomni.messenger.api.ApiConfiguration
import ai.clomni.messenger.api.UserIdentity
import ai.clomni.messenger.log.ClomniLog
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.presentation.ThemeOverride
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.ui.ClomniFonts
import ai.clomni.messenger.ui.MessengerRuntime
import android.content.Context
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The app's user, for [Clomni.loginUser]. Clomni knows the user by [userId], else by [email]; [phone] and [name] are
 * shown to the operators and fill the messenger's forms.
 *
 * A plain class, not a data class, so a later field can be added without breaking apps built against this one.
 */
public class ClomniUser @JvmOverloads constructor(
    public val userId: String? = null,
    public val email: String? = null,
    public val phone: String? = null,
    public val name: String? = null,
) {
    override fun equals(other: Any?): Boolean =
        other is ClomniUser && userId == other.userId && email == other.email && phone == other.phone && name == other.name

    override fun hashCode(): Int = listOf(userId, email, phone, name).hashCode()

    override fun toString(): String = "ClomniUser(userId=$userId, email=$email, phone=$phone, name=$name)"
}

/**
 * The Clomni Messenger SDK (brief 8·9): everything the app calls is here, with the same names as on iOS.
 *
 * Every method may be called from any thread; the work is done on the main thread, in the order of the calls.
 * Callbacks and listeners are called on the main thread. Nothing here adds anything to the app's screens: the
 * messenger opens only when the app asks ([present], [startFlow] with `openMessenger`, a tap on a Clomni
 * notification), and the floating button shows only after [setLauncherVisible] or when the panel turns it on.
 */
public object Clomni {
    private val main by lazy { Handler(Looper.getMainLooper()) }

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else main.post(action)
    }

    /** This SDK's version. */
    @JvmStatic
    public val version: String
        get() = BuildConfig.SDK_VERSION

    // Setup

    /**
     * Prepares the connection and push; adds nothing to the app's screens. Call it once, from
     * `Application.onCreate` (a notification can start the process, and the messenger it opens needs the SDK).
     * [region] is "eu".
     */
    @JvmStatic
    @JvmOverloads
    public fun initialize(context: Context, appId: String, apiKey: String, region: String = "eu") {
        val url = when (region.lowercase()) {
            "eu" -> ApiConfiguration.DEFAULT_BASE_URL
            else -> ApiConfiguration.DEFAULT_BASE_URL.also { ClomniLog.warning { "unknown region \"$region\", using eu" } }
        }
        val app = context.applicationContext
        onMain { MessengerRuntime.initialize(app, appId, apiKey, url) }
    }

    /**
     * The app's logged-in user. [userHash] is hex(HMAC-SHA256(identity_secret, userId)), computed on the app's
     * server, never in the app. Conversations of an anonymous visitor on this device move to the user.
     */
    @JvmStatic
    public fun loginUser(user: ClomniUser, userHash: String?) {
        val identity = UserIdentity(user.userId, user.email, user.phone, user.name)
        onMain { MessengerRuntime.login(identity) { it.loginUser(identity, userHash) } }
    }

    /**
     * An anonymous visitor, the same one on this device until [logout]. Not needed before [present]: the messenger
     * starts one itself when nobody is logged in.
     */
    @JvmStatic
    public fun loginUnidentifiedUser() {
        onMain { MessengerRuntime.login(null) { it.loginUnidentifiedUser() } }
    }

    /**
     * Changes only what is given; [customAttributes] (strings, numbers, booleans, lists and maps of them) are merged
     * with the user's existing ones. [language] is "az", "en" or "ru".
     */
    @JvmStatic
    @JvmOverloads
    public fun updateUser(name: String? = null, language: String? = null, customAttributes: Map<String, Any?>? = null) {
        val fields = LinkedHashMap<String, JsonElement>()
        name?.let { fields["name"] = JsonPrimitive(it) }
        language?.let { fields["language"] = JsonPrimitive(it) }
        if (customAttributes != null) {
            fields["custom_attributes"] = try {
                json(customAttributes)
            } catch (e: IllegalArgumentException) {
                return ClomniLog.error { "updateUser: ${e.message}" }
            }
        }
        if (fields.isEmpty()) return ClomniLog.warning { "updateUser: nothing to change" }
        onMain { MessengerRuntime.updateUser(JsonObject(fields)) }
    }

    /**
     * Ends the session and deletes the messenger's data on this device. Call it when the app's user logs out, or the
     * next user sees this one's conversations.
     */
    @JvmStatic
    public fun logout() {
        onMain { MessengerRuntime.logout() }
    }

    /**
     * How much the SDK writes to logcat (tag `Clomni`): [ClomniLogLevel.NONE] writes nothing, the default is
     * [ClomniLogLevel.WARNING]; [ClomniLogLevel.DEBUG] while developing.
     */
    @JvmStatic
    public fun setLogLevel(level: ClomniLogLevel) {
        ClomniLog.level = level.level
    }

    // Opening the messenger

    /**
     * Home. [source] says where in the app (for example "profile_support") and is stored with a conversation started
     * from here.
     */
    @JvmStatic
    @JvmOverloads
    public fun present(source: String? = null) {
        onMain { MessengerRuntime.coordinator?.present(source) ?: notReady() }
    }

    /** Straight into a new conversation, with the inbox's first flow. */
    @JvmStatic
    @JvmOverloads
    public fun presentNewConversation(source: String? = null) {
        onMain { MessengerRuntime.coordinator?.presentNewConversation(source) ?: notReady() }
    }

    /** One conversation, by its id ([onConversationStarted] gives it). */
    @JvmStatic
    public fun presentConversation(id: String) {
        onMain { MessengerRuntime.coordinator?.presentConversation(id) ?: notReady() }
    }

    /** Closes the messenger from code; the user is where they were in the app. */
    @JvmStatic
    public fun dismiss() {
        onMain { MessengerRuntime.coordinator?.dismiss() }
    }

    /**
     * Starts the flow bound to an app event (for example "payment_failed" or "ride_problem") in a new conversation.
     * Its texts can use [data] as `{{data.order_id}}` (strings, numbers, booleans, lists and maps of them). With
     * [openMessenger] the conversation opens on screen; otherwise the user learns of it from a push or the unread
     * count. Nothing happens when no flow is bound to the event.
     */
    @JvmStatic
    @JvmOverloads
    public fun startFlow(event: String, data: Map<String, Any?> = emptyMap(), openMessenger: Boolean = false, source: String? = null) {
        val json = try {
            json(data) as JsonObject
        } catch (e: IllegalArgumentException) {
            return ClomniLog.error { "startFlow: ${e.message}" }
        }
        onMain {
            MessengerRuntime.coordinator?.startFlow(event, json.takeIf { it.isNotEmpty() }, openMessenger, source) ?: notReady()
        }
    }

    /** The floating button: off by default, and the panel can turn it on too. The app's choice wins. */
    @JvmStatic
    public fun setLauncherVisible(visible: Boolean) {
        onMain { MessengerRuntime.setLauncherVisible(visible) }
    }

    /**
     * The app's own font for every text of the messenger, for example `ResourcesCompat.getFont(context,
     * R.font.montserrat)` with a font family that has the weights. Text keeps following the user's font size. A
     * weight the family lacks takes its nearest face. null is the system font. Set it before the messenger opens.
     */
    @JvmStatic
    public fun setTypeface(typeface: Typeface?) {
        ClomniFonts.typeface = typeface
    }

    /**
     * The app's own look over the panel's. [primaryColor] "#RRGGBB": the other brand colours are derived from it by
     * the panel's rules. [mode]: light, dark, or as the system is. Each call replaces the last; null leaves that one to
     * the panel. [typeface] sets the font as [setTypeface] does; null leaves the font as it is. The open messenger and
     * the launcher change at once.
     */
    @JvmStatic
    @JvmOverloads
    public fun setTheme(primaryColor: String? = null, typeface: Typeface? = null, mode: ClomniThemeMode? = null) {
        typeface?.let(::setTypeface)
        val override = themeOverride(primaryColor, mode)
        onMain { MessengerRuntime.setTheme(override) }
    }

    /** [setTheme]'s colour and mode; a colour that is not #RRGGBB is logged and left to the panel. */
    internal fun themeOverride(primaryColor: String?, mode: ClomniThemeMode?): ThemeOverride {
        val color = primaryColor?.let(RgbColor::parse)
        if (primaryColor != null && color == null) {
            ClomniLog.error { "setTheme: primaryColor \"$primaryColor\" is not #RRGGBB; the panel's colour stays" }
        }
        return ThemeOverride(color, mode?.mode)
    }

    /** Lifts the launcher above the app's bottom navigation, in dp. */
    @JvmStatic
    public fun setBottomPadding(dp: Int) {
        onMain { MessengerRuntime.setBottomPadding(dp) }
    }

    // Push (with ClomniPush)

    /**
     * The FCM token, from FirebaseMessagingService.onNewToken (and FirebaseMessaging.getToken at start). It is kept
     * and registered for whoever is logged in, and again for the next user.
     */
    @JvmStatic
    public fun setDeviceToken(token: String) {
        onMain { MessengerRuntime.setDeviceToken(token) }
    }

    /** The small icon of Clomni's notifications (a white silhouette, as Android asks); without it, the app's icon. */
    @JvmStatic
    public fun setNotificationIcon(icon: Int) {
        MessengerRuntime.notificationIcon = icon
    }

    // Unread count and events

    /** Called at once with the unread count, then on every change, until removed; for the app's own badge. */
    @JvmStatic
    public fun addUnreadCountListener(listener: UnreadCountListener) {
        onMain { MessengerRuntime.addUnreadCountListener(listener) }
    }

    @JvmStatic
    public fun removeUnreadCountListener(listener: UnreadCountListener) {
        onMain { MessengerRuntime.removeUnreadCountListener(listener) }
    }

    /** The messenger opened, with the source given to [present]. One listener; null removes it. */
    @JvmStatic
    public fun onMessengerOpened(listener: MessengerOpenedListener?) {
        MessengerRuntime.events.messengerOpened = listener?.let { { source -> it.onMessengerOpened(source) } }
    }

    @JvmStatic
    public fun onMessengerClosed(listener: MessengerClosedListener?) {
        MessengerRuntime.events.messengerClosed = listener?.let { { it.onMessengerClosed() } }
    }

    /** A new conversation, with its id. */
    @JvmStatic
    public fun onConversationStarted(listener: ConversationStartedListener?) {
        MessengerRuntime.events.conversationStarted = listener?.let { { id -> it.onConversationStarted(id) } }
    }

    /** The unread count changed; [addUnreadCountListener] also hears the current one at once. */
    @JvmStatic
    public fun onUnreadCountChanged(listener: UnreadCountListener?) {
        MessengerRuntime.events.unreadCountChanged = listener?.let { { count -> it.onUnreadCountChanged(count) } }
    }

    /** A flow reached its end, with the flow's id. */
    @JvmStatic
    public fun onFlowCompleted(listener: FlowCompletedListener?) {
        MessengerRuntime.events.flowCompleted = listener?.let { { flowId -> it.onFlowCompleted(flowId) } }
    }

    /**
     * A link the messenger is about to open (a news item's button: a web address or the app's own deep link). Return
     * true when the app opened it; false, or no listener, lets the system open it. One listener; null removes it.
     */
    @JvmStatic
    public fun onLink(listener: LinkListener?) {
        MessengerRuntime.events.link = listener?.let { { url -> it.onLink(url) } }
    }

    private fun notReady() = ClomniLog.error { "call Clomni.initialize first" }

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

/** Light, dark, or as the system is, for [Clomni.setTheme]. */
public enum class ClomniThemeMode(internal val mode: MessengerConfig.ThemeMode) {
    SYSTEM(MessengerConfig.ThemeMode.SYSTEM),
    LIGHT(MessengerConfig.ThemeMode.LIGHT),
    DARK(MessengerConfig.ThemeMode.DARK),
}

/** How much the SDK writes to logcat, for [Clomni.setLogLevel]. */
public enum class ClomniLogLevel(internal val level: ClomniLog.Level?) {
    NONE(null),

    /** A wrong api key or user_hash, a call before initialize, or something the app asked for that failed. */
    ERROR(ClomniLog.Level.ERROR),

    /** Also what was dropped or could not be done. The default. */
    WARNING(ClomniLog.Level.WARNING),
    INFO(ClomniLog.Level.INFO),
    DEBUG(ClomniLog.Level.DEBUG),
}

/** The unread count for the app's own badge ([Clomni.addUnreadCountListener], [Clomni.onUnreadCountChanged]). */
public fun interface UnreadCountListener {
    public fun onUnreadCountChanged(count: Int)
}

/** [Clomni.onMessengerOpened]. */
public fun interface MessengerOpenedListener {
    public fun onMessengerOpened(source: String?)
}

/** [Clomni.onMessengerClosed]. */
public fun interface MessengerClosedListener {
    public fun onMessengerClosed()
}

/** [Clomni.onConversationStarted]. */
public fun interface ConversationStartedListener {
    public fun onConversationStarted(conversationId: String)
}

/** [Clomni.onFlowCompleted]. */
public fun interface FlowCompletedListener {
    public fun onFlowCompleted(flowId: String)
}

/** [Clomni.onLink]: true when the app opened [url] itself. */
public fun interface LinkListener {
    public fun onLink(url: String): Boolean
}
