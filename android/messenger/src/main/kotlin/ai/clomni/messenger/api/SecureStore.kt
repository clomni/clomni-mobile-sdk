package ai.clomni.messenger.api

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Small secrets: the session and refresh tokens, the identity to log in again with, the anonymous user, the device id. */
internal interface SecureStore {
    fun read(key: String): String?

    /** Null deletes. */
    fun write(key: String, value: String?)
}

/** For tests, and wherever there is no Keystore. */
internal class MemorySecureStore : SecureStore {
    private val items = mutableMapOf<String, String>()

    @Synchronized
    override fun read(key: String): String? = items[key]

    @Synchronized
    override fun write(key: String, value: String?) {
        if (value == null) items.remove(key) else items[key] = value
    }
}

/**
 * Files encrypted with AES-GCM under a key that never leaves the Android Keystore, in `noBackupFilesDir`: the key
 * cannot be restored to another device, so neither are the files. A file that no longer decrypts (the key was
 * removed, say by a factory reset of the Keystore) reads as absent, and the SDK opens a new session.
 */
internal class KeystoreSecureStore(context: Context, appId: String) : SecureStore {
    private val dir = File(context.noBackupFilesDir, "clomni/$appId/secure")
    private val alias = "ai.clomni.messenger.$appId"

    @Synchronized
    override fun read(key: String): String? {
        val file = File(dir, key)
        if (!file.exists()) return null
        return try {
            val bytes = file.readBytes()
            val ivLength = bytes[0].toInt()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, bytes, 1, ivLength))
            String(cipher.doFinal(bytes, 1 + ivLength, bytes.size - 1 - ivLength), Charsets.UTF_8)
        } catch (e: Exception) {
            file.delete()
            null
        }
    }

    @Synchronized
    override fun write(key: String, value: String?) {
        val file = File(dir, key)
        if (value == null) {
            file.delete()
            return
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        dir.mkdirs()
        val temp = File(dir, "$key.tmp")
        temp.writeBytes(byteArrayOf(cipher.iv.size.toByte()) + cipher.iv + sealed)
        temp.renameTo(file)
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val TAG_BITS = 128
    }
}
