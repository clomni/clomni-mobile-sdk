package ai.clomni.messenger.ui

import ai.clomni.messenger.Clomni
import android.app.Activity
import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith

/** An app's main activity with React Native's launchMode. */
class SingleTaskHost : ComponentActivity()

/**
 * The messenger over the app's activities, on a device: what the SDK knows before `initialize` (Q-07), and the
 * messenger Android takes away from a singleTask app (G-16).
 */
@RunWith(AndroidJUnit4::class)
class MessengerRestoreTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    private inline fun <reified T : Activity> resumed(): T? {
        var found: T? = null
        instrumentation.runOnMainSync {
            found = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED).filterIsInstance<T>().firstOrNull()
        }
        return found
    }

    private fun <T : Any> waitFor(what: String, check: () -> T?): T {
        val deadline = System.currentTimeMillis() + 15_000
        while (true) {
            check()?.let { return it }
            if (System.currentTimeMillis() > deadline) throw AssertionError("timed out waiting for: $what")
            Thread.sleep(100)
        }
    }

    /**
     * Q-07 (test report, React Native): `initialize` came from JS after MainActivity was resumed, and the launcher
     * waited for the next resume. The SDK follows the app's activities from the process's start (its startup
     * provider), so the screen in front is known whenever `initialize` comes, and a late listener hears it at once.
     */
    @Test
    fun theScreenInFrontIsKnownBeforeInitialize() {
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                assertSame(activity, AppActivities.screens.resumed)
                val heard = mutableListOf<Activity>()
                val late = object : FrontScreens.Listener<Activity> {
                    override fun resumed(screen: Activity) {
                        heard += screen
                    }

                    override fun paused(screen: Activity) = Unit

                    override fun destroyed(screen: Activity) = Unit
                }
                val runtime = AppActivities.screens.listener
                AppActivities.screens.listener = late
                AppActivities.screens.listener = runtime
                assertSame("a listener that comes late hears the screen in front at once", activity, heard.single())
            }
        }
    }

    /**
     * G-16 (test report): React Native's MainActivity is singleTask; started again from the app's icon, Android clears
     * every activity above it, the messenger's too. The messenger was still open, so it comes back over the app.
     */
    @Test
    fun theMessengerComesBackOverASingleTaskApp() {
        MessengerRuntime.baseUrlForTests = NOWHERE
        instrumentation.runOnMainSync { Clomni.initialize(context, "app_g16", "android_sdk-g16") }
        val host = Intent(context, SingleTaskHost::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(host)
        waitFor("the app's activity") { resumed<SingleTaskHost>() }
        instrumentation.runOnMainSync { Clomni.present("g16") }
        val first = waitFor("the messenger") { resumed<ClomniMessengerActivity>() }

        // The app's icon: the same activity started again.
        context.startActivity(host)
        waitFor("Android took the messenger away") { first.isDestroyed.takeIf { it } }
        val again = waitFor("the messenger back") { resumed<ClomniMessengerActivity>()?.takeIf { it !== first } }
        assertNotSame(first, again)
        instrumentation.runOnMainSync { assertNotNull("still open where it was", MessengerRuntime.coordinator?.route) }

        instrumentation.runOnMainSync { Clomni.dismiss() }
        waitFor("closed by the app") { again.isDestroyed.takeIf { it } }
        instrumentation.runOnMainSync { org.junit.Assert.assertNull(MessengerRuntime.coordinator?.route) }
        // Closed by the app (or the user): it does not come back.
        context.startActivity(host)
        waitFor("the app's activity") { resumed<SingleTaskHost>() }
        Thread.sleep(500)
        org.junit.Assert.assertNull(resumed<ClomniMessengerActivity>())
    }

    companion object {
        /** The discard port on the device itself: refused at once. */
        const val NOWHERE = "http://127.0.0.1:9/v1"
    }
}
