package ai.clomni.messenger.protocol

/** GET /news (protocol/schema/news.json): the channel's published news in the panel's order, in one language. */
internal data class NewsItem(
    val id: String,
    val title: String,
    /** The card's short text. */
    val summary: String?,
    /** The item's own screen: bold, italic, links and lists. */
    val bodyMarkdown: String?,
    val imageUrl: String?,
    val button: Button?,
    /** Epoch ms. */
    val publishedAt: Long?,
) {
    /** A link button under the text: a web address or the app's own deep link. */
    data class Button(val text: String, val url: String)
}
