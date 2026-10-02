package ai.clomni.messenger.core

import ai.clomni.messenger.BuildConfig
import ai.clomni.messenger.api.ApiClient
import ai.clomni.messenger.api.ApiConfiguration
import ai.clomni.messenger.api.Credentials
import ai.clomni.messenger.api.DeviceInfo
import ai.clomni.messenger.api.KeystoreSecureStore
import ai.clomni.messenger.api.SecureStore
import ai.clomni.messenger.log.ClomniLog
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
import okhttp3.OkHttpClient
import java.io.File
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/** Builds the engine inside an app: Keystore-backed credentials, files in `noBackupFilesDir`, socket by foreground. */
internal object AndroidMessenger {

    /**
     * Runs in `Clomni.initialize`, on the main thread: it touches neither the disk nor the network (brief 8·10,
     * initialize ≤ 50 ms). The files are only named here; the previous run's cache, the Keystore and the HTTP client
     * (which reads the system's certificates) are first used on the SDK's worker.
     */
    fun create(
        context: Context,
        appId: String,
        apiKey: String,
        baseUrl: String = ApiConfiguration.DEFAULT_BASE_URL,
    ): ClomniEngine {
        val app = context.applicationContext as Application
        // Context.noBackupFilesDir without its mkdir, which would be a disk write on the main thread.
        val noBackup = File(app.applicationInfo.dataDir, "no_backup/clomni/$appId")
        val engine = engine(
            ApiConfiguration(appId, apiKey, baseUrl),
            KeystoreSecureStore(File(noBackup, "secure"), appId),
            File(noBackup, "cache"),
            lazy(ApiClient::defaultClient),
        ) { deviceId -> deviceInfo(app, deviceId) }
        ForegroundTracker(app) { foreground ->
            if (foreground) engine.applicationWillEnterForeground() else engine.applicationDidEnterBackground()
        }
        return engine
    }

    /** The engine of [create] without Android's own pieces; what it does on the calling thread is tested on the JVM. */
    fun engine(
        configuration: ApiConfiguration,
        secure: SecureStore,
        cacheDir: File,
        http: Lazy<OkHttpClient>,
        device: (deviceId: String) -> DeviceInfo,
    ): ClomniEngine {
        val protocol = ProtocolJson(::protocolLog)
        val credentials = Credentials(secure, protocol)
        val api = ApiClient(configuration, credentials, protocol, { device(credentials.deviceId) }, http)
        return ClomniEngine(api, credentials, MessageStore(cacheDir, protocol), protocol, http)
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

    /** What the parser dropped is a warning; what it showed as its fallback (a newer server), information. */
    fun protocolLog(line: String) {
        if (line.endsWith("dropped")) ClomniLog.warning { line } else ClomniLog.info { line }
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
