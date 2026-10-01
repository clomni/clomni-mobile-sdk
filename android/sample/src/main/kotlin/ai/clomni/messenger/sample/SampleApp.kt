package ai.clomni.messenger.sample

import ai.clomni.messenger.Clomni
import android.app.Application

/** Brief 8·12: initialize once, from Application.onCreate. Nobody is logged in: present() starts as a visitor. */
class SampleApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Clomni.initialize(
            this,
            appId = BuildConfig.CLOMNI_APP_ID,
            apiKey = BuildConfig.CLOMNI_API_KEY,
            baseUrl = BuildConfig.CLOMNI_BASE_URL.ifEmpty { null },
        )
    }
}
