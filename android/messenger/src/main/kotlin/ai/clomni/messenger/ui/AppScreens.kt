package ai.clomni.messenger.ui

import android.app.Activity
import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import java.lang.ref.WeakReference

/**
 * Which of the app's screens is in front, known from whenever tracking began rather than from when the runtime first
 * listens (test report Q-07: React Native calls `initialize` from JS after MainActivity was resumed, and the launcher
 * waited for the next resume). A listener that arrives late hears the screen in front at once. The messenger's own
 * screen is not one of the app's ([isOwn]). Screens are held weakly. On the UI thread.
 */
internal class FrontScreens<S : Any>(private val isOwn: (S) -> Boolean) {
    interface Listener<S> {
        fun resumed(screen: S)

        fun paused(screen: S)

        fun destroyed(screen: S)
    }

    private var front: WeakReference<S>? = null
    private var inFront = false

    /** The app's screen last resumed, while it is not gone. */
    val last: S? get() = front?.get()

    /** The app's screen that is resumed now, if any. */
    val resumed: S? get() = if (inFront) front?.get() else null

    var listener: Listener<S>? = null
        set(value) {
            field = value
            resumed?.let { value?.resumed(it) }
        }

    fun resumed(screen: S) {
        if (isOwn(screen)) return
        front = WeakReference(screen)
        inFront = true
        listener?.resumed(screen)
    }

    fun paused(screen: S) {
        if (isOwn(screen)) return
        if (front?.get() === screen) inFront = false
        listener?.paused(screen)
    }

    fun destroyed(screen: S) {
        if (isOwn(screen)) return
        if (front?.get() === screen) {
            front = null
            inFront = false
        }
        listener?.destroyed(screen)
    }

    /** `Clomni.initialize` was given an activity: the one in front when nothing was tracked yet. */
    fun adopt(screen: S) {
        if (front?.get() != null || isOwn(screen)) return
        resumed(screen)
    }
}

/** The app's activities for the messenger, tracked from the process's start ([ClomniStartup]). */
internal object AppActivities : Application.ActivityLifecycleCallbacks {
    val screens = FrontScreens<Activity> { it is ClomniMessengerActivity }
    private var registered = false

    /** Once per process; the startup provider does it before the app's own code runs, `initialize` again if not. */
    fun register(app: Application) {
        if (registered) return
        registered = true
        app.registerActivityLifecycleCallbacks(this)
    }

    override fun onActivityResumed(activity: Activity) = screens.resumed(activity)

    override fun onActivityPaused(activity: Activity) = screens.paused(activity)

    override fun onActivityDestroyed(activity: Activity) = screens.destroyed(activity)

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit

    override fun onActivityStarted(activity: Activity) = Unit

    override fun onActivityStopped(activity: Activity) = Unit

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
}

/**
 * Starts following the app's activities when the process starts, before `Application.onCreate` and long before a
 * React Native, Flutter or Unity app calls `initialize`: nothing else, no disk, no network. The way Firebase and the
 * AndroidX startup library begin, without adding a dependency.
 */
internal class ClomniStartup : ContentProvider() {
    override fun onCreate(): Boolean {
        (context?.applicationContext as? Application)?.let(AppActivities::register)
        return true
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
