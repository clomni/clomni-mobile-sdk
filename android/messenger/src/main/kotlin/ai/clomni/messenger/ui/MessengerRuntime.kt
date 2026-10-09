package ai.clomni.messenger.ui

import ai.clomni.messenger.BuildConfig
import ai.clomni.messenger.R
import ai.clomni.messenger.UnreadCountListener
import ai.clomni.messenger.api.UserIdentity
import ai.clomni.messenger.core.AndroidMessenger
import ai.clomni.messenger.core.ClomniEngine
import ai.clomni.messenger.core.NetworkMonitor
import ai.clomni.messenger.log.ClomniLog
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.MessengerCoordinator
import ai.clomni.messenger.presentation.MessengerEvents
import ai.clomni.messenger.presentation.MessengerRoute
import ai.clomni.messenger.presentation.PushNotification
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.presentation.ThemeOverride
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.ProtocolJson
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.lang.ref.WeakReference
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.Future

/** The coordinator's state for Compose, written on the UI thread. */
internal class RootState {
    var route by mutableStateOf<MessengerRoute?>(null)
    var ready by mutableStateOf(false)
    var failed by mutableStateOf(false)
    var config by mutableStateOf<MessengerConfig?>(null)
    var source by mutableStateOf<String?>(null)
    var offline by mutableStateOf(false)
    var userName by mutableStateOf<String?>(null)
}

/**
 * Holds the engine and the coordinator, and does what the coordinator says in Android and nothing more: starts the
 * messenger's own activity while it is open (sliding up; closing returns the app to where it was), and puts the
 * launcher on the app's activity in front only while the launcher shows. With the launcher off and the messenger
 * closed it touches no activity at all. Everything here runs on the UI thread.
 */
internal object MessengerRuntime {
    private val main = Handler(Looper.getMainLooper())
    private val waits = Executors.newCachedThreadPool { Thread(it, "clomni-runtime").apply { isDaemon = true } }

    var engine: ClomniEngine? = null
        private set
    var coordinator: MessengerCoordinator? = null
        private set
    private var network: NetworkMonitor? = null
    private var app: Application? = null

    /** Kept here so callbacks set before `initialize` are not lost. */
    val events = MessengerEvents()
    val root = RootState()

    /** The logged-in user's details: the Home greeting and form prefills. */
    var identity: UserIdentity? = null
        private set

    /** `Clomni.setLanguage`: the host's language, null to follow the phone (DESIGN-PASS-3 D1). */
    var language: String? = null
        private set

    /** `Clomni.setNotificationIcon`; 0 is the app's own icon. */
    @Volatile
    var notificationIcon: Int = 0

    /** Device tests: a server address that answers nothing, so no test talks to Clomni's own. */
    @Volatile
    internal var baseUrlForTests: String? = null

    /** A token the app gave before `initialize`. */
    private var pendingToken: String? = null
    private val protocol = ProtocolJson(AndroidMessenger::protocolLog)

    /** The device's network ([NetworkMonitor]) and the server's answers ([ai.clomni.messenger.core.ClomniChange.Connection]). */
    private var networkOffline = false
    private var reachable = true

    private var launcherVisible: Boolean? = null
    private var bottomPadding: Int? = null
    private val pendingListeners = LinkedHashSet<UnreadCountListener>()
    private val tokens = HashMap<UnreadCountListener, UUID>()
    private val overlay = LauncherOverlay(ActivityLauncherSurface())
    private val screens get() = AppActivities.screens
    private var messenger: WeakReference<ClomniMessengerActivity>? = null
    private var opening = false

    /** The messenger's activity went while it was open, not by the user (G-16): it comes back over the app's screen. */
    private var lost = false

