package ai.clomni.messenger.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Whether the app is in front decides whether the socket is open, and the server pushes only to a user without one
 * (CM-266): a push that starts the process must not count as the app in front, and a late initialize must still see
 * the app leave for the background.
 */
class ForegroundTest {
    @Test
    fun aProcessAPushStartedIsInTheBackgroundUntilAScreenStarts() {
        val changes = mutableListOf<Boolean>()
        val count = StartedActivities(startedAtCreate(0) { true }, changes::add)

        assertFalse(count.inForeground)
        count.started()
        assertEquals(listOf(true), changes)
    }

    @Test
    fun aLateInitializeSeesTheAppLeaveForTheBackground() {
        val changes = mutableListOf<Boolean>()
        // React Native calls initialize after MainActivity started.
        val count = StartedActivities(startedAtCreate(1) { false }, changes::add)

        assertTrue(count.inForeground)
        count.stopped(changingConfigurations = false)
        assertEquals(listOf(false), changes)
        assertFalse(count.inForeground)
    }

    @Test
    fun aRotationIsNotATripToTheBackground() {
        val changes = mutableListOf<Boolean>()
        val count = StartedActivities(1, changes::add)

        count.stopped(changingConfigurations = true)
        count.started()
        assertEquals(emptyList<Boolean>(), changes)
        assertTrue(count.inForeground)
    }

    @Test
    fun withoutTheStartupProviderTheProcessStateDecides() {
        assertEquals(1, startedAtCreate(null) { true })
        assertEquals(0, startedAtCreate(null) { false })
        assertEquals("counted from the process's start", 2, startedAtCreate(2) { false })
    }
}
