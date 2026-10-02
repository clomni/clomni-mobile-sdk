package ai.clomni.messenger

import ai.clomni.messenger.ui.MessengerRuntime
import android.content.Context

/**
 * Clomni's pushes in the app's FirebaseMessagingService (brief 8·6.5, 8·12). The SDK has no Firebase dependency:
 * the app hands over `RemoteMessage.data`, and its own pushes stay its own.
 *
 * ```
 * override fun onNewToken(token: String) = Clomni.setDeviceToken(token)
 * override fun onMessageReceived(message: RemoteMessage) {
 *     if (ClomniPush.handle(this, message.data)) return
 *     // the app's own push
 * }
 * ```
 */
public object ClomniPush {
    /** The Android notification channel of Clomni's notifications ("Dəstək mesajları"). */
    public const val CHANNEL_ID: String = "clomni_messages"

    /** Whether a data message is Clomni's: `"clomni": "1"`. */
    @JvmStatic
    public fun isClomniPush(data: Map<String, String>): Boolean = data["clomni"] == "1"

    /**
     * Shows a Clomni push as a notification (title, text, the operator's photo; a tap opens its conversation), unless
     * the messenger is open on any screen; its unread count reaches the unread listeners either way. True when the
     * push was Clomni's, handled; false for the app's own, which the SDK leaves alone. Call it on FCM's thread; from
     * the main thread the notification is built in the background.
     */
    @JvmStatic
    public fun handle(context: Context, data: Map<String, String>): Boolean {
        if (!isClomniPush(data)) return false
        MessengerRuntime.pushReceived(context.applicationContext, data)
        return true
    }
}