    /**
     * [activity]: the one `Clomni.initialize` was called from, if it was; the app's screen in front is known anyway
     * from the process's start ([ClomniStartup]), so a late `initialize` (React Native, Flutter, Unity) shows the
     * launcher at once (Q-07).
     */
    fun initialize(context: Context, appId: String, apiKey: String, baseUrl: String, activity: Activity? = null) {
        if (engine != null) return ClomniLog.warning { "initialize was called before; the first call stays" }
        val url = baseUrlForTests ?: baseUrl
        ClomniLog.info { "initialize: SDK ${BuildConfig.SDK_VERSION}, app $appId, $url" }
        val app = context.applicationContext as Application
        val engine = AndroidMessenger.create(app, appId, apiKey, url)
        val coordinator = MessengerCoordinator(engine, language, waits, { main.post(it) }, { line -> ClomniLog.warning { line } }, events)
        coordinator.onChange = ::render
        launcherVisible?.let(coordinator::setLauncherVisible)
        bottomPadding?.let(coordinator::setBottomPadding)
        pendingListeners.forEach { tokens[it] = coordinator.addUnreadCountListener(it::onUnreadCountChanged) }
        pendingListeners.clear()
        val network = NetworkMonitor(app)
        root.offline = network.state.isOffline
        // The capsule says offline while the device has no network, or has one that does not reach the server; the
        // network's return sends what waits in the outbox at once (G-17).
        network.state.addListener { offline ->
            main.post {
                networkOffline = offline
                root.offline = offline || !reachable
            }
            if (!offline) engine.networkAvailable()
        }
        engine.observe { change ->
            if (change is ai.clomni.messenger.core.ClomniChange.Connection) {
                main.post {
                    reachable = change.reachable
                    root.offline = networkOffline || !reachable
                }
            }
        }
        networkOffline = network.state.isOffline
        this.app = app
        this.engine = engine
        this.coordinator = coordinator
        this.network = network
        AppActivities.register(app)
        activity?.takeUnless { it.isFinishing }?.let(screens::adopt)
        // Hears the screen already in front at once.
        screens.listener = Screens
        pendingToken?.let(engine::setDeviceToken)
        pendingToken = null
        coordinator.start()
    }

    /** Runs [action] (a login) off the UI thread, then gets the messenger ready for the new session. */
    fun login(identity: UserIdentity?, action: (ClomniEngine) -> Future<Unit>) {
        val engine = engine ?: return ClomniLog.error { "call Clomni.initialize first" }
        this.identity = identity
        coordinator?.loggedIn(identity?.name)
        waits.execute {
            runCatching { action(engine).get() }.onFailure { ClomniLog.error { "login failed: ${it.cause ?: it}" } }
            main.post { coordinator?.start() }
        }
    }

    fun updateUser(fields: kotlinx.serialization.json.JsonObject) {
        val engine = engine ?: return ClomniLog.error { "call Clomni.initialize first" }
        waits.execute {
            runCatching { engine.updateUser(fields).get() }.onFailure { ClomniLog.error { "updateUser failed: ${it.cause ?: it}" } }
        }
    }

    fun logout() {
        val engine = engine ?: return
        identity = null
        coordinator?.loggedOut()
        engine.logout()
        app?.let { waits.execute { ClomniImages.clear(it) } }
    }

    fun setDeviceToken(token: String) {
        engine?.setDeviceToken(token) ?: run { pendingToken = token }
    }

    /**
     * A Clomni push (on FCM's thread): its count to the listeners, and a notification unless the messenger is open.
     * One this SDK cannot read is logged and still shown.
     */
    fun pushReceived(context: Context, data: Map<String, String>) {
        val push = protocol.parsePush(data)
        if (coordinator?.received(push) == false) return
        val config = coordinator?.config
        val strings = ClomniStrings.of(config, language)
        val label = context.applicationInfo.loadLabel(context.packageManager).toString()
        val notification = PushNotification.of(push, data, strings, label)
        val color = (AppTheme.override.primaryColor ?: config?.brand?.primaryColor?.let(RgbColor::parse))?.argb
        val post = { PushNotifier.post(context, notification, notificationIcon, color) }
        if (Looper.myLooper() == Looper.getMainLooper()) waits.execute(post) else post()
    }

    /** A tap on a Clomni notification, in the messenger's activity. */
    fun openFromPush(conversationId: String?) {
        coordinator?.openFromPush(conversationId) ?: ClomniLog.error { "call Clomni.initialize first" }
    }

    fun setLauncherVisible(visible: Boolean) {
        launcherVisible = visible
        coordinator?.setLauncherVisible(visible)
    }

    /** `Clomni.setTheme`: the open screens redraw by themselves (it is Compose state); the launcher is told here. */
    fun setTheme(override: ThemeOverride) {
        AppTheme.override = override
        render()
    }

    fun setLanguage(language: String?) {
        this.language = language
        coordinator?.setLanguage(language)
    }

