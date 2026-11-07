package com.honoured.app.session

import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class SessionMessageHandlerTest {
    private val cipher = FakeCipher()
    private val storeFile = File(Fixtures.tempDir(), "session.bin")
    private val store = SessionStore(storeFile, cipher)
    private val replies = mutableListOf<Pair<String, JSONObject>>()
    private val owners = mutableListOf<String?>()
    private val log = mutableListOf<String>()
    private val reply: (String, JSONObject) -> Unit = { t, p -> replies += t to p }

    private fun TestScope.handler(transport: RefreshTransport = RefreshTransport { current ->
        RefreshResponse.parse(current, 200, Fixtures.response(current.userId, "a-new", "r-new").toString(), 0.0)
    }): SessionMessageHandler {
        val registry = AccountScopedRegistry().apply {
            // Records which account's session was still stored when the clear ran.
            register("probe") { log += "clear(stored=${store.load()?.userId})" }
        }
        return SessionMessageHandler(
            store = store,
            refresher = SessionRefresher(store, transport, supervised()),
            mutations = SerialMutationQueue(backgroundScope),
            registry = registry,
            scope = supervised(),
            onOwnerChanged = { owners += it },
        )
    }

    private fun set(user: String, refresh: String = "r-$user") = JSONObject()
        .put("requestId", "set-$user")
        .put("userId", user)
        .put("accessToken", "a-$user")
        .put("refreshToken", refresh)
        .put("expiresAt", 2_000_000_000)

    private fun JSONObject.hasToken() = toString().let { it.contains("a-user") || it.contains("r-user") || it.contains("accessToken") }

    @Test fun setStoresTheSessionAndAcceptsWithoutEchoingTokens() = runTest {
        val h = handler()
        h.handle("SET_AUTH_SESSION", set("user-a"), reply)
        assertEquals("owner change is synchronous", listOf<String?>("user-a"), owners)
        settle()
        assertEquals("AUTH_SESSION_ACCEPTED", replies.single().first)
        assertEquals("user-a", replies.single().second.getString("userId"))
        assertFalse(replies.single().second.hasToken())
        assertEquals("r-user-a", store.load()!!.refreshToken)
        assertTrue("first sign-in clears nothing", log.isEmpty())
    }

    @Test fun anInvalidSetIsRefusedAndChangesNothing() = runTest {
        val h = handler()
        h.handle("SET_AUTH_SESSION", set("user-a").put("expiresAt", 0), reply)
        settle()
        assertEquals("ERROR", replies.single().first)
        assertEquals("invalid_auth_session", replies.single().second.getString("code"))
        assertFalse(replies.single().second.hasToken())
        assertTrue(owners.isEmpty())
        assertNull(store.load())
    }

    @Test fun aTokenRefreshForTheSamePersonClearsNothing() = runTest {
        val h = handler()
        h.handle("SET_AUTH_SESSION", set("user-a", "r1"), reply)
        h.handle("SET_AUTH_SESSION", set("user-a", "r2"), reply)
        settle()
        assertTrue(log.isEmpty())
        assertEquals("r2", store.load()!!.refreshToken)
    }

    @Test fun anotherPersonClearsThePreviousAccountBeforeTheNewSessionIsStored() = runTest {
        val h = handler()
        h.handle("SET_AUTH_SESSION", set("user-a"), reply)
        h.handle("SET_AUTH_SESSION", set("user-b"), reply)
        settle()
        assertEquals(listOf("clear(stored=user-a)"), log)
        assertEquals("user-b", store.load()!!.userId)
        assertEquals(listOf<String?>("user-a", "user-b"), owners)
    }

    @Test fun aStaleSessionForTheSamePersonNeverReplacesALaterOne() = runTest {
        val h = handler()
        // Native refreshed (r-later, later expiry) but the reply never reached the
        // page, which reloads and hands over its older session again.
        h.handle("SET_AUTH_SESSION", set("user-a", "r-later").put("expiresAt", 2_000_003_600), reply)
        h.handle("SET_AUTH_SESSION", set("user-a", "r-earlier").put("expiresAt", 2_000_000_000), reply)
        settle()
        assertEquals("r-later", store.load()!!.refreshToken)
        assertEquals(listOf("AUTH_SESSION_ACCEPTED", "AUTH_SESSION_ACCEPTED"), replies.map { it.first })
        // A genuinely newer session (later expiry) is stored.
        h.handle("SET_AUTH_SESSION", set("user-a", "r-newest").put("expiresAt", 2_000_007_200), reply)
        settle()
        assertEquals("r-newest", store.load()!!.refreshToken)
        assertTrue(log.isEmpty())
    }

    @Test fun aFailedSaveWhileSwitchingLeavesNoPreviousSessionBehind() = runTest {
        val h = handler()
        h.handle("SET_AUTH_SESSION", set("user-a"), reply)
        settle()
        cipher.failEncrypt = true
        h.handle("SET_AUTH_SESSION", set("user-b"), reply)
        settle()
        assertEquals("ERROR", replies.last().first)
        assertNull("user-a's session must not survive a failed switch", store.load())
        assertEquals(listOf("clear(stored=user-a)"), log)
    }

    @Test fun anUnreadableStoredSessionClearsAccountStateFirst() = runTest {
        storeFile.writeBytes(byteArrayOf(1, 2, 3)) // corrupt: the previous owner is unknown
        val h = handler()
        h.handle("SET_AUTH_SESSION", set("user-b"), reply)
        settle()
        assertEquals(listOf("clear(stored=null)"), log)
        assertEquals("user-b", store.load()!!.userId)
    }

    @Test fun clearWipesTheSessionAndAccountState() = runTest {
        val h = handler()
        h.handle("SET_AUTH_SESSION", set("user-a"), reply)
        h.handle("CLEAR_AUTH_SESSION", JSONObject().put("requestId", "c1"), reply)
        settle()
        assertNull(store.load())
        assertEquals(listOf("clear(stored=null)"), log)
        assertEquals(listOf("AUTH_SESSION_ACCEPTED", "AUTH_SESSION_CLEARED"), replies.map { it.first })
        assertEquals(listOf<String?>("user-a", null), owners)
    }

    @Test fun signInSignOutSignInRunInOrder() = runTest {
        val h = handler()
        h.handle("SET_AUTH_SESSION", set("user-a"), reply)
        h.handle("CLEAR_AUTH_SESSION", JSONObject(), reply)
        h.handle("SET_AUTH_SESSION", set("user-b"), reply)
        settle()
        assertEquals(listOf("AUTH_SESSION_ACCEPTED", "AUTH_SESSION_CLEARED", "AUTH_SESSION_ACCEPTED"), replies.map { it.first })
        assertEquals("user-b", store.load()!!.userId)
    }

    @Test fun refreshValidatesThenDeclinesOrRefreshes() = runTest {
        val h = handler()
        h.handle("REFRESH_AUTH_SESSION", JSONObject().put("requestId", "x"), reply)
        h.handle("REFRESH_AUTH_SESSION", JSONObject().put("userId", "user-a"), reply)
        settle()
        assertEquals("invalid_refresh_request", replies[0].second.getString("code"))
        assertEquals("AUTH_REFRESH_DECLINED", replies[1].first)
        assertEquals("no_session", replies[1].second.getString("reason"))

        replies.clear()
        h.handle("SET_AUTH_SESSION", set("user-a"), reply)
        settle()
        h.handle("REFRESH_AUTH_SESSION", JSONObject().put("userId", "user-a"), reply)
        settle()
        val (type, payload) = replies.last()
        assertEquals("AUTH_SESSION_REFRESHED", type)
        assertEquals("r-new", payload.getJSONObject("session").getString("refresh_token"))
        assertEquals("r-new", store.load()!!.refreshToken)
    }

    @Test fun anOfflineRefreshIsARetryableErrorWithoutTokens() = runTest {
        val h = handler(RefreshTransport { throw java.io.IOException("offline") })
        h.handle("SET_AUTH_SESSION", set("user-a"), reply)
        settle()
        h.handle("REFRESH_AUTH_SESSION", JSONObject().put("userId", "user-a"), reply)
        settle()
        assertEquals("ERROR", replies.last().first)
        assertEquals("auth_refresh_failed", replies.last().second.getString("code"))
        assertFalse(replies.last().second.hasToken())
    }

    @Test fun unknownTypesAreRefused() = runTest {
        handler().handle("SOMETHING", JSONObject(), reply)
        assertEquals("unsupported_message", replies.single().second.getString("code"))
    }
}
