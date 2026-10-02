package ai.clomni.messenger.ui

import ai.clomni.messenger.presentation.ImageSizing
import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.painter.ColorPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInspectionMode
import coil.ImageLoader
import coil.compose.AsyncImage
import coil.disk.DiskCache
import coil.memory.MemoryCache

/** Pictures by their URL instead of the network, for screenshot tests (which load nothing). */
internal val LocalPreviewImages = staticCompositionLocalOf<Map<String, ImageBitmap>> { emptyMap() }

/** The messenger's own image loader: a memory cache and a disk cache of its own, not the app's. */
internal object ClomniImages {
    @Volatile
    private var loader: ImageLoader? = null

    fun loader(context: Context): ImageLoader = loader ?: synchronized(this) {
        loader ?: context.applicationContext.let { app ->
            ImageLoader.Builder(app)
                .memoryCache { MemoryCache.Builder(app).maxSizePercent(0.10).build() }
                .diskCache { DiskCache.Builder().directory(app.cacheDir.resolve("clomni_images")).maxSizeBytes(50L * 1024 * 1024).build() }
                .crossfade(200)
                .build()
        }.also { loader = it }
    }
}

/**
 * A picture of the panel's (logo, avatar, header picture) at the width this screen needs and as WebP
 * ([ImageSizing]), cached; [placeholder] until it is here (primary_soft, APPEARANCE-CONTRACT 4), then it fades in.
 */
@Composable
internal fun RemoteImage(
    url: String,
    kind: ImageSizing.Kind,
    dp: Float,
    placeholder: Color,
    modifier: Modifier = Modifier,
    fit: Boolean = false,
) {
    val scale = if (fit) ContentScale.Fit else ContentScale.Crop
    val preview = LocalPreviewImages.current[url]
    when {
        preview != null -> Image(preview, null, modifier, contentScale = scale)
        LocalInspectionMode.current -> Box(modifier.background(placeholder))
        else -> {
            val density = LocalDensity.current.density
            val sized = remember(url, kind, dp, density) { ImageSizing.url(url, kind, dp, density) }
            val soft = remember(placeholder) { ColorPainter(placeholder) }
            AsyncImage(
                sized,
                contentDescription = null,
                imageLoader = ClomniImages.loader(LocalContext.current),
                modifier = modifier,
                placeholder = soft,
                error = soft,
                contentScale = scale,
            )
        }
    }
}

/** [RemoteImage] filling the box it is in. */
@Composable
internal fun androidx.compose.foundation.layout.BoxScope.RemoteImageFill(
    url: String,
    kind: ImageSizing.Kind,
    dp: Float,
    placeholder: Color,
    fit: Boolean = false,
) = RemoteImage(url, kind, dp, placeholder, Modifier.matchParentSize(), fit)
