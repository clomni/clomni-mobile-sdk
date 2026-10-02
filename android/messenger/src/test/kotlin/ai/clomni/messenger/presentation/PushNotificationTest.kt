package ai.clomni.messenger.presentation

import ai.clomni.messenger.protocol.ProtocolFiles
import ai.clomni.messenger.protocol.ProtocolJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PushNotificationTest {
    private val protocol = ProtocolJson()
    private val az = ClomniStrings("az")

    /** Fixture 44 as FCM delivers it: a data message, every value a string. */
    private val data = mapOf(
        "clomni" to "1", "type" to "message", "conversation_id" to "conv_5521", "message_id" to "msg_f02",
        "title" to "Leyla · Apar", "body" to "Gedişinizi yoxladıq, balansınıza 2 AZN qaytarıldı.",
        "avatar_url" to "https://app.clomni.ai/a/leyla.png", "unread_total" to "1",
    )

    @Test
    fun anOperatorsReply() {
        val notification = PushNotification.of(protocol.parsePush(data), data, az, "Apar")
        assertEquals(
            PushNotification(
                tag = "clomni:conv_5521",
                id = "clomni:conv_5521".hashCode(),
                title = "Leyla · Apar",
                text = "Gedişinizi yoxladıq, balansınıza 2 AZN qaytarıldı.",
                avatarUrl = "https://app.clomni.ai/a/leyla.png",
                conversationId = "conv_5521",
                channelName = "Dəstək mesajları",
            ),
            notification,
        )
        assertEquals("clomni_messages", PushNotification.CHANNEL_ID)
        assertEquals("Support messages", PushNotification.of(null, data, ClomniStrings("en"), "Apar").channelName)
        assertEquals("Сообщения поддержки", PushNotification.of(null, data, ClomniStrings("ru"), "Apar").channelName)
    }

    /** One per conversation: the same conversation's next push replaces it, another one stands beside it. */
    @Test
    fun onePerConversation() {
        val first = PushNotification.of(protocol.parsePush(data), data, az, "Apar")
        val next = data + ("message_id" to "msg_f03") + ("body" to "Və bir də")
        val other = data + ("conversation_id" to "conv_7")
        assertEquals(first.tag to first.id, PushNotification.of(protocol.parsePush(next), next, az, "Apar").let { it.tag to it.id })
        assertNotEquals(first.tag, PushNotification.of(protocol.parsePush(other), other, az, "Apar").tag)
    }

    @Test
    fun theTextStaysWithin180() {
        val long = data + ("body" to "ə".repeat(181))
        val notification = PushNotification.of(protocol.parsePush(long), long, az, "Apar")
        assertEquals(180, notification.text.codePointCount(0, notification.text.length))
        assertEquals("ə".repeat(179) + "…", notification.text)
        val emoji = data + ("body" to "👍".repeat(200))
        val cut = PushNotification.of(protocol.parsePush(emoji), emoji, az, "Apar").text
        assertEquals("emoji are not split", 180, cut.codePointCount(0, cut.length))
        // Fixture 92: a server that sent 181 anyway.
        val overlong = protocol.parsePush(ProtocolFiles.read("fixtures/92-invalid-push-body-too-long.json"))
        val text = PushNotification.of(overlong, emptyMap(), az, "Apar").text
        assertEquals(180, text.codePointCount(0, text.length))
    }

    /** A Clomni push this SDK cannot read (a later type, a missing field) still shows; a tap opens Home. */
    @Test
    fun anUnreadablePushShowsWhatItCan() {
        val later = mapOf("clomni" to "1", "type" to "survey", "title" to "Sorğu", "body" to "Bizi qiymətləndirin")
        assertNull(protocol.parsePush(later))
        val shown = PushNotification.of(null, later, az, "Apar")
        assertEquals("Sorğu", shown.title)
        assertEquals("Bizi qiymətləndirin", shown.text)
        assertNull(shown.conversationId)
        assertEquals("clomni:push", shown.tag)
        val bare = PushNotification.of(null, mapOf("clomni" to "1"), az, "Apar")
        assertEquals("Apar", bare.title)
        assertEquals("Oxunmamış mesaj var", bare.text)
        assertNull(bare.avatarUrl)
    }
}
