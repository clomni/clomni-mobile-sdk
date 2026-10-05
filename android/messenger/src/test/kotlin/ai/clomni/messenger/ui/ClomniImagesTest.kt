package ai.clomni.messenger.ui

import android.graphics.Bitmap
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.view.View
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import coil.ImageLoader
import coil.decode.DataSource
import coil.disk.DiskCache
import coil.memory.MemoryCache
import coil.request.ImageRequest
import coil.request.SuccessResult
import coil.transition.CrossfadeTransition
import coil.transition.TransitionTarget
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/** Logout empties the messenger's own picture caches: the next user sees none of this one's (CM-077). */
class ClomniImagesTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5)

    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun logoutEmptiesMemoryAndDisk() {
        val directory = folder.newFolder("clomni_images")
        val loader = ImageLoader.Builder(paparazzi.context)
            .memoryCache { MemoryCache.Builder(paparazzi.context).maxSizeBytes(1024 * 1024).build() }
            .diskCache { DiskCache.Builder().directory(directory).build() }
            .build()
        val key = MemoryCache.Key("https://app.clomni.ai/v1/uploads/photo.jpg")
        loader.memoryCache!![key] = MemoryCache.Value(Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888))
        val disk = loader.diskCache!!
        disk.openEditor(key.key)!!.run {
            disk.fileSystem.write(data) { writeUtf8("a picture") }
            commit()
        }
        assertNotNull(loader.memoryCache!![key])
        assertNotNull(disk.openSnapshot(key.key)?.also { it.close() })

        ClomniImages.clear(loader, directory)

        assertNull(loader.memoryCache!![key])
        assertEquals(0, loader.memoryCache!!.size)
        assertNull(disk.openSnapshot(key.key))
    }

    /**
     * DESIGN-PASS-3 C2: a picture from the disk or memory is there in its first frame; only one from the network fades
     * in. (Coil's own pipeline needs a running main looper, which these tests do not have.)
     */
    @Test
    fun onlyAPictureFromTheNetworkFadesIn() {
        val context = paparazzi.context
        val loader = ClomniImages.build(context, folder.newFolder("clomni_images"))
        val request = ImageRequest.Builder(context).data("https://app.clomni.ai/v1/brand/logo.png?v=3").build()
        val target = object : TransitionTarget {
            override val view = View(context)
            override val drawable: Drawable? = null
        }
        fun transition(source: DataSource) =
            loader.defaults.transitionFactory.create(target, SuccessResult(ColorDrawable(0), request, source))
        assertTrue(transition(DataSource.NETWORK) is CrossfadeTransition)
        for (kept in listOf(DataSource.DISK, DataSource.MEMORY_CACHE, DataSource.MEMORY)) {
            assertFalse("$kept", transition(kept) is CrossfadeTransition)
            assertFalse(ClomniImages.fadesIn(SuccessResult(ColorDrawable(0), request, kept)))
        }
        assertNotNull("kept on disk", loader.diskCache)
    }

    /** Before this run's loader exists, the folder a previous run left goes. */
    @Test
    fun withoutALoaderTheFolderGoes() {
        val directory = folder.newFolder("clomni_images")
        File(directory, "journal").writeText("libcore.io.DiskLruCache")
        ClomniImages.clear(null, directory)
        assertFalse(directory.exists())
    }
}
