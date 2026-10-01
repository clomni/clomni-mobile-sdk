package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.PushNotification
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import java.net.HttpURLConnection
import java.net.URL

/** Posts a [PushNotification] as an Android notification, and takes it away once its conversation is on screen. */
internal object PushNotifier {
    const val EXTRA_PUSH = "ai.clomni.messenger.push"
    const val EXTRA_CONVERSATION = "ai.clomni.messenger.conversation_id"

    /** [smallIcon] 0: the app's own icon. Fetches the operator's photo first (call it off the UI thread). */
    fun post(context: Context, notification: PushNotification, smallIcon: Int, color: Int?) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        ensureChannel(manager, notification.channelName)
        val built = build(
            context,
            notification,
            smallIcon.takeIf { it != 0 } ?: context.applicationInfo.icon.takeIf { it != 0 } ?: android.R.drawable.stat_notify_chat,
            color,
            notification.avatarUrl?.let(::photo),
            tapIntent(context, notification),
        )
        try {
            manager.notify(notification.tag, notification.id, built)
        } catch (e: SecurityException) {
            // Android 13+ without POST_NOTIFICATIONS: the app asks for it, not the SDK.
            MessengerRuntime.log("notification not shown: ${e.message}")
        }
    }

    /** The conversation is on screen: its notification has said what it had to. */
    fun cancel(context: Context, conversationId: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val tag = "clomni:$conversationId"
        manager.cancel(tag, tag.hashCode())
    }

    /** Made on first use, high importance; its name follows the messenger's language. */
    fun ensureChannel(manager: NotificationManager, name: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager.createNotificationChannel(NotificationChannel(PushNotification.CHANNEL_ID, name, NotificationManager.IMPORTANCE_HIGH))
    }

    fun build(
        context: Context,
        notification: PushNotification,
        smallIcon: Int,
        color: Int?,
        photo: Bitmap?,
        tap: PendingIntent?,
    ): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, PushNotification.CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH).setDefaults(Notification.DEFAULT_ALL)
        }
        builder.setSmallIcon(smallIcon)
            .setContentTitle(notification.title)
            .setContentText(notification.text)
            .setStyle(Notification.BigTextStyle().bigText(notification.text))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setShowWhen(true)
        color?.let(builder::setColor)
        photo?.let(builder::setLargeIcon)
        tap?.let(builder::setContentIntent)
        return builder.build()
    }

    /**
     * The app's own start screen with the messenger over it, so closing the messenger lands in the app; a running app
     * is brought to the front as it was.
     */
    private fun tapIntent(context: Context, notification: PushNotification): PendingIntent {
        val messenger = Intent(context, ClomniMessengerActivity::class.java)
            .setAction("ai.clomni.messenger.PUSH:${notification.conversationId.orEmpty()}")
            .putExtra(EXTRA_PUSH, true)
            .putExtra(EXTRA_CONVERSATION, notification.conversationId)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val intents = listOfNotNull(launch, messenger).toTypedArray()
        intents.first().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivities(
            context,
            notification.id,
            intents,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /** The operator's photo, or none when it does not arrive in time: the notification goes out without it. */
    private fun photo(url: String): Bitmap? = runCatching {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 4_000
        connection.readTimeout = 4_000
        try {
            val image = connection.inputStream.use(BitmapFactory::decodeStream) ?: return null
            val side = 192
            if (image.width <= side && image.height <= side) {
                image
            } else {
                val scale = side.toFloat() / maxOf(image.width, image.height)
                Bitmap.createScaledBitmap(image, (image.width * scale).toInt(), (image.height * scale).toInt(), true)
            }
        } finally {
            connection.disconnect()
        }
    }.getOrNull()
}
