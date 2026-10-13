package ai.clomni.fixtures.collision

import android.content.ContentProvider
import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.ProviderInfo
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.core.content.FileProvider
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.io.File

/**
 * CM-185: the app builds with the SDK next to another androidx FileProvider (that the build got here is the first
 * half), and neither provider pushed the other out: each authority is in the merged manifest with its own class and
 * hands out its own files.
 */
@RunWith(RobolectricTestRunner::class)
class ProviderCollisionTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val camera = "${context.packageName}.clomni.camera"

    @Test
    fun bothProvidersAreInTheApp() {
        assertEquals("ai.clomni.messenger.ui.ClomniFileProvider", provider(camera).name)
        assertEquals(FileProvider::class.java.name, provider(BuildConfig.OTHER_AUTHORITY).name)
    }

    /** What the attachment sheet's camera row does: a file in the cache, its Uri, the camera app writing into it. */
    @Test
    fun theCameraWritesThroughTheSdksProvider() {
        val uri = cameraTarget()
        assertEquals(camera, uri.authority)
        val bytes = byteArrayOf(1, 2, 3)
        ParcelFileDescriptor.AutoCloseOutputStream(open(camera).openFile(uri, "w")).use { it.write(bytes) }
        val written = File(context.cacheDir, "clomni_camera").listFiles()!!.single()
        assertArrayEquals(bytes, written.readBytes())
    }

    @Test
    fun theOtherProviderStillHandsOutItsFiles() {
        val file = File(context.cacheDir, "${BuildConfig.OTHER_DIR}/page.html").apply {
            parentFile!!.mkdirs()
            writeText("<p>hi</p>")
        }
        val uri = FileProvider.getUriForFile(context, BuildConfig.OTHER_AUTHORITY, file)
        assertEquals(BuildConfig.OTHER_AUTHORITY, uri.authority)
        val read = ParcelFileDescriptor.AutoCloseInputStream(open(BuildConfig.OTHER_AUTHORITY).openFile(uri, "r")).use {
            it.readBytes().decodeToString()
        }
        assertEquals("<p>hi</p>", read)
    }

    private fun provider(authority: String): ProviderInfo =
        checkNotNull(context.packageManager.resolveContentProvider(authority, PackageManager.GET_META_DATA)) {
            "no provider for $authority"
        }

    /** The provider the system would start for [authority], started the same way: its class from the manifest. */
    @Suppress("UNCHECKED_CAST")
    private fun open(authority: String): ContentProvider {
        val info = provider(authority)
        return Robolectric.buildContentProvider(Class.forName(info.name) as Class<ContentProvider>).create(info).get()
    }

    /**
     * The SDK's own Attachments.cameraTarget, as the camera row calls it. It is internal to the SDK, so it is reached
     * by reflection: a public function of an internal object keeps its name.
     */
    private fun cameraTarget(): Uri {
        val attachments = Class.forName("ai.clomni.messenger.ui.Attachments")
        val target = attachments.getMethod("cameraTarget", Context::class.java, Boolean::class.javaPrimitiveType)
        val uri = target.invoke(attachments.getField("INSTANCE").get(null), context, false) as Uri?
        return checkNotNull(uri) { "cameraTarget gave no Uri" }
    }
}
