package ai.clomni.messenger.protocol

import kotlinx.serialization.json.JsonElement

/** The `content` of a [Message], by its type (brief 8·5.2). */
public sealed interface MessageContent {

    /** Limited markdown: **bold**, *italic*, [text](https://…), line breaks, emoji. */
    public data class Text(val text: String) : MessageContent

    /** Flow buttons. Titles are kept whole; the UI shortens a title over 80 characters. */
    public data class QuickReplies(
        val text: String?,
        val buttons: List<Button>,
        val layout: QuickRepliesLayout,
        /** The composer is replaced by "choose one of the options above". */
        val inputDisabled: Boolean,
        /** A "← Back" button follows, sending `nav:back`. */
        val allowBack: Boolean,
    ) : MessageContent

    /** [width] and [height] are null when unknown; otherwise the bubble reserves their ratio before loading. */
    public data class Image(
        val url: String,
        val thumbUrl: String?,
        val width: Int?,
        val height: Int?,
        val caption: String?,
    ) : MessageContent

    public data class File(
        val url: String,
        val name: String,
        /** Bytes. */
        val size: Long,
        val mime: String,
    ) : MessageContent

    /** [submitted] holds the sent values once the form is read-only, otherwise null. */
    public data class Form(
        val text: String?,
        val formId: String,
        val fields: List<FormField>,
        val submitTitle: String,
        val submitted: Map<String, String>?,
    ) : MessageContent

    /**
     * Small centred text without a bubble. Known [event]s: operator_joined, assigned_to_team, conversation_closed,
     * conversation_reopened, waiting_in_queue (with [position]); any other is shown by its [text].
     */
    public data class System(
        val event: String,
        val text: String,
        val position: Int?,
    ) : MessageContent

    /** One card, or a carousel of several. */
    public data class Card(val cards: List<CardItem>) : MessageContent

    public data class Rating(
        val text: String,
        val scale: RatingScale,
        val comment: RatingComment,
        val submitted: Map<String, String>?,
    ) : MessageContent

    /**
     * A type this SDK does not know, or a known type whose content is broken. Shown with [Message.fallbackText].
     * [raw] is the `content` as received (null when it was missing).
     */
    public data class Unknown(val type: String, val raw: JsonElement?) : MessageContent
}

public data class Button(
    val id: String,
    val title: String,
    /** Shown before the title, e.g. a flag emoji. */
    val icon: String?,
    /** Opaque to the client: sent back as is in a button reply. */
    val payload: String,
)

public enum class QuickRepliesLayout {
    /** Full-width buttons, one per row (the default). */
    VERTICAL,

    /** Short buttons side by side. */
    CHIPS,
}

public data class FormField(
    val key: String,
    val type: FormFieldType,
    val label: String,
    val required: Boolean,
    val maxLength: Int?,
    /** ISO 3166 alpha-2, for [FormFieldType.PHONE]. */
    val defaultCountry: String?,
    val placeholder: String?,
    /** The choices of a [FormFieldType.SELECT]; empty for other types. */
    val options: List<Option>,
) {
    public data class Option(val value: String, val label: String)
}

public enum class FormFieldType(internal val wire: String) {
    TEXT("text"),
    TEXTAREA("textarea"),
    PHONE("phone"),
    EMAIL("email"),
    NUMBER("number"),
    SELECT("select"),
    DATE("date"),
    ;

    internal companion object {
        /** A field type added after this SDK was built is shown as a text field. */
        fun from(wire: String): FormFieldType = entries.firstOrNull { it.wire == wire } ?: TEXT
    }
}

public data class CardItem(
    val imageUrl: String?,
    val title: String,
    val subtitle: String?,
    val buttons: List<CardButton>,
)

/** Exactly one of [payload] (a flow button) and [url] (a link) is set. */
public data class CardButton(
    val id: String,
    val title: String,
    val payload: String?,
    val url: String?,
)

public enum class RatingScale(internal val wire: String) {
    EMOJI_5("emoji_5"),
    STAR_5("star_5"),
    ;

    internal companion object {
        fun from(wire: String): RatingScale? = entries.firstOrNull { it.wire == wire }
    }
}

public enum class RatingComment(internal val wire: String) {
    NONE("none"),
    OPTIONAL("optional"),
    REQUIRED("required"),
    ;

    internal companion object {
        fun from(wire: String?): RatingComment = entries.firstOrNull { it.wire == wire } ?: NONE
    }
}
