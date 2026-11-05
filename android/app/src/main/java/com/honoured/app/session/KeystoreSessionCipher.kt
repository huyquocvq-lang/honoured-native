package com.honoured.app.session

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * AES-256-GCM with a non-exportable key in the Android Keystore. The key does
 * not need the person to unlock the device, so a background worker (M4) can
 * read the session too. Blob layout: version (1 byte), IV length (1 byte),
 * IV, ciphertext + tag.
 */
class KeystoreSessionCipher(private val alias: String = ALIAS) : SessionCipher {

    override fun encrypt(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key(create = true))
        val iv = cipher.iv
        val sealed = cipher.doFinal(plain)
        return ByteBuffer.allocate(2 + iv.size + sealed.size)
            .put(VERSION)
            .put(iv.size.toByte())
            .put(iv)
            .put(sealed)
            .array()
    }

    override fun decrypt(blob: ByteArray): ByteArray {
        require(blob.size > 2 && blob[0] == VERSION) { "Unknown session format" }
        val ivLength = blob[1].toInt()
        require(ivLength in 12..16 && blob.size > 2 + ivLength) { "Corrupt session" }
        val iv = blob.copyOfRange(2, 2 + ivLength)
        val key = key(create = false) ?: throw IllegalStateException("Session key missing")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
        return cipher.doFinal(blob, 2 + ivLength, blob.size - 2 - ivLength)
    }

    override fun reset() {
        keyStore().deleteEntry(alias)
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    private fun key(create: Boolean): SecretKey? {
        (keyStore().getKey(alias, null) as? SecretKey)?.let { return it }
        if (!create) return null
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        generator.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    companion object {
        const val ALIAS = "honoured_session_v1"
        private const val PROVIDER = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val TAG_BITS = 128
        private const val VERSION: Byte = 1
    }
}
