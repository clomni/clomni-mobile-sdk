package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.MessengerTab
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.presentation.TabBar
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs

/**
 * Contract 1.0.7b §5.2: the unread badge is wholly inside the tab bar. On iOS its top stood over the bar's top line,
 * which cut across it. The bar is drawn with "99+" and read pixel by pixel: the badge's red starts at least 4 dp (and
 * its 1.5 dp ring) under the line, ends inside the bar, and the line is whole above it.
 */
@RunWith(AndroidJUnit4::class)
class TabBadgeTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun insideTheBarLight() = check(dark = false)

    @Test
    fun insideTheBarDark() = check(dark = true)

    private fun check(dark: Boolean) {
        val theme = ClomniTheme.make(null, dark)
        val bar = TabBar(
            listOf(
                TabBar.Tab(MessengerTab.HOME, "Əsas səhifə"),
                TabBar.Tab(MessengerTab.MESSAGES, "Söhbətlər", badge = "99+"),
                TabBar.Tab(MessengerTab.NEWS, "Xəbərlər"),
                TabBar.Tab(MessengerTab.FAQ, "Suallar"),
            ),
        )
        compose.setContent { Box(Modifier.testTag("bar")) { MessengerTabBar(bar, MessengerTab.HOME, theme) {} } }
        val image = compose.onNodeWithTag("bar").captureToImage().asAndroidBitmap()
        val density = InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics.density
        val red = (0 until image.height).filter { y -> (0 until image.width).any { x -> image.getPixel(x, y).near(theme.colors.unread) } }
        assertTrue("the badge is drawn", red.isNotEmpty())
        // The line is 1 dp; then 4 dp of room and the ring's 1.5 dp before the red.
        assertTrue("red from row ${red.first()}, at least ${(6 * density).toInt()}", red.first() >= (6 * density).toInt())
        assertTrue("red down to row ${red.last()} of ${image.height}", red.last() < image.height - 1)
        val line = (0 until density.toInt()).all { y -> (0 until image.width).all { x -> image.getPixel(x, y).near(theme.colors.border) } }
        assertTrue("the bar's line is whole", line)
    }

    private fun Int.near(color: RgbColor): Boolean {
        val c = color.argb
        return abs(android.graphics.Color.red(this) - android.graphics.Color.red(c)) <= 8 &&
            abs(android.graphics.Color.green(this) - android.graphics.Color.green(c)) <= 8 &&
            abs(android.graphics.Color.blue(this) - android.graphics.Color.blue(c)) <= 8
    }
}
