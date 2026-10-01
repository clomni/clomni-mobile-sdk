package ai.clomni.messenger.protocol

import kotlinx.serialization.json.JsonElement

/**
 * The `content` of a [Message], by its type (brief 8·5.2). The payload types are nested here, as on iOS, so that
 * `Button`, `Image` and the like do not clash with Compose's in an app that uses the SDK.
 */
internal sealed interface MessageContent {

    /** Limited markdown: **bold**, *italic*, [text](https://…), line breaks, emoji. */
    data class Text(val text: String) : MessageContent

    /** Flow buttons. Titles are kept whole, however long; the UI wraps a long one to two lines. */
    data class QuickReplies(
        val text: String?,
        val buttons: List<Button>,
        val layout: QuickRepliesLayout,
        /** The composer is hidden while this message waits for a button. */
        val inputDisabled: Boolean,
        /** A back button follows the others; it sends [ClientMessage.back]. */
        val allowBack: Boolean,
    ) : MessageContent

    /** [width] and [height] are null when unknown; otherwise the bubble reserves their ratio before loading. */
    data class Image(
        val url: String,
        val thumbUrl: String?,
        val width: Int?,
        val height: Int?,
        val caption: String?,
    ) : MessageContent

    data class File(
        val url: String,
        val name: String,
        /** Bytes. */
        val size: Long,
        val mime: String,
    ) : MessageContent

    /** [submitted] holds the sent values once the form is read-only, otherwise null. */
    data class Form(
        val text: String?,
        val formId: String,
        val fields: List<FormField>,
        val submitTitle: String,
        val submitted: Map<String, JsonElement>?,
    ) : MessageContent

    /** Centred grey text without a bubble. */
    data class System(
        val event: SystemEvent,
        val text: String,
        /** Queue position, for [SystemEvent.WaitingInQueue]. */
        val position: Int?,
    ) : MessageContent

    /** One card, or a carousel of several. */
    data class Card(val cards: List<CardItem>) : MessageContent

    data class Rating(
        val text: String,
        val scale: RatingScale,
        val comment: RatingComment,
        val submitted: Map<String, JsonElement>?,
    ) : MessageContent

    /**
     * A type this SDK does not know, or a known type whose content is broken. Shown with [Message.fallbackText];
     * [raw] is the `content` as received.
     */
    data class Unknown(val type: String, val raw: JsonElement) : MessageContent

    data class Button(
        val id: String,
        val title: String,
        /** Shown before the title, e.g. a flag emoji. */
        val icon: String?,
        /** Opaque: sent back as is in the button reply. */
        val payload: String,
    )

    enum class QuickRepliesLayout {
        /** Full-width buttons, one per row (the default). */
        VERTICAL,

        /** Short buttons side by side. */
        CHIPS,
    }

    data class FormField(
        val key: String,
        val type: FormFieldType,
        val label: String,
        val required: Boolean,
        val maxLength: Int?,
        /** ISO 3166 code for a phone field, e.g. "AZ". */
        val defaultCountry: String?,
        val placeholder: String?,
        /** The choices of a select field; empty for the other types. */
        val options: List<Option>,
    ) {
        data class Option(val value: String, val label: String)
    }

    /** A field type added after this SDK was built reads as [TEXT]. */
    enum class FormFieldType(internal val wire: String) {
        TEXT("text"),
        TEXTAREA("textarea"),
        PHONE("phone"),
        EMAIL("email"),
        NUMBER("number"),
        SELECT("select"),
        DATE("date"),
        ;

        internal companion object {
            fun from(wire: String): FormFieldType = entries.firstOrNull { it.wire == wire } ?: TEXT
        }
    }

    /** An event this SDK does not know is [Unknown] and is shown by its text alone. */
    sealed interface SystemEvent {
        data object OperatorJoined : SystemEvent
        data object AssignedToTeam : SystemEvent
        data object ConversationClosed : SystemEvent
        data object ConversationReopened : SystemEvent
        data object WaitingInQueue : SystemEvent
        data class Unknown(val raw: String) : SystemEvent
    }

    data class CardItem(
        val imageUrl: String?,
        val title: String,
        val subtitle: String?,
        val buttons: List<CardButton>,
    )

    /** Sends [payload] back as a button reply, or opens [url]; at least one is set. */
    data class CardButton(
        val id: String,
        val title: String,
        val payload: String?,
        val url: String?,
    )

    /** An unknown scale cannot be drawn, so it turns the whole content into [Unknown]. */
    enum class RatingScale(internal val wire: String) {
        EMOJI_5("emoji_5"),
        STAR_5("star_5"),
        ;

        internal companion object {
            fun from(wire: String): RatingScale? = entries.firstOrNull { it.wire == wire }
        }
    }

    /** Whether the rating asks for a comment: absent reads as [HIDDEN], an unknown value as [OPTIONAL]. */
    enum class RatingComment(internal val wire: String) {
        HIDDEN("none"),
        OPTIONAL("optional"),
        REQUIRED("required"),
        ;

        internal companion object {
            fun from(wire: String?): RatingComment =
                if (wire == null) HIDDEN else entries.firstOrNull { it.wire == wire } ?: OPTIONAL
        }
    }
}
