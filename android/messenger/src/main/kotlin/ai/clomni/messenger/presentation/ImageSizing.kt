package ai.clomni.messenger.presentation

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import kotlin.math.ceil

/**
 * The panel's pictures come in a few widths and as WebP (APPEARANCE-CONTRACT 1): `?w=48|96|144` for logos and
 * avatars, `?w=360|720|1080` for the header picture, `&format=webp`. The SDK asks for the smallest width that covers
 * the picture on this screen (a 28 dp logo at 3x is 84 px: 96), the largest when none does.
 */
internal object ImageSizing {
    enum class Kind(val widths: List<Int>) {
        ICON(listOf(48, 96, 144)),
        HEADER(listOf(360, 720, 1080)),

        /** The written logo: `?w=300|600|1200`. */
        WORDMARK(listOf(300, 600, 1200)),
    }

    /** [url] for a picture [dp] wide on a screen of [density]; the URL's own query stays. */
    fun url(url: String, kind: Kind, dp: Float, density: Float): String {
        val pixels = ceil(dp.toDouble() * density).toInt()
        val width = kind.widths.firstOrNull { it >= pixels } ?: kind.widths.last()
        val parsed = url.toHttpUrlOrNull() ?: return url
        return parsed.newBuilder()
            .removeAllQueryParameters("w")
            .removeAllQueryParameters("format")
            .addQueryParameter("w", width.toString())
            .addQueryParameter("format", "webp")
            .build()
            .toString()
    }
}
