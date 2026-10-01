package ai.clomni.messenger.protocol

/**
 * The Clomni keys of a push (`protocol/schema/push.json`): an FCM data message, or the keys next to `aps` on APNs.
 * Only payloads with `"clomni": "1"` are Clomni pushes.
 */
public data class PushPayload(
    /** `message` in v1. */
    val type: String,
    val conversationId: String,
    val messageId: String?,
    val title: String,
    /** Up to 180 characters as the server sends it; not shortened here. */
    val body: String,
    val avatarUrl: String?,
    val unreadTotal: Int?,
)