    fun setBottomPadding(padding: Int) {
        bottomPadding = padding
        coordinator?.setBottomPadding(padding)
    }

    fun addUnreadCountListener(listener: UnreadCountListener) {
        val coordinator = coordinator
        if (coordinator == null) {
            pendingListeners += listener
            listener.onUnreadCountChanged(0)
        } else {
            tokens[listener] = coordinator.addUnreadCountListener(listener::onUnreadCountChanged)
        }
    }

    fun removeUnreadCountListener(listener: UnreadCountListener) {
        pendingListeners.remove(listener)
        tokens.remove(listener)?.let { coordinator?.removeUnreadCountListener(it) }
    }

    /** The known details for forms: name, email, phone; the user kept from an earlier launch until the app logs in. */
    val known: Map<String, String>
        get() {
            val user = identity ?: coordinator?.keptUser
            return listOfNotNull(
                user?.name?.let { "name" to it },
                user?.email?.let { "email" to it },
                user?.phone?.let { "phone" to it },
            ).toMap()
        }

    // The messenger's activity

    fun attach(activity: ClomniMessengerActivity) {
        // A notification tapped while the messenger was open behind the app: the new one takes over.
        messenger?.get()?.takeIf { it !== activity && !it.isFinishing }?.let {
            it.replaced = true
            it.finish()
        }
        messenger = WeakReference(activity)
        opening = false
    }

    /**
     * It is gone. Closed by the user (✕, back, pulled down) the coordinator closed first, so [finishing] with the
     * messenger still open means Android took the screen away: an app's singleTask activity started again from its
     * icon clears what is above it (G-16, React Native's template). It comes back when the app's screen is in front.
     */
    fun detach(activity: ClomniMessengerActivity, finishing: Boolean) {
        // An instance another one already took over from says nothing.
        if (messenger?.get() !== activity) return
        messenger = null
        if (!finishing || activity.replaced) return
        if (coordinator?.route != null) {
            lost = true
            ClomniLog.debug { "messenger: its screen was taken away while open; it comes back" }
            render()
        }
    }

    /** Back: to the screen this one was opened from; from the first one, out. */
    fun back() {
        coordinator?.back()
    }

    /** Brings Android in line with the coordinator. */
    private fun render() {
        val coordinator = coordinator ?: return
        root.route = coordinator.route
        root.ready = coordinator.readiness == MessengerCoordinator.Readiness.READY
        root.failed = coordinator.prepareFailed
        root.config = coordinator.config
        root.source = coordinator.source
        root.userName = coordinator.userName
        (coordinator.route as? MessengerRoute.Conversation)?.let { open -> app?.let { PushNotifier.cancel(it, open.id) } }
        val shown = messenger?.get()
        if (coordinator.route == null) lost = false
        // Opened from the app's screen in front; while the app is in the background, when it comes back.
        if (coordinator.route != null && shown == null && !opening && (screens.last == null || screens.resumed != null)) {
            open()
        } else if (coordinator.route == null && shown != null && !shown.isFinishing) {
            shown.closeAnimated()
        }
        overlay.update(coordinator.launcher, coordinator.config, AppTheme.override) { coordinator.present("launcher") }
    }

    private fun open() {
        val app = app ?: return
        val from = screens.last?.takeUnless { it.isFinishing }
        val intent = Intent(from ?: app, ClomniMessengerActivity::class.java)
        if (from == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        // Back where it was taken away: no sliding up again.
        if (lost) intent.putExtra(ClomniMessengerActivity.EXTRA_RESTORED, true)
        lost = false
        opening = true
        try {
            (from ?: app).startActivity(intent)
            if (from != null && Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                @Suppress("DEPRECATION")
                from.overridePendingTransition(0, 0)
            }
        } catch (e: RuntimeException) {
            opening = false
            ClomniLog.error { "the messenger cannot open: ${e.message}" }
        }
    }

    /** The app's screens: the launcher stands on the one in front, and an open messenger waits for one to open over. */
    private object Screens : FrontScreens.Listener<Activity> {
        override fun resumed(screen: Activity) {
            // A start that never attached (Android refused it) is not still on its way.
            if (messenger?.get() == null) opening = false
            overlay.resumed(screen)
            render()
        }

        override fun paused(screen: Activity) = overlay.paused(screen)

        override fun destroyed(screen: Activity) = Unit
    }
}
