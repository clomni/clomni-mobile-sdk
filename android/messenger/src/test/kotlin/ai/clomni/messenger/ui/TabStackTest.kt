package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.MessengerTab
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Contract 1.0.7b §3, §5.1: a tab opened once stays (its state with it), opened again when chosen again. */
class TabStackTest {
    @Test
    fun aTabOpenedOnceStays() {
        val stack = TabStack()
        assertNull("nothing before the first tab", stack.selected)
        stack.show(MessengerTab.HOME)
        assertEquals(MessengerTab.HOME, stack.selected)

        stack.show(MessengerTab.MESSAGES)
        assertEquals(MessengerTab.MESSAGES, stack.selected)
        assertEquals(listOf(MessengerTab.HOME, MessengerTab.MESSAGES), stack.opened)

        stack.show(MessengerTab.HOME)
        assertEquals(MessengerTab.HOME, stack.selected)
        assertEquals("back to Home: the same Home, not a second one", listOf(MessengerTab.HOME, MessengerTab.MESSAGES), stack.opened)
        stack.show(MessengerTab.HOME)
        assertEquals("the same tab again changes nothing", listOf(MessengerTab.HOME, MessengerTab.MESSAGES), stack.opened)

        stack.show(MessengerTab.FAQ)
        assertEquals(listOf(MessengerTab.HOME, MessengerTab.MESSAGES, MessengerTab.FAQ), stack.opened)
    }
}
