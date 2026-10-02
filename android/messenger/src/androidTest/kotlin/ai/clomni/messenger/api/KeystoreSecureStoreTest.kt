package ai.clomni.messenger.api

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.KeyStore

/** The session and the identity, sealed with an Android Keystore key (AES-GCM), on a device. */
@RunWith(AndroidJUnit4::class)
class KeystoreSecureStoreTest {
    private val appId = "app_keystore_test"
    private val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.noBackupFilesDir, "clomni/$appId/secure")
    private val store = KeystoreSecureStore(dir, appId)

    @After
    fun clean() {
        dir.deleteRecursively()
        deleteKey()
    }

    private fun deleteKey() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry("ai.clomni.messenger.$appId")

    @Test
    fun writesReadsAndDeletes() {
        assertNull(store.read("session"))
        store.write("session", """{"token":"t_1","refresh_token":"r_1"}""")
        assertEquals("""{"token":"t_1","refresh_token":"r_1"}""", store.read("session"))
        assertFalse("sealed, not plain text", File(dir, "session").readText(Charsets.ISO_8859_1).contains("t_1"))
        assertEquals("a second store reads the same", """{"token":"t_1","refresh_token":"r_1"}""", KeystoreSecureStore(dir, appId).read("session"))
        store.write("session", null)
        assertNull(store.read("session"))
        assertFalse(File(dir, "session").exists())
    }

    /** The key gone (a restore to a new phone, a cleared Keystore): a clean start, not a crash. */
    @Test
    fun aLostKeyIsACleanStart() {
        store.write("identity", "aysel")
        deleteKey()
        assertNull(KeystoreSecureStore(dir, appId).read("identity"))
        assertFalse("the unreadable file is gone", File(dir, "identity").exists())
        store.write("identity", "aysel")
        assertEquals("aysel", store.read("identity"))
    }
}
