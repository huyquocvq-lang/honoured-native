package com.honoured.app.session

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** The real Android Keystore: AES-GCM round trip, tamper detection, key loss. */
@RunWith(AndroidJUnit4::class)
class KeystoreSessionCipherTest {
    private val cipher = KeystoreSessionCipher(alias = "honoured_session_test")
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val file = File(context.noBackupFilesDir, "test/session.bin")

    @After fun tearDown() {
        cipher.reset()
        file.delete()
    }

    @Test fun roundTripsWithAFreshIvEachTime() {
        val plain = "{\"refreshToken\":\"secret\"}".toByteArray()
        val a = cipher.encrypt(plain)
        val b = cipher.encrypt(plain)
        assertFalse("random IV", a.contentEquals(b))
        assertArrayEquals(plain, cipher.decrypt(a))
        assertArrayEquals(plain, cipher.decrypt(b))
        assertFalse(String(a, Charsets.ISO_8859_1).contains("secret"))
    }

    @Test fun aTamperedBlobOrALostKeyCannotBeRead() {
        val blob = cipher.encrypt("hello".toByteArray())
        val tampered = blob.copyOf().also { it[it.size - 1] = (it[it.size - 1].toInt() xor 1).toByte() }
        assertTrue(runCatching { cipher.decrypt(tampered) }.isFailure)
        cipher.reset()
        assertTrue(runCatching { cipher.decrypt(blob) }.isFailure)
    }

    @Test fun theStoreUsesItAndForgetsAnUnreadableSession() {
        val store = SessionStore(file, cipher)
        val session = NativeAuthSession("user-a", "access", "refresh", 2_000_000_000.0)
        store.save(session)
        assertEquals(session, SessionStore(file, cipher).load())
        cipher.reset()
        val reopened = SessionStore(file, cipher)
        assertNull(reopened.load())
        assertTrue(reopened.lastReadWasUnreadable)
        assertFalse(file.exists())
    }
}
