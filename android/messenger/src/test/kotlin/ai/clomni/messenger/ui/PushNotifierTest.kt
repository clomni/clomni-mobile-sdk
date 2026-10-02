package ai.clomni.messenger.ui

import ai.clomni.messenger.ClomniPush
import ai.clomni.messenger.presentation.ClomniStrings
import ai.clomni.messenger.presentation.PushNotification
import ai.clomni.messenger.protocol.ProtocolJson
import android.app.Notification
import android.graphics.Bitmap
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * The notification a Clomni push becomes, built by the real framework classes Paparazzi's layoutlib carries (no
 * device, no Robolectric): what Android will show.
 */
class PushNotifierTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5, theme = "android:Theme.Material.Light.NoActionBar")

    private val data = mapOf(
        "clomni" to "1", "type" to "message", "conversation_id" to "conv_5521", "message_id" to "msg_f02",
        "title" to "Leyla · Apar", "body" to "Gedişinizi yoxladıq, balansınıza 2 AZN qaytarıldı.",
        "avatar_url" to "https://app.clomni.ai/a/leyla.png", "unread_total" to "1",
    )

    private fun notification() = PushNotification.of(ProtocolJson().parsePush(data), data, ClomniStrings("az"), "Apar")

    @Test
    fun theOperatorsReply() {
        val photo = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
        val built = PushNotifier.build(paparazzi.context, notification(), android.R.drawable.stat_notify_chat, 0xFF1F9D63.toInt(), photo, null)
        assertEquals("Leyla · Apar", built.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertEquals("Gedişinizi yoxladıq, balansınıza 2 AZN qaytarıldı.", built.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals("Gedişinizi yoxladıq, balansınıza 2 AZN qaytarıldı.", built.extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString())
        assertEquals(ClomniPush.CHANNEL_ID, built.channelId)
        assertEquals("clomni_messages", PushNotification.CHANNEL_ID)
        assertEquals(Notification.CATEGORY_MESSAGE, built.category)
        assertEquals(Notification.VISIBILITY_PRIVATE, built.visibility)
        assertTrue("a tap takes it away", built.flags and Notification.FLAG_AUTO_CANCEL != 0)
        assertEquals(0xFF1F9D63.toInt(), built.color)
        assertNotNull("the operator's photo", built.getLargeIcon())
    }

    /** No photo (it did not load in time), no colour, no tap: still a notification. */
    @Test
    fun withoutThePhoto() {
        val built = PushNotifier.build(paparazzi.context, notification(), android.R.drawable.stat_notify_chat, null, null, null)
        assertNull(built.getLargeIcon())
        assertNull(built.contentIntent)
        assertEquals("Leyla · Apar", built.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
    }

    @Test
    fun theAppsOwnPushIsLeftAlone() {
        assertFalse(ClomniPush.handle(paparazzi.context, mapOf("order_id" to "7", "title" to "Sifarişiniz yoldadır")))
        assertFalse(ClomniPush.isClomniPush(mapOf("clomni" to "2")))
        assertTrue(ClomniPush.isClomniPush(data))
    }
}
