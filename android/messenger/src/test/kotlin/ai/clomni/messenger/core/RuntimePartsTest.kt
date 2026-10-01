package ai.clomni.messenger.core

import ai.clomni.messenger.Clomni
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.Executor

class RuntimePartsTest {
    @Test
    fun offlineFollowsTheNetworks() {
        val state = OfflineState(initiallyOffline = true)
        val heard = mutableListOf<Boolean>()
        val listener: (Boolean) -> Unit = { heard += it }
        state.addListener(listener)
        state.available("wifi")
        state.available("cell")
        state.lost("wifi")
        assertFalse("one network is enough", state.isOffline)
        state.lost("cell")
        assertTrue(state.isOffline)
        state.removeListener(listener)
        state.available("wifi")
        assertEquals("only changes, until removed", listOf(false, true), heard)
    }

    @Test
    fun aSerialExecutorRunsOneTaskAtATimeInOrder() {
        val queued = ArrayDeque<Runnable>()
        val pool = Executor { queued.addLast(it) }
        val serial = SerialExecutor(pool)
        val ran = mutableListOf<Int>()
        serial.execute { ran += 1 }
        serial.execute { ran += 2 }
        serial.execute { ran += 3 }
        assertEquals("the next waits for the one running", 1, queued.size)
        while (queued.isNotEmpty()) queued.removeFirst().run()
        assertEquals(listOf(1, 2, 3), ran)
    }

    /** `Clomni.startFlow`'s data: the app's own map as JSON. */
    @Test
    fun flowDataAsJson() {
        val data = mapOf(
            "ride_id" to "R-1923", "minutes" to 18, "price" to 2.4, "paid" to false, "note" to null,
            "stops" to listOf("Gənclik", "28 May"), "card" to mapOf("last4" to "1234"), "codes" to arrayOf(1, 2),
        )
        assertEquals(
            """{"ride_id":"R-1923","minutes":18,"price":2.4,"paid":false,"note":null,"stops":["Gənclik","28 May"],""" +
                """"card":{"last4":"1234"},"codes":[1,2]}""",
            JsonObject(data.mapValues { Clomni.json(it.value) }).toString(),
        )
        val refused = runCatching { Clomni.json(Any()) }.exceptionOrNull()
        assertTrue(refused?.message.orEmpty(), refused is IllegalArgumentException)
    }
}
