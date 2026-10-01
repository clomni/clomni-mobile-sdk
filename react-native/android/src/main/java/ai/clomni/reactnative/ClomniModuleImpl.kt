package ai.clomni.reactnative

import ai.clomni.messenger.Clomni
import ai.clomni.messenger.ClomniUser
import ai.clomni.messenger.UnreadCountListener
import android.util.Log
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableMap
import kotlin.math.roundToInt

/**
 * What the module does, for both architectures (src/newarch and src/oldarch only adapt it): every call goes to the
 * Android SDK's [Clomni] facade, and the SDK's events go back to JS as [NAME_EVENT] maps `{name, count?, text?}`.
 */
internal class ClomniModuleImpl(
    private val context: ReactApplicationContext,
    private val emit: (WritableMap) -> Unit,
) {
    @Volatile
    private var unreadCount = 0

    private val unreadListener = UnreadCountListener { count ->
        unreadCount = count
        emit(event("unreadCountChanged", count = count))
    }

    init {
        // The app's JS hears these; native code of the app should not set them as well.
        Clomni.onMessengerOpened = { source -> emit(event("messengerOpened", text = source)) }
        Clomni.onMessengerClosed = { emit(event("messengerClosed")) }
        Clomni.onConversationStarted = { id -> emit(event("conversationStarted", text = id)) }
        Clomni.onFlowCompleted = { flowId -> emit(event("flowCompleted", text = flowId)) }
        Clomni.addUnreadCountListener(unreadListener)
    }

    fun invalidate() {
        Clomni.removeUnreadCountListener(unreadListener)
        Clomni.onMessengerOpened = null
        Clomni.onMessengerClosed = null
        Clomni.onConversationStarted = null
        Clomni.onFlowCompleted = null
    }

    fun setup(appId: String, apiKey: String, region: String) {
        Clomni.initialize(context.applicationContext, appId, apiKey, region)
    }

    fun loginUser(user: ReadableMap, userHash: String?) {
        Clomni.loginUser(
            ClomniUser(userId = user.text("userId"), email = user.text("email"), phone = user.text("phone"),
                name = user.text("name")),
            userHash,
        )
    }

    fun loginUnidentifiedUser() = Clomni.loginUnidentifiedUser()

    fun logout() = Clomni.logout()

    fun present(source: String?) = Clomni.present(source)

    fun presentNewConversation(source: String?) = Clomni.presentNewConversation(source)

    fun presentConversation(conversationId: String) = Clomni.presentConversation(conversationId)

    fun dismiss() = Clomni.dismiss()

    fun startFlow(event: String, data: ReadableMap, openMessenger: Boolean, source: String?) {
        Clomni.startFlow(event, data.toHashMap(), openMessenger, source)
    }

    fun setLauncherVisible(visible: Boolean) = Clomni.setLauncherVisible(visible)

    fun setBottomPadding(padding: Double) = Clomni.setBottomPadding(padding.roundToInt())

    /** A tap on a Clomni notification: its conversation opens. */
    fun handlePush(data: ReadableMap) {
        val conversationId = data.text("conversation_id")
        if (data.text("clomni") != "1" || conversationId == null) return
        Clomni.presentConversation(conversationId)
    }

    /** Android shows or hides its own notifications; the JS layer does not ask here. */
    fun shouldShowForeground(): Boolean = true

    fun getUnreadCount(promise: Promise) = promise.resolve(unreadCount)

    // Not in the Android SDK's facade yet (push registration and display: CM-075; the rest: CM-076).
    fun updateUser() = notYet("updateUser")

    fun setLogLevel() = notYet("setLogLevel")

    fun setTypeface() = notYet("setTypeface")

    fun setDeviceToken() = notYet("setDeviceToken")

    fun setNotificationIcon() = notYet("setNotificationIcon")

    private fun notYet(call: String) {
        Log.w(TAG, "$call: not in this version of the Android SDK yet; nothing done")
    }

    private fun ReadableMap.text(key: String): String? =
        if (hasKey(key) && !isNull(key)) getString(key) else null

    private fun event(name: String, count: Int? = null, text: String? = null): WritableMap =
        Arguments.createMap().apply {
            putString("name", name)
            if (count != null) putInt("count", count)
            if (text != null) putString("text", text)
        }

    companion object {
        const val NAME = "Clomni"

        /** The old architecture's event (NativeEventEmitter); the New Architecture uses the spec's onEvent. */
        const val NAME_EVENT = "ClomniEvent"
        private const val TAG = "Clomni"
    }
}
