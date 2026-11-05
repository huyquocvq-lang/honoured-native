package com.honoured.app.session

import org.json.JSONObject
import java.io.File

/** Encrypts the stored session. The production implementation is [KeystoreSessionCipher]. */
interface SessionCipher {
    fun encrypt(plain: ByteArray): ByteArray

    /** Throws when the blob cannot be decrypted (key lost, data corrupted). */
    fun decrypt(blob: ByteArray): ByteArray

    /** Forgets the key, so an old copy of the file can never be read again. */
    fun reset() {}
}

/**
 * The one copy of the Supabase session native keeps, encrypted, in a file
 * under `noBackupFilesDir` (excluded from cloud backup and device transfer).
 * Every method is blocking and serialised on one lock: call it off the main
 * thread. A file that cannot be read is treated as no session and removed,
 * never as a crash.
 */
class SessionStore(private val file: File, private val cipher: SessionCipher) {
    private val lock = Any()
    private var cached: NativeAuthSession? = null
    private var loaded = false

    /** True when the last read found a file it could not decrypt or parse. */
    @Volatile var lastReadWasUnreadable: Boolean = false
        private set

    fun load(): NativeAuthSession? = synchronized(lock) { loadLocked() }

    fun save(session: NativeAuthSession) = synchronized(lock) { saveLocked(session) }

    /**
     * Stores [next] only while the stored session is still [expected] (same
     * user and refresh token). A refresh that finished after the page signed
     * out, switched account or stored a newer session must not overwrite it.
     */
    fun replaceIf(expected: NativeAuthSession, next: NativeAuthSession): Boolean = synchronized(lock) {
        val stored = loadLocked() ?: return@synchronized false
        if (stored.userId != expected.userId || stored.refreshToken != expected.refreshToken) return@synchronized false
        saveLocked(next)
        true
    }

    fun clear() = synchronized(lock) {
        cached = null
        loaded = true
        if (file.exists() && !file.delete()) throw IllegalStateException("Could not delete the stored session")
    }

    private fun loadLocked(): NativeAuthSession? {
        if (loaded) return cached
        loaded = true
        lastReadWasUnreadable = false
        if (!file.exists()) {
            cached = null
            return null
        }
        cached = runCatching {
            val plain = cipher.decrypt(file.readBytes())
            NativeAuthSession.fromJson(JSONObject(String(plain, Charsets.UTF_8)))
                ?: throw IllegalStateException("Stored session is invalid")
        }.getOrElse {
            // Key gone (restored to a new device, Keystore reset) or a corrupt
            // file: forget it. The page still has its own session and refreshes
            // for itself until it hands native a new one.
            lastReadWasUnreadable = true
            file.delete()
            runCatching { cipher.reset() }
            null
        }
        return cached
    }

    private fun saveLocked(session: NativeAuthSession) {
        val blob = cipher.encrypt(session.toJson().toString().toByteArray(Charsets.UTF_8))
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeBytes(blob)
        if (!tmp.renameTo(file)) {
            tmp.delete()
            throw IllegalStateException("Could not store the session")
        }
        cached = session
        loaded = true
    }
}
