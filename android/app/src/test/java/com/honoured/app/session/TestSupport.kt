package com.honoured.app.session

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import org.json.JSONObject
import java.io.File
import java.nio.file.Files

/** Reversible stand-in for the Keystore cipher in JVM tests. */
class FakeCipher : SessionCipher {
    var broken = false
    var failEncrypt = false
    var resets = 0

    override fun encrypt(plain: ByteArray): ByteArray = if (failEncrypt) throw IllegalStateException("keystore busy") else MAGIC + plain.map { (it.toInt() xor 0x5A).toByte() }.toByteArray()

    override fun decrypt(blob: ByteArray): ByteArray {
        if (broken) throw IllegalStateException("key gone")
        require(blob.size >= MAGIC.size && blob.copyOfRange(0, MAGIC.size).contentEquals(MAGIC)) { "corrupt" }
        return blob.copyOfRange(MAGIC.size, blob.size).map { (it.toInt() xor 0x5A).toByte() }.toByteArray()
    }

    override fun reset() {
        resets += 1
    }

    private companion object {
        val MAGIC = byteArrayOf(0x48, 0x4F, 0x4E)
    }
}

object Fixtures {
    fun tempDir(): File = Files.createTempDirectory("honoured-test").toFile().apply { deleteOnExit() }

    fun session(user: String = "user-a", access: String = "access-1", refresh: String = "refresh-1", expiresAt: Double = 2_000_000_000.0) =
        NativeAuthSession(user, access, refresh, expiresAt)

    /** A Supabase refresh-token grant response. */
    fun response(user: String, access: String, refresh: String, expiresAt: Long = 2_000_003_600L): JSONObject = JSONObject()
        .put("access_token", access)
        .put("refresh_token", refresh)
        .put("expires_in", 3600)
        .put("expires_at", expiresAt)
        .put("token_type", "bearer")
        .put("user", JSONObject().put("id", user))
}

/** Like the app's SessionServices scope: a failed refresh never cancels its siblings. */
fun TestScope.supervised(): CoroutineScope =
    CoroutineScope(backgroundScope.coroutineContext + SupervisorJob(backgroundScope.coroutineContext[Job]))

/** Runs background work (mutation queue, launched refreshes) that `advanceUntilIdle` skips. */
fun TestScope.settle() = repeat(10) { runCurrent() }
