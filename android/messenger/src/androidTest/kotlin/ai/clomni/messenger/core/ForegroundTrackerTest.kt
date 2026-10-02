package ai.clomni.messenger.core

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList

/** The socket follows the app: open while one of its activities is started, closed when the app goes to the background. */
@RunWith(AndroidJUnit4::class)
class ForegroundTrackerTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test
    fun foregroundAndBackground() {
        val app = instrumentation.targetContext.applicationContext as Application
        val changes = CopyOnWriteArrayList<Boolean>()
        val tracker = ForegroundTracker(app) { changes += it }
        try {
            ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
                instrumentation.waitForIdleSync()
                assertEquals("an activity started: the foreground", listOf(true), changes)
                // A rotation stops the activity only to start its replacement: not the background.
                scenario.recreate()
                instrumentation.waitForIdleSync()
                assertEquals(listOf(true), changes)
            }
            instrumentation.waitForIdleSync()
            assertEquals("the last activity stopped: the background", false, changes.last())
            ActivityScenario.launch(ComponentActivity::class.java).use {
                instrumentation.waitForIdleSync()
                assertEquals("back again", true, changes.last())
            }
            instrumentation.waitForIdleSync()
            assertEquals(false, changes.last())
            assertEquals("never two in a row the same", changes.zipWithNext().none { (a, b) -> a == b }, true)
        } finally {
            app.unregisterActivityLifecycleCallbacks(tracker)
        }
    }
}
