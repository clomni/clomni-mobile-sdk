package ai.clomni.messenger

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class ClomniUserTest {
    @Test
    fun equalByItsFields() {
        val aysel = ClomniUser(userId = "12345", email = "aysel@example.com")
        assertEquals(ClomniUser("12345", "aysel@example.com"), aysel)
        assertEquals(ClomniUser("12345", "aysel@example.com").hashCode(), aysel.hashCode())
        assertNotEquals(ClomniUser("12345", "aysel@example.com", name = "Aysel"), aysel)
        assertEquals("ClomniUser(userId=12345, email=aysel@example.com, phone=null, name=null)", aysel.toString())
    }
}
