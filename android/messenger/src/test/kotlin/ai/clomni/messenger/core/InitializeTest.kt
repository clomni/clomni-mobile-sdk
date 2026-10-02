package ai.clomni.messenger.core

import ai.clomni.messenger.api.ApiClient
import ai.clomni.messenger.api.ApiConfiguration
import ai.clomni.messenger.api.DeviceInfo
import ai.clomni.messenger.api.MemorySecureStore
import ai.clomni.messenger.api.SecureStore
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit

/**
 * `Clomni.initialize` runs on the app's main thread, within 50 ms (brief 8·10): building the engine reads no stored
 * credential and builds no HTTP client there (building one reads the system's certificates); both happen on the SDK's
 * worker when it first needs them. The device test (androidTest) adds StrictMode and the clock.
 */
class InitializeTest {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun theCallingThreadTouchesNeitherDiskNorNetwork() {
        val caller = Thread.currentThread()
        val onCaller = CopyOnWriteArrayList<String>()
        val offCaller = CopyOnWriteArrayList<String>()
        fun note(what: String) = (if (Thread.currentThread() === caller) onCaller else offCaller).add(what)
        val secure = object : SecureStore {
            private val inner = MemorySecureStore()

            override fun read(key: String): String? = inner.read(key).also { note("read $key") }

            override fun write(key: String, value: String?) {
                note("write $key")
                inner.write(key, value)
            }
        }
        var builtOn: Thread? = null
        val http = lazy {
            builtOn = Thread.currentThread()
            ApiClient.defaultClient()
        }
        val cache = File(folder.root, "no_backup/clomni/app_1/cache")
        val server = MockWebServer()
        server.enqueue(MockResponse().setResponseCode(503))
        try {
            val engine = AndroidMessenger.engine(
                ApiConfiguration("app_1", "android_sdk-k", server.url("/v1").toString(), "1.0.0"),
                secure,
                cache,
                http,
            ) { DeviceInfo(it, "14", "1.0", "1.0.0", "az-AZ", "Asia/Baku", "Pixel") }
            assertEquals("nothing read or written on the calling thread", emptyList<String>(), onCaller)
            assertFalse("no HTTP client built yet", http.isInitialized())
            assertFalse("not even the cache's folder", cache.exists())

            // The first request: the worker reads the credentials and builds the client.
            engine.loginUnidentifiedUser().runCatching { get(10, TimeUnit.SECONDS) }
            assertTrue(http.isInitialized())
            assertNotSame(caller, builtOn)
            assertTrue(offCaller.toString(), offCaller.isNotEmpty())
            assertEquals(emptyList<String>(), onCaller)
            engine.shutdown()
        } finally {
            server.shutdown()
        }
    }
}
