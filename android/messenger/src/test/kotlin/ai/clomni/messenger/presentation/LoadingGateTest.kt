package ai.clomni.messenger.presentation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** DESIGN-PASS 5 on a test clock: shown after 300 ms of loading, and then for at least 400 ms. */
class LoadingGateTest {
    @Test
    fun aQuickLoadShowsNothing() {
        val gate = LoadingGate()
        assertFalse(gate.visible(true, 1_000))
        assertEquals(1_300L, gate.nextChange(true))
        assertFalse(gate.visible(true, 1_299))
        assertFalse("done in 299 ms: never shown", gate.visible(false, 1_299))
        assertNull(gate.nextChange(false))
    }

    @Test
    fun aLongerLoadShowsAfter300AndStaysAtLeast400() {
        val gate = LoadingGate()
        gate.visible(true, 0)
        assertTrue(gate.visible(true, 300))
        assertNull("shown while loading: nothing to wait for", gate.nextChange(true))
        assertTrue("done at 350, still shown", gate.visible(false, 350))
        assertEquals(700L, gate.nextChange(false))
        assertTrue(gate.visible(false, 699))
        assertFalse(gate.visible(false, 700))
        // A load that lasts past the minimum hides as soon as it is done.
        assertTrue(gate.visible(true, 1_000).not())
        assertTrue(gate.visible(true, 1_300))
        assertFalse(gate.visible(false, 2_000))
    }

    @Test
    fun aNewLoadWaitsItsOwn300() {
        val gate = LoadingGate()
        gate.visible(true, 0)
        gate.visible(false, 200)
        assertFalse(gate.visible(true, 250))
        assertFalse("the delay counts from 250", gate.visible(true, 500))
        assertTrue(gate.visible(true, 550))
    }
}
