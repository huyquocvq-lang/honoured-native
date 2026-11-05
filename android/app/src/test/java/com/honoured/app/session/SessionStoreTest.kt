package com.honoured.app.session

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class NativeAuthSessionTest {
    private fun payload() = JSONObject()
        .put("requestId", "r-1")
        .put("userId", "user-a")
        .put("accessToken", "secret-access")
        .put("refreshToken", "secret-refresh")
        .put("expiresAt", 1_900_000_000)

    @Test fun acceptsAValidSetPayloadWithIntegerOrDecimalExpiry() {
        assertEquals(1_900_000_000.0, NativeAuthSession.fromSetPayload(payload())!!.expiresAt, 0.0)
        assertEquals(1.5, NativeAuthSession.fromSetPayload(payload().put("expiresAt", 1.5))!!.expiresAt, 0.0)
    }

    @Test fun rejectsMissingEmptyOrWronglyTypedFields() {
        for (key in listOf("userId", "accessToken", "refreshToken", "expiresAt")) {
            assertNull("missing $key", NativeAuthSession.fromSetPayload(payload().apply { remove(key) }))
        }
        for (key in listOf("userId", "accessToken", "refreshToken")) {
            assertNull("empty $key", NativeAuthSession.fromSetPayload(payload().put(key, "")))
            assertNull("number $key", NativeAuthSession.fromSetPayload(payload().put(key, 42)))
        }
        assertNull("expiry as string", NativeAuthSession.fromSetPayload(payload().put("expiresAt", "1900000000")))
        assertNull("zero expiry", NativeAuthSession.fromSetPayload(payload().put("expiresAt", 0)))
        assertNull("negative expiry", NativeAuthSession.fromSetPayload(payload().put("expiresAt", -5)))
    }

    @Test fun toStringNeverContainsATokenAndJsonRoundTrips() {
        val s = NativeAuthSession.fromSetPayload(payload())!!
        assertFalse(s.toString().contains("secret"))
        assertTrue(s.toString().contains("user-a"))
        assertEquals(s, NativeAuthSession.fromJson(s.toJson()))
    }
}

class SessionStoreTest {
    private val dir = Fixtures.tempDir()
    private val file = File(dir, "honoured/session.bin")
    private val cipher = FakeCipher()

    @Test fun savesLoadsAndClears() {
        val store = SessionStore(file, cipher)
        assertNull(store.load())
        store.save(Fixtures.session())
        assertEquals(Fixtures.session(), store.load())
        assertEquals("a new instance reads the file", Fixtures.session(), SessionStore(file, cipher).load())
        assertFalse("never stored in clear text", String(file.readBytes()).contains("refresh-1"))
        store.clear()
        assertNull(store.load())
        assertFalse(file.exists())
        assertNull(SessionStore(file, cipher).load())
    }

    @Test fun anUnreadableFileIsNoSessionAndIsRemoved() {
        SessionStore(file, cipher).save(Fixtures.session())
        cipher.broken = true
        val store = SessionStore(file, cipher)
        assertNull(store.load())
        assertTrue(store.lastReadWasUnreadable)
        assertFalse(file.exists())
        assertEquals("the key is reset so the old blob can never be read", 1, cipher.resets)
        cipher.broken = false
        store.save(Fixtures.session(refresh = "refresh-2"))
        assertEquals("refresh-2", SessionStore(file, cipher).load()!!.refreshToken)
    }

    @Test fun aCorruptFileIsNoSession() {
        file.parentFile!!.mkdirs()
        file.writeBytes(byteArrayOf(1, 2, 3, 4))
        assertNull(SessionStore(file, cipher).load())
        assertFalse(file.exists())
    }

    @Test fun replaceIfOnlyReplacesTheExpectedSession() {
        val store = SessionStore(file, cipher)
        val a1 = Fixtures.session(refresh = "r1")
        store.save(a1)
        assertTrue(store.replaceIf(a1, Fixtures.session(refresh = "r2")))
        assertEquals("r2", store.load()!!.refreshToken)
        assertFalse("stale expectation", store.replaceIf(a1, Fixtures.session(refresh = "r3")))
        assertFalse("another user", store.replaceIf(Fixtures.session(user = "user-b", refresh = "r2"), Fixtures.session(refresh = "r4")))
        store.clear()
        assertFalse("signed out meanwhile", store.replaceIf(Fixtures.session(refresh = "r2"), Fixtures.session(refresh = "r5")))
        assertNull(store.load())
    }
}

class RefreshResponseTest {
    private val current = Fixtures.session()

    @Test fun parsesSupabaseResponse() {
        val r = RefreshResponse.parse(current, 200, Fixtures.response("user-a", "a2", "r2").toString(), 100.0)
        assertEquals(NativeAuthSession("user-a", "a2", "r2", 2_000_003_600.0), r.session)
        assertEquals("a2", r.response.getString("access_token"))
    }

    @Test fun fallsBackToExpiresIn() {
        val body = Fixtures.response("user-a", "a2", "r2").apply { remove("expires_at") }.toString()
        assertEquals(3700.0, RefreshResponse.parse(current, 200, body, 100.0).session.expiresAt, 0.0)
    }

    @Test fun classifiesFailures() {
        fun code(status: Int, body: String): String = try {
            RefreshResponse.parse(current, status, body, 0.0); "ok"
        } catch (e: RefreshError) {
            e::class.simpleName!!
        }
        assertEquals("InvalidSession", code(400, "{}"))
        assertEquals("InvalidSession", code(401, "{}"))
        assertEquals("Http", code(500, "{}"))
        assertEquals("Http", code(429, "{}"))
        assertEquals("InvalidResponse", code(200, "not json"))
        assertEquals("InvalidResponse", code(200, Fixtures.response("user-a", "", "r2").toString()))
        assertEquals("another user's session is never adopted", "InvalidSession", code(200, Fixtures.response("user-b", "a2", "r2").toString()))
        assertNotNull(RefreshResponse.parse(current, 201, Fixtures.response("user-a", "a2", "r2").toString(), 0.0))
    }
}
