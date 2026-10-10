package ai.clomni.messenger.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The app's screen in front, with screens as names; "messenger" is the SDK's own. */
class FrontScreensTest {
    private val screens = FrontScreens<String> { it == "messenger" }
    private val heard = mutableListOf<String>()
    private val listener = object : FrontScreens.Listener<String> {
        override fun resumed(screen: String) {
            heard += "resumed $screen"
        }

        override fun paused(screen: String) {
            heard += "paused $screen"
        }

        override fun destroyed(screen: String) {
            heard += "destroyed $screen"
        }
    }

    /**
     * Q-07 (test report, React Native): `initialize` came after MainActivity was resumed, and the launcher waited for
     * the next resume. Tracked from the process's start, the screen in front is told to a listener that comes late.
     */
    @Test
    fun aLateListenerHearsTheScreenInFrontAtOnce() {
        screens.resumed("main")
        screens.listener = listener
        assertEquals(listOf("resumed main"), heard)
        screens.resumed("messenger")
        screens.paused("main")
        assertEquals("the messenger's own screen is not the app's", "main", screens.last)
        assertNull("but main is not in front any more", screens.resumed)
        screens.resumed("main")
        assertEquals("main", screens.resumed)
        assertEquals(listOf("resumed main", "paused main", "resumed main"), heard)
    }

    @Test
    fun aPausedScreenIsNotToldAgain() {
        screens.resumed("main")
        screens.paused("main")
        screens.listener = listener
        assertEquals("not in front: nothing to show the launcher on", emptyList<String>(), heard)
        screens.destroyed("main")
        assertNull(screens.last)
    }

    /** `initialize` from an activity, with nothing tracked (the startup provider removed by the app): that one. */
    @Test
    fun theActivityInitializeCameFromStandsInWhenNothingIsTracked() {
        screens.adopt("main")
        assertEquals("main", screens.resumed)
        screens.resumed("rides")
        screens.adopt("main")
        assertEquals("tracked: the activity given changes nothing", "rides", screens.resumed)
        screens.adopt("messenger")
        assertEquals("rides", screens.last)
    }
}
