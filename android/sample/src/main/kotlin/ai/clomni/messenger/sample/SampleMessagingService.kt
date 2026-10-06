package ai.clomni.messenger.sample

import ai.clomni.messenger.Clomni
import ai.clomni.messenger.ClomniPush
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** What a host app writes for Clomni's pushes (android/docs/push.md): hand over the token, let Clomni show its own. */
class SampleMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Clomni.setDeviceToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        ClomniPush.handle(this, message.data)
    }
}
