package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ChatController
import ai.clomni.messenger.presentation.Media
import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream

/** Reads what the pickers hand back; runs on the conversation's worker, never on the UI thread. */
internal object Attachments {
    /**
     * A picked photo as a JPEG with its longer side at most 2048 px (brief 8·5.5), turned upright by its EXIF
     * orientation; transparency becomes white. Null when it cannot be decoded.
     */
    fun image(resolver: ContentResolver, uri: Uri): ChatController.PickedFile? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val (width, height) = Media.uploadSize(bounds.outWidth, bounds.outHeight)
        // Decode at the smallest power-of-two step that is still at least the target size, then scale exactly.
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= width && bounds.outHeight / (sample * 2) >= height) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        val decoded = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) } ?: return null
        val matrix = Matrix().apply {
            postScale(width.toFloat() / decoded.width, height.toFloat() / decoded.height)
            val degrees = rotation(resolver, uri)
            if (degrees != 0) postRotate(degrees.toFloat())
        }
        val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        val opaque = if (upright.hasAlpha()) {
            Bitmap.createBitmap(upright.width, upright.height, Bitmap.Config.ARGB_8888).also {
                Canvas(it).apply {
                    drawColor(Color.WHITE)
                    drawBitmap(upright, 0f, 0f, null)
                }
            }
        } else {
            upright
        }
        val out = ByteArrayOutputStream()
        opaque.compress(Bitmap.CompressFormat.JPEG, 85, out)
        return ChatController.PickedFile(out.toByteArray(), "image.jpg", "image/jpeg")
    }

    /** A picked or taken file as it is sent: a picture scaled ([image]), anything else as it is ([file]). */
    fun read(resolver: ContentResolver, uri: Uri, maxBytes: Long): ChatController.PickedFile? =
        if (resolver.getType(uri)?.startsWith("image/") == true) image(resolver, uri) else file(resolver, uri, maxBytes)

    /** A file's name for its preview. */
    fun name(resolver: ContentResolver, uri: Uri): String = runCatching {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }.getOrNull() ?: uri.lastPathSegment ?: "file"

    /** Where the camera writes the next photo: a new file in the app's cache, shared with the camera app by Uri. */
    fun cameraTarget(context: android.content.Context): Uri? = runCatching {
        val dir = java.io.File(context.cacheDir, "clomni_camera").apply { mkdirs() }
        val file = java.io.File(dir, "photo-${System.currentTimeMillis()}.jpg")
        androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.clomni.camera", file)
    }.getOrNull()

    /**
     * A picked file, read up to one byte over [maxBytes]: the engine refuses what is over its limit, and nothing larger
     * is held in memory. Null when it cannot be opened.
     */
    fun file(resolver: ContentResolver, uri: Uri, maxBytes: Long): ChatController.PickedFile? {
        val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: uri.lastPathSegment ?: "file"
        val mime = resolver.getType(uri) ?: "application/octet-stream"
        val data = resolver.openInputStream(uri)?.use { input ->
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            var total = 0L
            while (total <= maxBytes) {
                val read = input.read(buffer)
                if (read < 0) break
                out.write(buffer, 0, read)
                total += read
            }
            out.toByteArray()
        } ?: return null
        return ChatController.PickedFile(data, name, mime)
    }

    /**
     * Degrees to turn a photo upright; the platform's ExifInterface reads a stream from API 24 (lint prefers
     * androidx.exifinterface, which the SDK's dependency rule leaves out).
     */
    private fun rotation(resolver: ContentResolver, uri: Uri): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return 0
        val orientation = runCatching {
            resolver.openInputStream(uri)?.use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            }
        }.getOrNull()
        return when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90
            ExifInterface.ORIENTATION_ROTATE_180 -> 180
            ExifInterface.ORIENTATION_ROTATE_270 -> 270
            else -> 0
        }
    }
}
