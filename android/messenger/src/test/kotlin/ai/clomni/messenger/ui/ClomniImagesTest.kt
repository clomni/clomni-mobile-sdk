package ai.clomni.messenger.ui

import android.graphics.Bitmap
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import coil.ImageLoader
import coil.disk.DiskCache
import coil.memory.MemoryCache
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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

    /** Before this run's loader exists, the folder a previous run left goes. */
    @Test
    fun withoutALoaderTheFolderGoes() {
        val directory = folder.newFolder("clomni_images")
        File(directory, "journal").writeText("libcore.io.DiskLruCache")
        ClomniImages.clear(null, directory)
        assertFalse(directory.exists())
    }
}
