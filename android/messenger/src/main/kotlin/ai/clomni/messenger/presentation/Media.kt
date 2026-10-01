package ai.clomni.messenger.presentation

import java.util.Locale

/** Sizes and labels of images and files in the conversation (brief 8·7.4, 8·5.5). */
internal object Media {
    const val MAX_IMAGE_WIDTH = 220.0
    const val MAX_IMAGE_HEIGHT = 300.0

    /** Images are scaled so their longer side is at most this many pixels before they are sent. */
    const val MAX_UPLOAD_SIDE = 2048.0

    data class Box(val width: Double, val height: Double, val known: Boolean)

    /**
     * The box an image takes in its bubble, reserved before it loads so the list does not jump: its own ratio within
     * 220×300 (never larger than the image), or a 4:3 placeholder when the size is unknown.
     */
    fun imageBox(width: Int?, height: Int?): Box {
        if (width == null || height == null || width <= 0 || height <= 0) {
            return Box(MAX_IMAGE_WIDTH, MAX_IMAGE_WIDTH * 3 / 4, false)
        }
        val scale = minOf(1.0, MAX_IMAGE_WIDTH / width, MAX_IMAGE_HEIGHT / height)
        return Box(Math.round(width * scale).toDouble(), Math.round(height * scale).toDouble(), true)
    }

    /** The pixel size to send an image of [width]×[height] at. */
    fun uploadSize(width: Int, height: Int): Pair<Int, Int> {
        val scale = minOf(1.0, MAX_UPLOAD_SIDE / maxOf(width, height, 1))
        return Math.round(width * scale).toInt() to Math.round(height * scale).toInt()
    }

    /** "820 B", "182 KB", "1,4 MB" (a decimal point in English). */
    fun fileSize(bytes: Long, language: String): String = when {
        bytes < 1_000 -> "${maxOf(0, bytes)} B"
        bytes < 1_000_000 -> "${Math.round(bytes / 1_000.0)} KB"
        else -> {
            val megabytes = String.format(Locale.ROOT, "%.1f", bytes / 1_000_000.0)
            (if (language == "en") megabytes else megabytes.replace('.', ',')) + " MB"
        }
    }

    /** The icon of a file card. */
    enum class FileIcon { PDF, IMAGE, AUDIO, VIDEO, DOCUMENT }

    fun fileIcon(mime: String): FileIcon = when {
        mime == "application/pdf" -> FileIcon.PDF
        mime.startsWith("image/") -> FileIcon.IMAGE
        mime.startsWith("audio/") -> FileIcon.AUDIO
        mime.startsWith("video/") -> FileIcon.VIDEO
        else -> FileIcon.DOCUMENT
    }

    fun isImage(mime: String): Boolean = mime.startsWith("image/")
}
