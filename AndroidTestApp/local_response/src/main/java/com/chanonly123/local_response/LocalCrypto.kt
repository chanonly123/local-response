package com.chanonly123.local_response

import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Encrypts the bodies exchanged with the mapper.
 *
 * The key is committed on both sides, so this is not a secret from anyone
 * reading the source — it exists so recorded traffic is not plaintext on a
 * shared network, where a sniffer would otherwise pick up every header and body
 * the app sends. It must match `Constants.sharedKey` in the Swift sources; a
 * mismatch shows up as the mapper rejecting every call.
 *
 * The mapped response served from `/overriden-request` is deliberately not
 * encrypted: it is read by the app's own HTTP client, which knows nothing about
 * this key.
 */
internal object LocalCrypto {

    private const val SHARED_KEY = "LocalResponse/v1/2f8a1c4e9b7d6053"

    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val NONCE_BYTES = 12
    private const val TAG_BITS = 128

    /// AES-GCM needs 32 bytes; the shared string is whatever length it is, so
    /// hash it to length rather than constrain how the constant is written.
    private val key by lazy {
        val digest = MessageDigest.getInstance("SHA-256").digest(SHARED_KEY.toByteArray(Charsets.UTF_8))
        SecretKeySpec(digest, "AES")
    }

    private val random by lazy { SecureRandom() }

    /**
     * Nonce, ciphertext and tag in one blob — the layout CryptoKit calls
     * `combined`, which is what the Swift side reads.
     */
    fun seal(data: ByteArray): ByteArray? {
        return try {
            val nonce = ByteArray(NONCE_BYTES).also { random.nextBytes(it) }
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce))
            // doFinal already appends the tag to the ciphertext, so prefixing
            // the nonce is all that is left to match CryptoKit.
            nonce + cipher.doFinal(data)
        } catch (e: Exception) {
            null
        }
    }

    fun open(data: ByteArray): ByteArray? {
        return try {
            if (data.size <= NONCE_BYTES) return null
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                key,
                GCMParameterSpec(TAG_BITS, data, 0, NONCE_BYTES)
            )
            cipher.doFinal(data, NONCE_BYTES, data.size - NONCE_BYTES)
        } catch (e: Exception) {
            null
        }
    }
}
