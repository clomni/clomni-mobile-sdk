package ai.clomni.messenger.presentation

import ai.clomni.messenger.presentation.ClomniStrings.Key
import ai.clomni.messenger.protocol.PushPayload

/**
 * What a Clomni push shows (brief 8·6.5, 4.4): the operator and brand as the title, the message (at most 180
 * characters), the operator's photo when it loads. One per conversation: a new push for it replaces the one there.
 * A Clomni push this SDK cannot read still shows what it can, and a tap opens the messenger's Home.
 */
internal data class PushNotification(
    /** The notification's tag; with [id], what a newer push of the same conversation replaces. */
    val tag: String,
    val id: Int,
    val title: String,
    val text: String,
    val avatarUrl: String?,
    /** Opened on a tap; null opens Home. */
    val conversationId: String?,
    val channelName: String,
) {
    companion object {
        /** The Android notification channel of every Clomni push. */
        const val CHANNEL_ID = "clomni_messages"
        const val MAX_TEXT = 180

        fun of(push: PushPayload?, data: Map<String, String>, strings: ClomniStrings, appName: String): PushNotification {
            val conversationId = push?.conversationId
            val tag = "clomni:${conversationId ?: "push"}"
            return PushNotification(
                tag = tag,
                id = tag.hashCode(),
                title = push?.title ?: data["title"]?.takeIf { it.isNotBlank() } ?: appName,
                text = shortened(push?.body ?: data["body"]?.takeIf { it.isNotBlank() } ?: strings[Key.UNREAD_MESSAGES]),
                avatarUrl = push?.avatarUrl ?: data["avatar_url"],
                conversationId = conversationId,
                channelName = strings[Key.SUPPORT_MESSAGES],
            )
        }

        /** The server keeps a body within 180 characters; a longer one is cut there with "…". */
        private fun shortened(text: String): String {
            if (text.codePointCount(0, text.length) <= MAX_TEXT) return text
            return text.substring(0, text.offsetByCodePoints(0, MAX_TEXT - 1)).trimEnd() + "…"
        }
    }
}
