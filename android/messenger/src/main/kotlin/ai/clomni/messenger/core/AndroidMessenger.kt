package ai.clomni.messenger.core

import ai.clomni.messenger.BuildConfig
import ai.clomni.messenger.api.ApiClient
import ai.clomni.messenger.api.ApiConfiguration
import ai.clomni.messenger.api.Credentials
import ai.clomni.messenger.api.DeviceInfo
import ai.clomni.messenger.api.KeystoreSecureStore
import ai.clomni.messenger.presentation.ChatController
import ai.clomni.messenger.presentation.HomeController
import ai.clomni.messenger.presentation.Scheduler
import ai.clomni.messenger.protocol.ProtocolJson
import ai.clomni.messenger.store.MessageStore
import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/** Builds the engine inside an app: Keystore-backed credentials, files in `noBackupFilesDir`, socket by foreground. */
internal object AndroidMessenger {
    private const val TAG = "Clomni"

    fun create(
        context: Context,
        appId: String,
        apiKey: String,
        baseUrl: String = ApiConfiguration.DEFAULT_BASE_URL,
    ): ClomniEngine {
        val app = context.applicationContext as Application
        val log: (String) -> Unit = { Log.d(TAG, it) }
        val protocol = ProtocolJson(log)
        val credentials = Credentials(KeystoreSecureStore(app, appId), protocol)
        val http = ApiClient.defaultClient()
        val device = { deviceInfo(app, credentials.deviceId) }
        val api = ApiClient(ApiConfiguration(appId, apiKey, baseUrl), credentials, protocol, device, http)
        val store = MessageStore(File(app.noBackupFilesDir, "clomni/$appId/cache"), protocol)
        val engine = ClomniEngine(api, credentials, store, protocol, http, log = log)
        ForegroundTracker(app) { foreground ->
            if (foreground) engine.applicationWillEnterForeground() else engine.applicationDidEnterBackground()
        }
        return engine
    }

    /**
     * What `ClomniMessenger` (the Compose screen) is built on: the engine's state on the UI thread, waits on a worker
     * of their own. [language] null follows the config; [userName] is for the greeting.
     */
    fun homeController(engine: ClomniEngine, language: String?, userName: String?): HomeController {
        val ui = Handler(Looper.getMainLooper())
        return HomeController(engine, language, userName, SerialExecutor(pool), main = { ui.post(it) })
    }

    /** Threads for the screens' waits; idle ones end after a minute, so opening the messenger again leaks none. */
    private val pool = Executors.newCachedThreadPool { Thread(it, "clomni-ui").apply { isDaemon = true } }

    /**
     * What `ClomniChat` (the conversation screen) is built on, like [homeController]. [known] is the user's name, email
     * and phone for prefilling forms.
     */
    fun chatController(
        engine: ClomniEngine,
        conversationId: String,
        language: String?,
        known: Map<String, String> = emptyMap(),
    ): ChatController {
        val ui = Handler(Looper.getMainLooper())
        val worker = SerialExecutor(pool)
        val scheduler = Scheduler { delayMs, action ->
            val runnable = Runnable(action)
            ui.postDelayed(runnable, delayMs)
            return@Scheduler { ui.removeCallbacks(runnable) }
        }
        return ChatController(engine, conversationId, language, worker, main = { ui.post(it) }, scheduler, known)
    }

    fun deviceInfo(context: Context, deviceId: String): DeviceInfo = DeviceInfo(
        deviceId = deviceId,
        osVersion = Build.VERSION.RELEASE,
        appVersion = runCatching {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull(),
        sdkVersion = BuildConfig.SDK_VERSION,
        locale = Locale.getDefault().toLanguageTag(),
        timezone = TimeZone.getDefault().id,
        model = Build.MODEL,
    )
}

/** Runs its tasks one at a time, in order, on [pool]'s threads (the Executor documentation's SerialExecutor). */
internal class SerialExecutor(private val pool: Executor) : Executor {
    private val tasks = ArrayDeque<Runnable>()
    private var active: Runnable? = null

    @Synchronized
    override fun execute(command: Runnable) {
        tasks.addLast(
            Runnable {
                try {
                    command.run()
                } finally {
                    next()
                }
            },
        )
        if (active == null) next()
    }

    @Synchronized
    private fun next() {
        active = tasks.removeFirstOrNull()
        active?.let(pool::execute)
    }
}

/**
 * Foreground while at least one activity of the app is started. Plain activity callbacks rather than
 * ProcessLifecycleOwner, which would add androidx.lifecycle to every app's dependencies.
 */
internal class ForegroundTracker(app: Application, private val onChange: (Boolean) -> Unit) :
    Application.ActivityLifecycleCallbacks {
    private var started = 0

    init {
        app.registerActivityLifecycleCallbacks(this)
    }

    override fun onActivityStarted(activity: Activity) {
        if (started++ == 0) onChange(true)
    }

    override fun onActivityStopped(activity: Activity) {
        // A configuration change stops the activity only to start its replacement: not a trip to the background.
        if (--started == 0 && !activity.isChangingConfigurations) onChange(false)
        if (started < 0) started = 0
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit

    override fun onActivityResumed(activity: Activity) = Unit

    override fun onActivityPaused(activity: Activity) = Unit

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

    override fun onActivityDestroyed(activity: Activity) = Unit
}
