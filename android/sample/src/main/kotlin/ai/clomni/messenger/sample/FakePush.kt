package ai.clomni.messenger.sample

import ai.clomni.messenger.ClomniPush
import android.content.Context

/**
 * What the app's FirebaseMessagingService does with a message (android/docs/push.md), with a message made here:
 * the sample has no Firebase. The payload is what Clomni's server sends.
 */
object FakePush {
    private val operatorReply = mapOf(
        "clomni" to "1",
        "type" to "message",
        "conversation_id" to "conv_sample",
        "title" to "Leyla · Apar",
        "body" to "Gedişinizi yoxladıq, balansınıza 2 AZN qaytarıldı.",
        "unread_total" to "1",
    )

    fun deliver(context: Context) {
        // As in onMessageReceived: true, and shown, for Clomni's pushes; false for the app's own.
        ClomniPush.handle(context, operatorReply)
    }
}
