package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.Fixture
import ai.clomni.messenger.presentation.LauncherState
import ai.clomni.messenger.protocol.MessengerConfig
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** The optional launcher (brief 8·7.2, 4.4): 56 dp, the brand colour, the unread badge, on an app's screen. */
class LauncherSnapshotTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5, theme = "android:Theme.Material.Light.NoActionBar")

    private val state = LauncherState(MessengerConfig.LauncherPosition.RIGHT, 20, "3", "Bizə mesaj göndərin, Oxunmamış mesaj var")

    /** An app's own screen with the launcher in its corner, as ActivityLauncherSurface puts it there. */
    private fun screen(vararg launchers: Pair<LauncherState, Boolean>): ViewGroup {
        val context = paparazzi.context
        return FrameLayout(context).apply {
            setBackgroundColor(0xFFF2F2F7.toInt())
            addView(
                TextView(context).apply {
                    text = "Gedişlər"
                    textSize = 30f
                    setPadding(48, 48, 48, 48)
                },
                FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP),
            )
            for ((launcher, dark) in launchers) {
                addView(LauncherView(context).apply { bind(launcher, ClomniTheme.make(Fixture.aparConfig.brand, dark)) {} })
            }
        }
    }

    @Test
    fun onAnAppScreen() {
        paparazzi.snapshot(screen(state to false), "launcher_right_badge")
    }

    @Test
    fun leftAboveATabBarWithManyUnread() {
        paparazzi.snapshot(screen(state.copy(side = MessengerConfig.LauncherPosition.LEFT, bottomPadding = 64, badge = "99+") to false), "launcher_left_99")
    }

    @Test
    fun darkWithoutBadge() {
        paparazzi.snapshot(screen(state.copy(badge = null) to true), "launcher_dark")
    }

    @Test
    fun itsSizeAndLabel() {
        val view = LauncherView(paparazzi.context).apply { bind(state, ClomniTheme.make(null, false)) {} }
        val density = paparazzi.context.resources.displayMetrics.density
        assertEquals("56 dp and room for the badge and the shadow", ((56 + 32) * density).toInt(), view.layoutParams.width)
        assertEquals("Bizə mesaj göndərin, Oxunmamış mesaj var", view.contentDescription)
        val params = view.layoutParams as FrameLayout.LayoutParams
        assertEquals(Gravity.BOTTOM or Gravity.END, params.gravity)
        assertEquals("20 dp from the edge, minus that room", ((20 - 16) * density).toInt(), params.marginEnd)
        assertEquals(((20 - 16 + 20) * density).toInt(), params.bottomMargin)
        assertEquals("it gives from its centre", ((16 + 28) * density), view.pivotX, 0.5f)
        view.isPressed = true
        assertTrue(view.isPressed)
        assertTrue("white lines on the default dark brand", view.whiteLines)
        val light = ai.clomni.messenger.presentation.ChatFixture.config("""{"brand":{"primary_color":"#FFE14D"}}""").brand
        val onLight = LauncherView(paparazzi.context).apply { bind(state, ClomniTheme.make(light, false)) {} }
        assertFalse("black lines where on_primary is dark", onLight.whiteLines)
    }
}
