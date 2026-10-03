package ai.clomni.messenger.core

import android.app.Activity
import android.app.Application
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The socket follows the app: open while one of its activities is started, closed when the app goes to the background.
 *
 * ActivityScenario starts helper activities of its own (androidx.test's bootstrap and empty activities, which on API 30
 * stay started after a scenario closes), so the expectation is not a fixed list: after each step the tracker must say
 * exactly what the platform's own count of started activities says.
 */
@RunWith(AndroidJUnit4::class)
class ForegroundTrackerTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    /** Activities started and not stopped, counted straight from the platform. */
    private class Started : Application.ActivityLifecycleCallbacks {
        val activities = mutableSetOf<Activity>()

        override fun onActivityStarted(activity: Activity) {
            activities += activity
        }

        override fun onActivityStopped(activity: Activity) {
            activities -= activity
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit

        override fun onActivityResumed(activity: Activity) = Unit

        override fun onActivityPaused(activity: Activity) = Unit

        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

        override fun onActivityDestroyed(activity: Activity) = Unit
    }

    @Test
    fun foregroundAndBackground() {
        val app = instrumentation.targetContext.applicationContext as Application
        val started = Started().also(app::registerActivityLifecycleCallbacks)
        val changes = CopyOnWriteArrayList<Boolean>()
        val tracker = ForegroundTracker(app) { changes += it }
        fun inStep(what: String) {
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                assertEquals(what, started.activities.isNotEmpty(), changes.lastOrNull() ?: false)
            }
        }
        try {
            ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
                inStep("an activity started: the foreground")
                assertEquals(true, changes.last())
                val before = changes.size
                // A rotation stops the activity only to start its replacement: not the background, no news at all.
                scenario.recreate()
                inStep("after a rotation")
                assertEquals("a rotation reports nothing", before, changes.size)
            }
            inStep("the scenario closed")
            ActivityScenario.launch(ComponentActivity::class.java).use { inStep("back again") }
            inStep("closed again")
            assertEquals("never two in a row the same", true, changes.zipWithNext().none { (a, b) -> a == b })
        } finally {
            app.unregisterActivityLifecycleCallbacks(tracker)
            app.unregisterActivityLifecycleCallbacks(started)
        }
    }
}
