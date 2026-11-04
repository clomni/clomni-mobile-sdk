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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
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
 * CM-347 (contract 1.0.7b §3): going back to a tab finds it as it was. On iOS every return to Home showed one white
 * frame, then the page; on Android Home was built again: its scroll back at the top, and for one frame the brand
 * colour only 16 dp high under a white greeting. Home here is a long scrolled page that counts how often it is built.
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
            BasicText("Söhbətlərin siyahısı", Modifier.fillMaxSize())
        }
    }

    /** Where Home is scrolled to, as its node tells accessibility. */
    private fun homePosition(): Float =
        compose.onNodeWithTag("home").fetchSemanticsNode().config[SemanticsProperties.VerticalScrollAxisRange].value()

    private fun scrollHome() {
        compose.onNodeWithTag("home").performTouchInput { swipeUp() }
        compose.waitForIdle()
    }

    private fun tap(tab: String) {
        compose.onNodeWithContentDescription(tab).performClick()
        compose.waitForIdle()
    }

    @Test
    fun homeIsAsItWasAfterAnotherTab() {
        val stack = TabStack()
        compose.setContent {
            var selected by remember { mutableStateOf(MessengerTab.HOME) }
            stack.show(selected)
            TabPages(bar, stack, theme, { selected = it }) { Page(it) }
        }
        scrollHome()
        val scrolled = homePosition()
        assertTrue("Home scrolled: $scrolled", scrolled > 0f)

        tap("Söhbətlər, 7 oxunmamış")
        compose.onNodeWithText("Söhbətlərin siyahısı").assertIsDisplayed()
        // Kept, but not placed while another tab is open: not drawn, not touched, not read out.
        val placed = compose.onAllNodesWithTag("home").fetchSemanticsNodes().count { it.layoutInfo.isPlaced }
        assertEquals("Home placed under the conversations", 0, placed)

        tap("Əsas səhifə")
        compose.onNodeWithTag("home").assertIsDisplayed()
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
        tap("Söhbətlər, 7 oxunmamış")
        tap("Əsas səhifə")
        assertEquals("built twice", 2, builds)
        assertEquals("back at its top", 0f, homePosition())
    }
}
