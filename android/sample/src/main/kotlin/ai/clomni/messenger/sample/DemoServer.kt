package ai.clomni.messenger.sample

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Stands in for the app's own server. The user hash proves to Clomni that the user is who the app says; it is
 * computed with the inbox's Identity Secret, which lives on the server and never in the app. The sample computes
 * it here only because it has no server: never ship an Identity Secret in an app.
 */
object DemoServer {
    private const val IDENTITY_SECRET = "demo-identity-secret"

    /** What the app's login answer would carry: hex(HMAC-SHA256(identity_secret, user_id)). */
    fun userHash(userId: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(IDENTITY_SECRET.toByteArray(), "HmacSHA256"))
        return mac.doFinal(userId.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}
