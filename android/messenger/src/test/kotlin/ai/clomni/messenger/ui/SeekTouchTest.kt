package ai.clomni.messenger.ui

import androidx.compose.ui.geometry.Offset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * CM-341: a touch on a voice message's waveform takes nothing until it has moved a touch slop; up or down it is the
 * transcript's scroll, sideways it seeks. The device test (TranscriptScrollTest) drags the list from a bubble.
 */
class SeekTouchTest {
    private val slop = 18f

    @Test
    fun undecidedWithinTheSlop() {
        assertNull(SeekTouch.of(Offset(0f, 0f), slop))
        assertNull(SeekTouch.of(Offset(17f, -17f), slop))
    }

    @Test
    fun upOrDownIsTheListsScroll() {
        assertEquals(SeekTouch.SCROLL, SeekTouch.of(Offset(0f, 19f), slop))
        assertEquals(SeekTouch.SCROLL, SeekTouch.of(Offset(4f, -40f), slop))
        // Diagonal but more up than sideways: still the list's.
        assertEquals(SeekTouch.SCROLL, SeekTouch.of(Offset(20f, -30f), slop))
    }

    @Test
    fun sidewaysSeeks() {
        assertEquals(SeekTouch.SEEK, SeekTouch.of(Offset(19f, 0f), slop))
        assertEquals(SeekTouch.SEEK, SeekTouch.of(Offset(-30f, 10f), slop))
        assertEquals(SeekTouch.SEEK, SeekTouch.of(Offset(25f, 25f), slop))
    }
}
