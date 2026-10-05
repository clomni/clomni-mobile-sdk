package ai.clomni.messenger.protocol

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// The parsed types written back in the wire format, so the SDK keeps them on disk (session, conversations, messages)
// and reads them with the same parser. Parsing the result gives the same value again.

internal fun MobileSession.toJson(): JsonObject = buildJsonObject {
    put("session_token", sessionToken)
    put("expires_at", Iso8601.format(expiresAt))
    put("refresh_token", refreshToken)
    put("ws_url", wsUrl)
    put(
        "user",
        buildJsonObject {
            put("id", userId)
            put("anonymous", anonymous)
            put("language", language)
        },
    )
}

internal fun Conversation.toJson(): JsonObject = buildJsonObject {
    put("id", id)
    put("status", status.wire)
    put("assignee", assignee?.toJson() ?: JsonNull)
    put("unread_count", unreadCount)
    put("last_message", lastMessage?.toJson() ?: JsonNull)
    put(
        "flow",
        flow?.let {
            buildJsonObject {
                put("active", it.active)
                put("awaiting", it.awaiting)
                putIfPresent("flow_id", it.flowId)
                putIfPresent("node_id", it.nodeId)
            }
        } ?: JsonNull,
    )
    put("opened_from", openedFrom)
    put("created_at", Iso8601.format(createdAt))
}

internal fun Message.toJson(): JsonObject = buildJsonObject {
    put("id", id)
    put("client_id", clientId)
    put("conversation_id", conversationId)
    put("type", type)
    put(
        "sender",
        buildJsonObject {
            put("type", sender.type.wire)
            putIfPresent("id", sender.id)
            putIfPresent("name", sender.name)
            putIfPresent("avatar_url", sender.avatarUrl)
        },
    )
    put("created_at", Iso8601.format(createdAt))
    put("seq", seq)
    put("lang", lang)
    put(
        "flow",
        flow?.let {
            buildJsonObject {
                put("flow_id", it.flowId)
                put("node_id", it.nodeId)
                putIfPresent("version", it.version)
                put("interactive", it.interactive)
            }
        } ?: JsonNull,
    )
    put("content", content.toJson())
    put("fallback_text", fallbackText)
    replyTo?.let { quoted ->
        put(
            "reply_to",
            buildJsonObject {
                put("id", quoted.id)
                put(
                    "sender",
                    quoted.sender?.let { sender ->
                        buildJsonObject {
                            put("type", sender.type.wire)
                            putIfPresent("name", sender.name)
                        }
                    } ?: JsonNull,
                )
                put("excerpt", quoted.excerpt)
                put("kind", quoted.kind)
            },
        )
    }
}

private fun Assignee.toJson(): JsonObject = buildJsonObject {
    put("name", name)
    put("avatar_url", avatarUrl)
    putIfPresent("online", online)
}

private fun MessageContent.toJson(): JsonElement = when (this) {
    is MessageContent.Text -> buildJsonObject { put("text", text) }
    is MessageContent.QuickReplies -> buildJsonObject {
        putIfPresent("text", text)
        put("buttons", JsonArray(buttons.map { it.toJson() }))
        put("layout", if (layout == MessageContent.QuickRepliesLayout.CHIPS) "chips" else "vertical")
        put("input_disabled", inputDisabled)
        put("allow_back", allowBack)
    }
    is MessageContent.Image -> buildJsonObject {
        put("url", url)
        put("thumb_url", thumbUrl)
        put("width", width)
        put("height", height)
        put("caption", caption)
    }
    is MessageContent.File -> buildJsonObject {
        put("url", url)
        put("name", name)
        put("size", size)
        put("mime", mime)
    }
    is MessageContent.Form -> buildJsonObject {
        putIfPresent("text", text)
        put("form_id", formId)
        put("fields", JsonArray(fields.map { it.toJson() }))
        put("submit_title", submitTitle)
        put("submitted", submitted?.let(::JsonObject) ?: JsonNull)
    }
    is MessageContent.System -> buildJsonObject {
        put("event", event.wire)
        put("text", text)
        putIfPresent("position", position)
    }
    is MessageContent.Card -> buildJsonObject { put("cards", JsonArray(cards.map { it.toJson() })) }
    is MessageContent.Rating -> buildJsonObject {
        put("text", text)
        put("scale", scale.wire)
        put("comment", comment.wire)
        put("submitted", submitted?.let(::JsonObject) ?: JsonNull)
    }
    is MessageContent.Unknown -> raw
}

private fun MessageContent.Button.toJson() = buildJsonObject {
    put("id", id)
    put("title", title)
    put("icon", icon)
    put("payload", payload)
}

private fun MessageContent.FormField.toJson() = buildJsonObject {
    put("key", key)
    put("type", type.wire)
    put("label", label)
    put("required", required)
    putIfPresent("max_length", maxLength)
    putIfPresent("default_country", defaultCountry)
    putIfPresent("placeholder", placeholder)
    if (type == MessageContent.FormFieldType.SELECT) {
        put("options", JsonArray(options.map { buildJsonObject { put("value", it.value); put("label", it.label) } }))
    }
}

private fun MessageContent.CardItem.toJson() = buildJsonObject {
    put("image_url", imageUrl)
    put("title", title)
    put("subtitle", subtitle)
    put(
        "buttons",
        JsonArray(
            buttons.map {
                buildJsonObject {
                    put("id", it.id)
                    put("title", it.title)
                    putIfPresent("payload", it.payload)
                    putIfPresent("url", it.url)
                }
            },
        ),
    )
}

private val MessageContent.SystemEvent.wire: String
    get() = when (this) {
        MessageContent.SystemEvent.OperatorJoined -> "operator_joined"
        MessageContent.SystemEvent.AssignedToTeam -> "assigned_to_team"
        MessageContent.SystemEvent.ConversationClosed -> "conversation_closed"
        MessageContent.SystemEvent.ConversationReopened -> "conversation_reopened"
        MessageContent.SystemEvent.WaitingInQueue -> "waiting_in_queue"
        is MessageContent.SystemEvent.Unknown -> raw
    }

private fun JsonObjectBuilder.putIfPresent(key: String, value: String?) {
    if (value != null) put(key, value)
}

private fun JsonObjectBuilder.putIfPresent(key: String, value: Number?) {
    if (value != null) put(key, value)
}

private fun JsonObjectBuilder.putIfPresent(key: String, value: Boolean?) {
    if (value != null) put(key, value)
}
