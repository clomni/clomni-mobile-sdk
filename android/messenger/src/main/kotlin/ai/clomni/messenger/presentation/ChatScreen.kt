package ai.clomni.messenger.presentation

import ai.clomni.messenger.protocol.Conversation
import ai.clomni.messenger.protocol.Message
import ai.clomni.messenger.protocol.MessageContent
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.Sender
import ai.clomni.messenger.protocol.SenderType
import ai.clomni.messenger.store.PendingMessage
import java.io.File

/** Everything the conversation screen shows (brief 8·7.4, 7.5, 7.6), decided here so the Compose view only draws. */
internal data class ChatScreen(
    val phase: HomeScreen.Phase,
    /** "Yüklənir": the loading indicator's name for TalkBack. */
    val loadingLabel: String = "",
    val header: ChatHeader,
    val items: List<ChatItem>,
    val composer: ChatComposer,
    /** The thin strip under the header while offline (DESIGN-PASS-3 C1). */
    val offline: String?,
    /** "Qoşuldu": the strip's word for a second once the connection is back. */
    val connected: String,
    val failure: HomeScreen.Failure?,
    /** The newest incoming message, for TalkBack to read out when it changes. */
    val announcement: Announcement?,
    /** A message's long-press menu: "Cavabla", "Kopyala". */
    val replyLabel: String = "",
    val copyLabel: String = "",
)

internal data class Announcement(val id: String, val text: String)

/** White bar with the bottom hairline: back arrow, who is answering, ✕. */
internal data class ChatHeader(
    val lead: Lead,
    /** The brand, or the operator's name. */
    val title: String,
    /** "Adətən bir neçə dəqiqəyə cavab veririk", the reply time while queued, the company under an operator ("Apar"), or when the team is back. */
    val subtitle: String,
    val backLabel: String,
    val closeLabel: String,
) {
    sealed interface Lead {
        /** Nobody has taken the conversation: the company's logo (its initial without one). */
        data class Brand(val logo: ChatAvatar) : Lead

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
    /** Under the last bubble of an incoming run: when, "indi" or "12:42". */
    val meta: String?,
    /** Under the user's message when it is the last one, or when it failed. */
    val status: Status?,
    val accessibilityLabel: String,
    /** Over the first bubble of an incoming run: who, the brand for the bot ("Clomni"), "Leyla". */
    val author: String? = null,
    /** The message this one answers, in a small block at the top of the bubble; a tap scrolls to it. */
    val quote: Quote? = null,
    /** The server's id; null while the message is still on its way. */
    val messageId: String? = null,
    /** A swipe to the right or "Cavabla" quotes it in the composer: only while there is a composer to write in. */
    val replyable: Boolean = false,
    /** What "Kopyala" copies: the text or the caption; null when there is nothing to copy. */
    val copyText: String? = null,
) {
    /** Who wrote the quoted message ("Siz", "Leyla", the brand) and one line of it, or "Mesaj silinib". */
    data class Quote(val messageId: String, val author: String, val excerpt: String)

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
        /**
         * "Göndərilir", "Göndərildi", "Oxundu": only TalkBack reads it, the screen shows [mark]. A failure,
         * "Göndərilmədi · Yenidən cəhd et", is on screen in words.
         */
        val text: String,
        val isFailure: Boolean,
        /** The client id to send again when the failure is tapped. */
        val retryId: String?,
        /** The clock, then ✓, next to [time]; null for a failure. */
        val mark: Mark? = null,
        /** When it was sent, next to [mark]: "indi", "12:42". */
        val time: String? = null,
    ) {
        enum class Mark { SENDING, SENT, READ }
    }
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
    /** TalkBack's reading of [text], with who wrote it and when: "Clomni bot, 10:30: …". */
    val textAccessibilityLabel: String,
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
        /** TalkBack's name of the field: the label, and "məcburi" for the "*". */
        val accessibilityLabel: String,
        val placeholder: String?,
        val maxLength: Int?,
        val options: List<MessageContent.FormField.Option>,
        /** The logged-in user's known value, filled in before they type. */
        val initialValue: String,
        /** On screen: the label, with "(istəyə görə)" after an optional field's. */
        val shownLabel: String = label,
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
    /** The attachment sheet: photo or video, the camera, any file; the × on a picked one. */
    val mediaLabel: String,
    val cameraLabel: String,
    val fileLabel: String,
    val removeLabel: String,
    /** The message being answered, over the field with its ✕ ([cancelQuoteLabel]). */
    val quote: Bubble.Quote? = null,
    val cancelQuoteLabel: String = "",
) {
    sealed interface Mode {
        data object Open : Mode

        /** The step waits for a button: no composer at all, the choices end the conversation (operator, 2026-10-04). */
        data object Hidden : Mode

        /** "Söhbət bağlanıb · Yeni söhbət başlat"; writing anyway reopens it. */
        data class Closed(val text: String, val action: String) : Mode
    }
}

/**
 * A flow waits for a choice and the last message offers it: nobody is writing, whatever the last "typing" said
 * (operator, 2026-10-06).
 */
internal val ChatSnapshot.awaitsChoice: Boolean
    get() {
        val flow = conversation?.flow ?: return false
        if (!flow.active || flow.awaiting == null || pending.isNotEmpty()) return false
        val last = messages.lastOrNull { it.content !is MessageContent.System } ?: return false
        return last.content is MessageContent.QuickReplies && last.id in answerable
    }

/** This sender is the one shown [typing]: the same kind, and the same person when both are named; a bot is a bot. */
internal fun Sender.isTyping(typing: Sender): Boolean =
    type == typing.type && (type == SenderType.BOT || id == null || typing.id == null || id == typing.id)

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
    /** The message the user is answering (swipe or "Cavabla"), until it is sent or dismissed. */
    val replyingTo: String? = null,
)
