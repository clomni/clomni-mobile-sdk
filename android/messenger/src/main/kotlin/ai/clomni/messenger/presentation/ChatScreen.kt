package ai.clomni.messenger.presentation

import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.store.PendingMessage
import java.io.File

/** Everything the conversation screen shows (brief 8·7.4, 7.5, 7.6), decided here so the Compose view only draws. */
internal data class ChatScreen(
    val phase: HomeScreen.Phase,
    val header: ChatHeader,
    val items: List<ChatItem>,
    val composer: ChatComposer,
    /** The thin yellow strip under the header. */
    val offline: String?,
    val failure: HomeScreen.Failure?,
    /** The newest incoming message, for TalkBack to read out when it changes. */
    val announcement: Announcement?,
)

internal data class Announcement(val id: String, val text: String)

/** White bar with the bottom hairline: back arrow, who is answering, ✕. */
internal data class ChatHeader(
    val lead: Lead,
    /** The brand, or the operator's name. */
    val title: String,
    /** "Komanda da kömək edə bilər", the reply time while queued, "Apar · onlayn", or when the team is back. */
    val subtitle: String,
    val backLabel: String,
    val closeLabel: String,
) {
    sealed interface Lead {
        /** Up to three team avatars, 24 dp, overlapping. */
        data class Team(val urls: List<String>) : Lead

        /** The operator, 28 dp, with the green dot while online. */
        data class Person(val avatar: ChatAvatar, val online: Boolean) : Lead
    }
}

internal data class ChatAvatar(
    val url: String?,
    val initial: String,
    /** The bot is drawn in the brand colour while it has no picture. */
    val isBot: Boolean,
)

internal sealed interface ChatItem {
    val id: String

    /** "Bu gün 10:30": before the first message and after a pause of more than an hour. */
    data class TimeItem(override val id: String, val text: String) : ChatItem

    data class BubbleItem(val bubble: Bubble) : ChatItem {
        override val id: String get() = bubble.id
    }

    /** Centred grey text without a bubble, with small avatars: "Leyla söhbətə qoşuldu". */
    data class SystemItem(val line: SystemLine) : ChatItem {
        override val id: String get() = line.id
    }

    /** The live buttons of the latest flow step. */
    data class RepliesItem(val block: QuickReplyBlock) : ChatItem {
        override val id: String get() = "replies-${block.messageId}"
    }

    data class TypingItem(val line: TypingLine) : ChatItem {
        override val id: String get() = "typing"
    }
}

internal data class Bubble(
    val id: String,
    val side: Side,
    val body: Body,
    val position: Position,
    /** Next to the last bubble of an incoming run. */
    val avatar: ChatAvatar?,
    /** Under the last bubble of an incoming run: "Clomni · Bot · indi", "Leyla · indi". */
    val meta: String?,
    /** Under the user's message when it is the last one, or when it failed. */
    val status: Status?,
    val accessibilityLabel: String,
) {
    enum class Side { INCOMING, OUTGOING }

    /** Where the bubble stands in a run of one sender's messages; the corners where bubbles meet are 5 dp. */
    enum class Position { SINGLE, FIRST, MIDDLE, LAST }

    sealed interface Body

    data class TextBody(val runs: List<TextRun>) : Body

    data class ImageBody(
        /** The thumbnail if there is one. */
        val url: String?,
        /** For full screen. */
        val fullUrl: String?,
        /** A picture the user is sending, before the server has it. */
        val localFile: File?,
        val width: Double,
        val height: Double,
        /** False: a placeholder of this size until the image loads. */
        val sizeKnown: Boolean,
        val caption: List<TextRun>?,
    ) : Body

    data class FileBody(
        val name: String,
        /** "182 KB" */
        val size: String,
        val icon: Media.FileIcon,
        val url: String?,
    ) : Body

    data class Status(
        /** "Göndərilir", "Göndərildi", "Oxundu", "Göndərilmədi · Yenidən cəhd et". */
        val text: String,
        val isFailure: Boolean,
        /** The client id to send again when the failure is tapped. */
        val retryId: String?,
    )
}

internal data class SystemLine(val id: String, val text: String, val avatars: List<ChatAvatar>)

internal data class QuickReplyBlock(
    val messageId: String,
    val layout: MessageContent.QuickRepliesLayout,
    val buttons: List<ReplyButton>,
    /** "← Geri" (nav:back), drawn grey after the others. */
    val back: ReplyButton?,
)

internal data class ReplyButton(
    val id: String,
    /** The icon (a flag, say) and the title, as drawn; a long title wraps to two lines and ends with "…". */
    val title: String,
    val accessibilityLabel: String,
)

internal data class TypingLine(val avatar: ChatAvatar, val accessibilityLabel: String)

/** A form in a bot bubble; read-only once sent ("Göndərildi") or when it is no longer the live step. */
internal data class FormCard(
    val messageId: String,
    val text: List<TextRun>?,
    val fields: List<Field>,
    val submitTitle: String,
    val readOnly: Boolean,
    /** What was sent, label by label. */
    val submitted: List<Line>,
    /** "Göndərildi" under a sent form. */
    val sentLabel: String?,
) : Bubble.Body {
    data class Field(
        val id: String,
        val type: MessageContent.FormFieldType,
        val label: String,
        val required: Boolean,
        val placeholder: String?,
        val maxLength: Int?,
        val options: List<MessageContent.FormField.Option>,
        /** The logged-in user's known value, filled in before they type. */
        val initialValue: String,
    )

    data class Line(val label: String, val value: String)
}

internal data class ChatComposer(
    val mode: Mode,
    val placeholder: String,
    val showsAttach: Boolean,
    val showsEmoji: Boolean,
    /** Characters a message may have. */
    val limit: Int,
    val sendLabel: String,
    val attachLabel: String,
    val emojiLabel: String,
    /** The attachment menu: a picture, or any file. */
    val imageLabel: String,
    val fileLabel: String,
) {
    sealed interface Mode {
        data object Open : Mode

        /** The step waits for a button: "Yuxarıdakı variantlardan birini seçin", no icons. */
        data class Locked(val text: String) : Mode

        /** "Söhbət bağlanıb · Yeni söhbət başlat"; writing anyway reopens it. */
        data class Closed(val text: String, val action: String) : Mode
    }
}

/** What the conversation screen is built from. */
internal data class ChatSnapshot(
    val config: MessengerConfig? = null,
    val conversation: Conversation? = null,
    /** In seq order. */
    val messages: List<Message> = emptyList(),
    val pending: List<PendingMessage> = emptyList(),
    /** The files of pending attachments, by client id. */
    val localFiles: Map<String, File> = emptyMap(),
    /** Messages whose buttons or form are live. */
    val answerable: Set<String> = emptySet(),
    /** The highest seq the operator has read. */
    val readUpTo: Long? = null,
    /** Who is typing, while the indicator shows. */
    val typing: Sender? = null,
    val load: MessengerSnapshot.Load = MessengerSnapshot.Load.LOADING,
    val isOffline: Boolean = false,
    /** The user's details for prefilling forms: name, email, phone. */
    val known: Map<String, String> = emptyMap(),
)
