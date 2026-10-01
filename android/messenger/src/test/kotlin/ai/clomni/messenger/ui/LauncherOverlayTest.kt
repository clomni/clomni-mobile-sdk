package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.LauncherState
import ai.clomni.messenger.protocol.MessengerConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The launcher's placement on the app's screens, with screens as names: what it asks the windows for. */
class LauncherOverlayTest {
    private val asked = mutableListOf<String>()
    private val overlay = LauncherOverlay(
        object : LauncherOverlay.Surface<String> {
            override fun show(screen: String, state: LauncherState, config: MessengerConfig?, tap: () -> Unit) {
                asked += "show $screen ${state.badge ?: "-"}"
            }

            override fun hide(screen: String) {
                asked += "hide $screen"
            }
        },
    )
    private val on = LauncherState(MessengerConfig.LauncherPosition.RIGHT, 20, "3", "Bizə mesaj göndərin")

    /** Brief 7.2, "Bitdi": with the launcher off, no view is made on any screen, whatever the app does. */
    @Test
    fun offMeansNoViewAtAll() {
        overlay.resumed("profile")
        overlay.update(null, null) {}
        overlay.paused("profile")
        overlay.resumed("rides")
        overlay.update(null, null) {}
        overlay.paused("rides")
        assertTrue(asked.toString(), asked.isEmpty())
    }

    @Test
    fun itFollowsTheScreenInFront() {
        overlay.update(on, null) {}
        assertTrue("no screen in front yet", asked.isEmpty())
        overlay.resumed("profile")
        overlay.update(on.copy(badge = "99+"), null) {}
        overlay.paused("profile")
        overlay.resumed("rides")
        overlay.update(null, null) {}
        overlay.update(on, null) {}
        overlay.paused("other")
        assertEquals(
            listOf("show profile 3", "show profile 99+", "hide profile", "show rides 99+", "hide rides", "show rides 3"),
            asked,
        )
    }
}
