package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ClomniTheme
import ai.clomni.messenger.presentation.MessengerTab
import ai.clomni.messenger.presentation.TabBar
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsNodeInteractionCollection
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * CM-347 (contract 1.0.7b §3, §5.1). Going back to a tab finds it as it was: on Android Home used to be built again,
 * its scroll back at the top. And a screen opens the way the operator asked: the one before gone at once, the spinner
 * alone in the middle for at least 350 ms and until the data is there, then the screen; never two screens at once.
 * Home here is a long scrolled page that counts how often it is built.
 */
@RunWith(AndroidJUnit4::class)
class TabPagesTest {
    @get:Rule
    val compose = createComposeRule()

    private val bar = TabBar(
        listOf(
            TabBar.Tab(MessengerTab.HOME, "Əsas səhifə"),
            TabBar.Tab(MessengerTab.MESSAGES, "Söhbətlər", badge = "7", accessibilityLabel = "Söhbətlər, 7 oxunmamış"),
        ),
    )
    private val theme = ClomniTheme.make(null, false)

    /** How many times Home's page was built. */
    private var builds = 0

    @Composable
    private fun Page(tab: MessengerTab) {
        if (tab == MessengerTab.HOME) {
            remember { builds++ }
            Column(Modifier.fillMaxSize().testTag("home").verticalScroll(rememberScrollState())) {
                repeat(60) { BasicText("Sətir $it", Modifier.fillMaxWidth().height(48.dp)) }
            }
        } else {
            BasicText("Söhbətlərin siyahısı", Modifier.fillMaxSize().testTag("messages"))
        }
    }

    /** Where Home is scrolled to, as its node tells accessibility. */
    private fun homePosition(): Float =
        compose.onNodeWithTag("home").fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange].value()

    private fun scrollHome() {
        compose.onNodeWithTag("home").performTouchInput { swipeUp() }
        compose.waitForIdle()
    }

    /** How many of these are on screen: placed, as is every node above them (a page its parent does not place is not). */
    private fun SemanticsNodeInteractionCollection.placed(): Int =
        fetchSemanticsNodes().count { node: SemanticsNode -> generateSequence(node.layoutInfo) { it.parentInfo }.all { it.isPlaced } }

    private fun placed(tag: String) = compose.onAllNodesWithTag(tag, useUnmergedTree = true).placed()

    private fun spinners() = compose.onAllNodesWithContentDescription(LOADING).placed()

    /** Taps [tab] and checks the moment after: the spinner alone. Then waits for the tab's page. */
    private fun open(tab: String, page: String) {
        compose.mainClock.autoAdvance = false
        compose.onNodeWithContentDescription(tab).performClick()
        compose.mainClock.advanceTimeByFrame()
        compose.mainClock.advanceTimeByFrame()
        assertEquals("the spinner in the middle", 1, spinners())
        assertEquals("the tab left is gone at once", 0, placed("home") + placed("messages"))
        compose.mainClock.autoAdvance = true
        compose.waitUntil(5_000) { placed(page) == 1 }
        assertEquals("then the page alone", 0, spinners())
    }

    @Test
    fun homeIsAsItWasAfterAnotherTab() {
        val stack = TabStack()
        compose.setContent {
            var selected by remember { mutableStateOf(MessengerTab.HOME) }
            stack.show(selected)
            TabPages(bar, stack, theme, ready = true, loading = LOADING, select = { selected = it }) { Page(it) }
        }
        assertEquals("the first tab is there at once", 1, placed("home"))
        assertEquals(0, spinners())
        scrollHome()
        val scrolled = homePosition()
        assertTrue("Home scrolled: $scrolled", scrolled > 0f)

        open("Söhbətlər, 7 oxunmamış", "messages")
        assertEquals("Home kept, but not placed: not drawn, not touched, not read out", 0, placed("home"))

        open("Əsas səhifə", "home")
        assertEquals(0, placed("messages"))
        assertEquals("built once", 1, builds)
        assertEquals("where it was left", scrolled, homePosition())
    }

    /** The control: a tab drawn by `when`, as SDK 1.0.7 had it, builds Home again at its top; the measure above sees that. */
    @Test
    fun aPlainSwitchBuildsHomeAgain() {
        compose.setContent {
            var selected by remember { mutableStateOf(MessengerTab.HOME) }
            WithTabBar(bar, selected, theme, { selected = it }) { Page(selected) }
        }
        scrollHome()
        assertTrue(homePosition() > 0f)
        compose.onNodeWithContentDescription("Söhbətlər, 7 oxunmamış").performClick()
        compose.onNodeWithContentDescription("Əsas səhifə").performClick()
        compose.waitForIdle()
        assertEquals("built twice", 2, builds)
        assertEquals("back at its top", 0f, homePosition())
    }

    /** A screen pushed: the spinner for at least 350 ms, then, only once its data is there, the screen. */
    @Test
    fun aPushedScreenWaitsForItsData() {
        var ready by mutableStateOf(false)
        compose.mainClock.autoAdvance = false
        compose.setContent {
            OpeningPages(ONE_PAGE, Unit, ready = ready, enter = true, Color.White, theme, LOADING) { BasicText("Xəbər", Modifier.testTag("news")) }
        }
        compose.mainClock.advanceTimeByFrame()
        assertEquals(1, spinners())
        assertEquals(0, placed("news"))
        compose.mainClock.advanceTimeBy(1_000)
        assertEquals("no data yet: still the spinner", 1, spinners())
        assertEquals(0, placed("news"))
        ready = true
        compose.mainClock.autoAdvance = true
        compose.waitUntil(5_000) { placed("news") == 1 }
        assertEquals(0, spinners())
    }

    /** A screen gone back to (or the first one) is there at once, with no spinner. */
    @Test
    fun aScreenGoneBackToIsThereAtOnce() {
        compose.setContent {
            OpeningPages(ONE_PAGE, Unit, ready = true, enter = false, Color.White, theme, LOADING) { BasicText("Söhbətlər", Modifier.testTag("list")) }
        }
        assertEquals(1, placed("list"))
        assertEquals(0, spinners())
    }

    private companion object {
        const val LOADING = "Yüklənir"
    }
}
