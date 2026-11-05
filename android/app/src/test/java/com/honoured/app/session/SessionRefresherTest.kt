package com.honoured.app.session

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.IOException

/**
 * The refresh-token-reuse guard: native refreshes each token once however
 * many callers ask, and never stores a result over a session that changed.
 */
class SessionRefresherTest {
    private val store = SessionStore(File(Fixtures.tempDir(), "session.bin"), FakeCipher())

    /** Records the refresh tokens it was asked to spend; answers when [gate] completes. */
    private inner class FakeTransport : RefreshTransport {
        val spent = mutableListOf<String>()
        var gate = CompletableDeferred<Unit>().apply { complete(Unit) }
        var answer: (NativeAuthSession) -> SessionRefresher.RefreshResult = { current ->
            val n = spent.size
            RefreshResponse.parse(current, 200, Fixtures.response(current.userId, "a$n", "r$n").toString(), 0.0)
        }

        override suspend fun refresh(current: NativeAuthSession): SessionRefresher.RefreshResult {
            spent += current.refreshToken
            gate.await()
            return answer(current)
        }
    }

    @Test fun declinesWithoutASessionOrForAnotherPerson() = runTest {
        val transport = FakeTransport()
        val refresher = SessionRefresher(store, transport, supervised())
        assertEquals(SessionRefresher.WebOutcome.Declined("no_session"), refresher.refreshForWeb("user-a"))
        store.save(Fixtures.session(user = "user-b"))
        assertEquals(SessionRefresher.WebOutcome.Declined("other_user"), refresher.refreshForWeb("user-a"))
        assertTrue("nothing was spent", transport.spent.isEmpty())
    }

    @Test fun fiveConcurrentCallersSpendTheTokenOnce() = runTest {
        store.save(Fixtures.session(refresh = "r-start"))
        val transport = FakeTransport().apply { gate = CompletableDeferred() }
        val refresher = SessionRefresher(store, transport, supervised())
        val calls = (1..5).map { async { refresher.refreshForWeb("user-a") } }
        runCurrent()
        transport.gate.complete(Unit)
        val outcomes = calls.awaitAll()
        assertEquals(listOf("r-start"), transport.spent)
        outcomes.forEach {
            it as SessionRefresher.WebOutcome.Refreshed
            assertEquals("r1", it.response.getString("refresh_token"))
        }
        assertEquals("r1", store.load()!!.refreshToken)
    }

    @Test fun eachRefreshSpendsTheNewestStoredToken() = runTest {
        store.save(Fixtures.session(refresh = "r-start"))
        val transport = FakeTransport()
        val refresher = SessionRefresher(store, transport, supervised())
        refresher.refreshForWeb("user-a")
        refresher.refreshForWeb("user-a")
        refresher.refreshForWeb("user-a")
        assertEquals("never the same token twice", listOf("r-start", "r1", "r2"), transport.spent)
        assertEquals("r3", store.load()!!.refreshToken)
    }

    @Test fun aSessionStoredDuringTheRequestIsNeverOverwritten() = runTest {
        store.save(Fixtures.session(refresh = "r-start"))
        val transport = FakeTransport().apply { gate = CompletableDeferred() }
        val refresher = SessionRefresher(store, transport, supervised())
        val call = async { refresher.refreshForWeb("user-a") }
        runCurrent()
        store.save(Fixtures.session(refresh = "r-newer-sign-in"))
        transport.gate.complete(Unit)
        assertEquals(SessionRefresher.WebOutcome.Declined("superseded"), call.await())
        assertEquals("r-newer-sign-in", store.load()!!.refreshToken)
    }

    @Test fun aSignOutOrAccountSwitchDuringTheRequestWins() = runTest {
        store.save(Fixtures.session(refresh = "r-start"))
        val transport = FakeTransport().apply { gate = CompletableDeferred() }
        val refresher = SessionRefresher(store, transport, supervised())
        val call = async { refresher.refreshForWeb("user-a") }
        runCurrent()
        store.clear()
        transport.gate.complete(Unit)
        assertEquals(SessionRefresher.WebOutcome.Declined("superseded"), call.await())
        assertEquals(null, store.load())

        store.save(Fixtures.session(refresh = "r-a"))
        transport.gate = CompletableDeferred()
        val second = async { refresher.refreshForWeb("user-a") }
        runCurrent()
        store.save(Fixtures.session(user = "user-b", refresh = "r-b"))
        transport.gate.complete(Unit)
        assertEquals(SessionRefresher.WebOutcome.Declined("superseded"), second.await())
        assertEquals("user-b", store.load()!!.userId)
    }

    @Test fun mapsFailuresWithoutEverReplayingTheToken() = runTest {
        store.save(Fixtures.session(refresh = "r-start"))
        val transport = FakeTransport()
        val refresher = SessionRefresher(store, transport, supervised())

        transport.answer = { throw RefreshError.InvalidSession() }
        assertEquals(SessionRefresher.WebOutcome.Declined("invalid_session"), refresher.refreshForWeb("user-a"))
        transport.answer = { throw RefreshError.NotConfigured() }
        assertEquals(SessionRefresher.WebOutcome.Declined("not_configured"), refresher.refreshForWeb("user-a"))
        transport.answer = { throw IOException("offline") }
        assertEquals(SessionRefresher.WebOutcome.Failed, refresher.refreshForWeb("user-a"))
        transport.answer = { throw RefreshError.Http(503) }
        assertEquals(SessionRefresher.WebOutcome.Failed, refresher.refreshForWeb("user-a"))
        assertEquals("a failed refresh keeps the stored session", "r-start", store.load()!!.refreshToken)
    }

    @Test fun refreshedSessionIfNeededOnlyRefreshesNearExpiry() = runTest {
        store.save(Fixtures.session(refresh = "r-start", expiresAt = 1_000.0))
        val transport = FakeTransport()
        val refresher = SessionRefresher(store, transport, supervised())
        assertEquals("r-start", refresher.refreshedSessionIfNeeded(nowSeconds = 500.0)!!.refreshToken)
        assertTrue(transport.spent.isEmpty())
        assertEquals("r1", refresher.refreshedSessionIfNeeded(nowSeconds = 950.0)!!.refreshToken)
        assertEquals(listOf("r-start"), transport.spent)
    }
}
