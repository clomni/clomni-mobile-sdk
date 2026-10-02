package ai.clomni.messenger.log

import ai.clomni.messenger.Clomni
import ai.clomni.messenger.ClomniLogLevel
import ai.clomni.messenger.ClomniThemeMode
import ai.clomni.messenger.api.ApiClient
import ai.clomni.messenger.api.ApiConfiguration
import ai.clomni.messenger.api.ClomniError
import ai.clomni.messenger.api.Credentials
import ai.clomni.messenger.api.DeviceInfo
import ai.clomni.messenger.api.MemorySecureStore
import ai.clomni.messenger.api.SessionIdentity
import ai.clomni.messenger.api.UserIdentity
import ai.clomni.messenger.presentation.RgbColor
import ai.clomni.messenger.presentation.ThemeOverride
import ai.clomni.messenger.protocol.MessengerConfig
import ai.clomni.messenger.protocol.ProtocolJson
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ClomniLogTest {
    private val lines = mutableListOf<String>()

    init {
        ClomniLog.handler = { level, line -> lines += "${level.name.lowercase()}: $line" }
    }

    @After
    fun reset() = ClomniLog.reset()

    @Test
    fun levels() {
        assertEquals("the default", ClomniLog.Level.WARNING, ClomniLog.level)
        var made = 0
        ClomniLog.error { "e" }
        ClomniLog.warning { "w" }
        ClomniLog.info { made++; "i" }
        ClomniLog.debug { made++; "d" }
        assertEquals(listOf("error: e", "warning: w"), lines)
        assertEquals("a line is made only when its level is written", 0, made)

        Clomni.setLogLevel(ClomniLogLevel.DEBUG)
        ClomniLog.debug { "d" }
        Clomni.setLogLevel(ClomniLogLevel.ERROR)
        ClomniLog.warning { "w2" }
        Clomni.setLogLevel(ClomniLogLevel.NONE)
        ClomniLog.error { "e2" }
        assertEquals(listOf("error: e", "warning: w", "debug: d"), lines)
    }

    /** Clomni.setTheme: each call replaces the last; a colour that is not #RRGGBB is said and left to the panel. */
    @Test
    fun setThemesColourAndMode() {
        assertEquals(
            ThemeOverride(RgbColor.parse("#0A66C2"), MessengerConfig.ThemeMode.DARK),
            Clomni.themeOverride("#0A66C2", ClomniThemeMode.DARK),
        )
        assertEquals("nothing given: the panel's", ThemeOverride(), Clomni.themeOverride(null, null))
        assertEquals(ThemeOverride(mode = MessengerConfig.ThemeMode.SYSTEM), Clomni.themeOverride("blue", ClomniThemeMode.SYSTEM))
        assertEquals(listOf("error: setTheme: primaryColor \"blue\" is not #RRGGBB; the panel's colour stays"), lines)
        assertEquals(MessengerConfig.ThemeMode.LIGHT, ClomniThemeMode.LIGHT.mode)
    }

    /** Brief 8·6.6: the two mistakes of an integration, in the words the brief gives them. */
    @Test
    fun aWrongKeyOrHashIsSaidPlainly() {
        val server = MockWebServer()
        try {
            val api = ApiClient(
                ApiConfiguration("app_8x2k", "android_sdk-wrong", server.url("/v1").toString(), "1.0.0"),
                Credentials(MemorySecureStore(), ProtocolJson()),
                ProtocolJson(),
                { DeviceInfo("d_1", "14", "1.0", "1.0.0", "az-AZ", "Asia/Baku", "Pixel") },
                ApiClient.defaultClient(),
                sleep = {},
            )
            fun error(status: Int, code: String) = MockResponse().setResponseCode(status)
                .setBody("""{"error":{"code":"$code","message":"x","request_id":"req_1"}}""")
            server.enqueue(error(401, "invalid_api_key"))
            server.enqueue(error(403, "identity_verification_failed"))
            server.enqueue(error(404, "conversation_not_found"))
            for (identity in listOf(SessionIdentity.Anonymous, SessionIdentity.User(UserIdentity("5"), "bad"))) {
                assertTrue(runCatching { api.open(identity) }.exceptionOrNull() is ClomniError.Server)
            }
            assertEquals(
                listOf(
                    "error: api_key səhvdir və ya bu platforma üçün deyil",
                    "error: user_hash səhvdir. identity_secret və user_id-ni yoxlayın",
                ),
                lines,
            )
        } finally {
            server.shutdown()
        }
    }
}
