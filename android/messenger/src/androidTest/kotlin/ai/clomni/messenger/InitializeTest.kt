package ai.clomni.messenger

import android.os.Build
import android.os.StrictMode
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Brief 8·10: `Clomni.initialize` takes the main thread for at most 50 ms, and does no disk or network work there.
 * StrictMode reports every disk read, disk write and network call on the main thread while it runs (to a listener,
 * not penaltyDeath, which would take the test runner down with it and say nothing).
 */
@RunWith(AndroidJUnit4::class)
class InitializeTest {
    @Test
    fun initializeIsQuickAndTouchesNoDiskOrNetwork() {
        assumeTrue("StrictMode's listener is API 28+", Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val app = instrumentation.targetContext.applicationContext
        val violations = CopyOnWriteArrayList<String>()
        var tookMs = 0.0
        var previous: StrictMode.ThreadPolicy? = null
        instrumentation.runOnMainSync {
            previous = StrictMode.getThreadPolicy()
            StrictMode.setThreadPolicy(
                StrictMode.ThreadPolicy.Builder()
                    .detectDiskReads()
                    .detectDiskWrites()
                    .detectNetwork()
                    .penaltyListener({ it.run() }) { violation -> violations += violation.stackTraceToString().lines().take(12).joinToString("\n") }
                    .build(),
            )
            val start = SystemClock.elapsedRealtimeNanos()
            Clomni.initialize(app, "app_strict", "android_sdk-strict")
            tookMs = (SystemClock.elapsedRealtimeNanos() - start) / 1e6
        }
        // StrictMode reports a main-thread violation once the message that caused it is done.
        instrumentation.waitForIdleSync()
        instrumentation.runOnMainSync { StrictMode.setThreadPolicy(previous) }
        assertEquals(emptyList<String>(), violations)
        assertTrue("initialize took %.1f ms".format(tookMs), tookMs <= 50.0)
    }
}
