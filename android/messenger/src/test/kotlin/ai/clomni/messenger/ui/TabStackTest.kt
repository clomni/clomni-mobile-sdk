package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.MessengerTab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Contract 1.0.7b §3: a tab opened once stays (its state with it); the one it replaced is drawn under it until settled. */
class TabStackTest {
    @Test
    fun aTabOpenedOnceStays() {
        val stack = TabStack()
        assertNull("nothing before the first tab", stack.selected)
        stack.show(MessengerTab.HOME)
        assertEquals(MessengerTab.HOME, stack.selected)
        assertNull("the first tab is simply there", stack.under)

        stack.show(MessengerTab.MESSAGES)
        assertEquals(MessengerTab.MESSAGES, stack.selected)
        assertEquals("Home stays drawn under the conversations while they fade in", MessengerTab.HOME, stack.under)
        assertEquals(listOf(MessengerTab.HOME, MessengerTab.MESSAGES), stack.opened)
        stack.settled()
        assertNull(stack.under)

        stack.show(MessengerTab.HOME)
        assertEquals("back to Home: the same Home, not a second one", listOf(MessengerTab.HOME, MessengerTab.MESSAGES), stack.opened)
        assertEquals(MessengerTab.MESSAGES, stack.under)
        stack.show(MessengerTab.HOME)
        assertEquals("the same tab again changes nothing", MessengerTab.MESSAGES, stack.under)

        stack.show(MessengerTab.FAQ)
        assertEquals(listOf(MessengerTab.HOME, MessengerTab.MESSAGES, MessengerTab.FAQ), stack.opened)
        assertEquals("a change during a fade: the tab being left is the one under", MessengerTab.HOME, stack.under)
    }
}
