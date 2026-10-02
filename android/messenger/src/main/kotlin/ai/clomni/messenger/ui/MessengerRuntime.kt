package ai.clomni.messenger.ui

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
import android.os.Bundle
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

    /** `Clomni.setNotificationIcon`; 0 is the app's own icon. */
    @Volatile
    var notificationIcon: Int = 0

    /** A token the app gave before `initialize`. */
    private var pendingToken: String? = null
    private val protocol = ProtocolJson(AndroidMessenger::protocolLog)

    private var launcherVisible: Boolean? = null
    private var bottomPadding: Int? = null
    private val pendingListeners = LinkedHashSet<UnreadCountListener>()
    private val tokens = HashMap<UnreadCountListener, UUID>()
    private val overlay = LauncherOverlay(ActivityLauncherSurface())
    private var front: WeakReference<Activity>? = null
    private var messenger: WeakReference<ClomniMessengerActivity>? = null
    private var opening = false

    fun initialize(context: Context, appId: String, apiKey: String, baseUrl: String) {
        if (engine != null) return ClomniLog.warning { "initialize was called before; the first call stays" }
        val app = context.applicationContext as Application
        val engine = AndroidMessenger.create(app, appId, apiKey, baseUrl)
        val coordinator = MessengerCoordinator(engine, null, waits, { main.post(it) }, { line -> ClomniLog.warning { line } }, events)
        coordinator.onChange = ::render
        launcherVisible?.let(coordinator::setLauncherVisible)
        bottomPadding?.let(coordinator::setBottomPadding)
        pendingListeners.forEach { tokens[it] = coordinator.addUnreadCountListener(it::onUnreadCountChanged) }
        pendingListeners.clear()
        val network = NetworkMonitor(app)
        root.offline = network.state.isOffline
        network.state.addListener { offline -> main.post { root.offline = offline } }
        app.registerActivityLifecycleCallbacks(Activities)
        this.app = app
        this.engine = engine
        this.coordinator = coordinator
        this.network = network
        pendingToken?.let(engine::setDeviceToken)
        pendingToken = null
        coordinator.start()
    }

    /** Runs [action] (a login) off the UI thread, then gets the messenger ready for the new session. */
    fun login(identity: UserIdentity?, action: (ClomniEngine) -> Future<Unit>) {
        val engine = engine ?: return ClomniLog.error { "call Clomni.initialize first" }
        this.identity = identity
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
        val strings = ClomniStrings(config?.languages?.firstOrNull() ?: Locale.getDefault().language, config?.strings.orEmpty())
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

    /** The known details for forms: name, email, phone. */
    val known: Map<String, String>
        get() = listOfNotNull(
            identity?.name?.let { "name" to it },
            identity?.email?.let { "email" to it },
            identity?.phone?.let { "phone" to it },
        ).toMap()

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

    /** It is gone; when the user closed it (system back, swipe), the messenger is closed. */
    fun detach(activity: ClomniMessengerActivity, closedByUser: Boolean) {
        if (messenger?.get() === activity) messenger = null
        if (closedByUser && !activity.replaced) coordinator?.dismiss()
    }

    /** Back: from a conversation to Home, from Home out. */
    fun back() {
        val coordinator = coordinator ?: return
        if (coordinator.route is MessengerRoute.Conversation) coordinator.navigate(MessengerRoute.Home) else coordinator.dismiss()
    }

    /** Brings Android in line with the coordinator. */
    private fun render() {
        val coordinator = coordinator ?: return
        root.route = coordinator.route
        root.ready = coordinator.readiness == MessengerCoordinator.Readiness.READY
        root.failed = coordinator.prepareFailed
        root.config = coordinator.config
        root.source = coordinator.source
        (coordinator.route as? MessengerRoute.Conversation)?.let { open -> app?.let { PushNotifier.cancel(it, open.id) } }
        val shown = messenger?.get()
        if (coordinator.route != null && shown == null && !opening) {
            open()
        } else if (coordinator.route == null && shown != null && !shown.isFinishing) {
            shown.finish()
        }
        overlay.update(coordinator.launcher, coordinator.config, AppTheme.override) { coordinator.present("launcher") }
    }

    private fun open() {
        val app = app ?: return
        val from = front?.get()?.takeUnless { it.isFinishing }
        val intent = Intent(from ?: app, ClomniMessengerActivity::class.java)
        if (from == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        opening = true
        try {
            (from ?: app).startActivity(intent)
            if (from != null && Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                @Suppress("DEPRECATION")
                from.overridePendingTransition(Motion.open(from), R.anim.clomni_stay)
            }
        } catch (e: RuntimeException) {
            opening = false
            ClomniLog.error { "the messenger cannot open: ${e.message}" }
        }
    }

    /** The app's activities: which is in front, for the launcher and for opening the messenger from it. */
    private object Activities : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(activity: Activity) {
            if (activity is ClomniMessengerActivity) return
            front = WeakReference(activity)
            overlay.resumed(activity)
        }

        override fun onActivityPaused(activity: Activity) {
            if (activity !is ClomniMessengerActivity) overlay.paused(activity)
        }

        override fun onActivityDestroyed(activity: Activity) {
            if (front?.get() === activity) front = null
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit

        override fun onActivityStarted(activity: Activity) = Unit

        override fun onActivityStopped(activity: Activity) = Unit

        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
    }
}
