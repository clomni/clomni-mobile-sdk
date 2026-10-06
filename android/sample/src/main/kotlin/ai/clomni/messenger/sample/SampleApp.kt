package ai.clomni.messenger.sample

import ai.clomni.messenger.Clomni
import ai.clomni.messenger.ClomniLogLevel
import android.app.Application
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging

class SampleApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Once, at start: a notification can start the app, and the messenger it opens needs the SDK ready.
        // App ID and the Android API key: Clomni panel → Channels → Mobile app.
        Clomni.initialize(this, appId = BuildConfig.CLOMNI_APP_ID, apiKey = BuildConfig.CLOMNI_API_KEY)
        // Integration mistakes (a wrong key or user_hash) and more show in logcat under the tag "Clomni".
        if (BuildConfig.DEBUG) Clomni.setLogLevel(ClomniLogLevel.DEBUG)
        // FCM only when the build had a google-services.json; the token can change, so hand it over at every start.
        if (FirebaseApp.getApps(this).isNotEmpty()) {
            FirebaseMessaging.getInstance().token.addOnSuccessListener(Clomni::setDeviceToken)
        }
    }
}
