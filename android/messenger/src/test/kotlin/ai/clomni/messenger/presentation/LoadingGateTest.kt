package ai.clomni.messenger.presentation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** DESIGN-PASS 5 and contract 1.0.7b §3 on a test clock: shown after 150 ms of loading, and then for at least 400 ms. */
class LoadingGateTest {
    @Test
    fun aQuickLoadShowsNothing() {
        val gate = LoadingGate()
        assertFalse(gate.visible(true, 1_000))
        assertEquals(1_150L, gate.nextChange(true))
        assertFalse(gate.visible(true, 1_149))
        assertFalse("done in 149 ms: never shown", gate.visible(false, 1_149))
        assertNull(gate.nextChange(false))
    }

    @Test
    fun aLongerLoadShowsAfter150AndStaysAtLeast400() {
        val gate = LoadingGate()
        gate.visible(true, 0)
        assertTrue(gate.visible(true, 150))
        assertNull("shown while loading: nothing to wait for", gate.nextChange(true))
        assertTrue("done at 200, still shown", gate.visible(false, 200))
        assertEquals(550L, gate.nextChange(false))
        assertTrue(gate.visible(false, 549))
        assertFalse(gate.visible(false, 550))
        // A load that lasts past the minimum hides as soon as it is done.
        assertTrue(gate.visible(true, 1_000).not())
        assertTrue(gate.visible(true, 1_150))
        assertFalse(gate.visible(false, 2_000))
    }

    @Test
    fun aNewLoadWaitsItsOwn150() {
        val gate = LoadingGate()
        gate.visible(true, 0)
        gate.visible(false, 100)
        assertFalse(gate.visible(true, 120))
        assertFalse("the delay counts from 120", gate.visible(true, 269))
        assertTrue(gate.visible(true, 270))
    }
}
