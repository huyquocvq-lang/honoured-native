package com.honoured.app.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class GoogleAuthStateTest {
    private var counter = 0
    private fun state() = GoogleAuthState { "ctx-${++counter}" }

    private fun GoogleAuthState.start(requestId: String?, intent: String?, context: String?) =
        begin(requestId, intent, context, "raw")

    private fun BeginResult.code() = (this as? BeginResult.Rejected)?.failure?.code
    private fun BeginResult.attempt() = (this as BeginResult.Started).attempt

    @Test fun syncIsIdempotentForTheSameUserAndPage() {
        val s = state()
        val a = s.sync(null)
        assertEquals(a, s.sync(null))
        assertEquals("an empty user id means signed out", a, s.sync(""))
        val b = s.sync("user-a")
        assertNotEquals(a.id, b.id)
        assertEquals(b, s.sync("user-a"))
    }

    @Test fun requiresAContextFromThisPage() {
        val s = state()
        assertEquals("stale_context", s.start("r1", "sign_in", "ctx-x").code())
        val context = s.sync(null)
        s.documentWillChange()
        assertEquals("stale_context", s.start("r1", "sign_in", context.id).code())
        assertNull(s.context)
    }

    @Test fun validatesPayloadAndIntentAgainstTheContext() {
        val s = state()
        val out = s.sync(null)
        assertEquals("invalid_payload", s.start(null, "sign_in", out.id).code())
        assertEquals("invalid_payload", s.start("r1", "bogus", out.id).code())
        assertEquals("invalid_payload", s.start("r1", "sign_in", null).code())
        assertEquals("invalid_payload", s.start("r1", "link", out.id).code())
        val signedIn = s.sync("user-a")
        assertEquals("invalid_payload", s.start("r2", "sign_in", signedIn.id).code())
        assertTrue(s.start("r3", "link", signedIn.id) is BeginResult.Started)
    }

    @Test fun oneAttemptAtATimeAndOneResultPerRequest() {
        val s = state()
        val context = s.sync(null)
        val attempt = s.start("r1", "sign_in", context.id).attempt()
        assertEquals("in_progress", s.start("r2", "sign_in", context.id).code())
        assertEquals(attempt, s.finish(attempt))
        assertNull("a second callback is dropped", s.finish(attempt))
        assertEquals("a used requestId is never served again", "invalid_payload", s.start("r1", "sign_in", context.id).code())
        assertTrue(s.start("r2", "sign_in", context.id) is BeginResult.Started)
    }

    @Test fun reloadAndClearInvalidateAnAttempt() {
        val s = state()
        var context = s.sync(null)
        var attempt = s.start("r1", "sign_in", context.id).attempt()
        s.documentWillChange()
        assertFalse(s.isCurrent(attempt))
        assertNull(s.finish(attempt))

        context = s.sync("user-a")
        attempt = s.start("r2", "link", context.id).attempt()
        assertEquals("same owner resync keeps the attempt", context, s.sync("user-a"))
        assertTrue(s.isCurrent(attempt))
        s.sync("user-b")
        assertNull("owner change drops it", s.finish(attempt))

        context = s.sync(null)
        attempt = s.start("r3", "sign_in", context.id).attempt()
        val fresh = s.clear()
        assertNotEquals(context.id, fresh.id)
        assertNull(fresh.userId)
        assertNull(s.finish(attempt))
        assertEquals("stale_context", s.start("r4", "sign_in", context.id).code())
    }

    @Test fun cancelOnlyMatchesTheCurrentAttempt() {
        val s = state()
        val context = s.sync(null)
        val attempt = s.start("r1", "sign_in", context.id).attempt()
        assertNull(s.cancel("other", "r1"))
        assertNull(s.cancel(context.id, "r9"))
        assertEquals(attempt, s.cancel(context.id, "r1"))
        assertNull("the result after a cancel is dropped", s.finish(attempt))
        assertNull(s.cancel(context.id, "r1"))
    }
}

class AuthSupportTest {
    @Test fun presentationGateIsExclusiveAndIgnoresStaleReleases() {
        val gate = ProviderPresentationGate()
        val first = gate.acquire(ProviderPresentationGate.Holder.GOOGLE)
        assertNotNull(first)
        assertNull(gate.acquire(ProviderPresentationGate.Holder.GOOGLE_CLEANUP))
        gate.release(first!!)
        val cleanup = gate.acquire(ProviderPresentationGate.Holder.GOOGLE_CLEANUP)
        gate.release(first)
        assertEquals(ProviderPresentationGate.Holder.GOOGLE_CLEANUP, gate.holder)
        gate.release(cleanup!!)
        assertNull(gate.holder)
    }

    @Test fun nonceIsRandomHexAndHashedWithSha256() {
        val (raw, hashed) = AuthNonce.make()
        val (other, _) = AuthNonce.make()
        assertEquals(64, raw.length)
        assertTrue(raw.all { it in '0'..'9' || it in 'a'..'f' })
        assertNotEquals(raw, other)
        assertEquals(AuthNonce.sha256Hex(raw), hashed)
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", AuthNonce.sha256Hex("abc"))
    }

    @Test fun trustedOriginIsExact() {
        val origin = TrustedWebOrigin.from("https://honour-your-word.lovable.app/path?q=1")!!
        assertEquals("https://honour-your-word.lovable.app", origin.listenerRule)
        assertTrue(origin.matches("https", "honour-your-word.lovable.app", -1))
        assertTrue(origin.matches("HTTPS", "Honour-Your-Word.lovable.app", 443))
        assertTrue(origin.matches("https://honour-your-word.lovable.app/settings"))
        assertFalse(origin.matches("http", "honour-your-word.lovable.app", -1))
        assertFalse(origin.matches("https", "evil.honour-your-word.lovable.app", -1))
        assertFalse(origin.matches("https", "honour-your-word.lovable.app.evil.com", -1))
        assertFalse(origin.matches("https", "honour-your-word.lovable.app", 8443))
        assertFalse(origin.matches(null, null, -1))
        assertFalse(origin.matches(null as String?))
        assertNull("only HTTPS can be trusted", TrustedWebOrigin.from("http://honour-your-word.lovable.app"))
        assertEquals("https://example.test:8443", TrustedWebOrigin.from("https://example.test:8443/")!!.listenerRule)
    }

    @Test fun serverClientIdMustBeAGoogleClientId() {
        assertEquals("123-web.apps.googleusercontent.com", GoogleClientConfig.serverClientId(" 123-web.apps.googleusercontent.com "))
        assertNull(GoogleClientConfig.serverClientId(""))
        assertNull(GoogleClientConfig.serverClientId(".apps.googleusercontent.com"))
        assertNull(GoogleClientConfig.serverClientId("123 web.apps.googleusercontent.com"))
        assertNull(GoogleClientConfig.serverClientId("not-a-client-id"))
    }

    @Test fun serialQueueRunsInSubmissionOrderEvenWhenEarlierWorkIsSlower() {
        val queue = SerialCallbackQueue()
        val log = java.util.Collections.synchronizedList(mutableListOf<String>())
        val latch = CountDownLatch(3)
        queue.enqueue { done ->
            Thread {
                Thread.sleep(150)
                log += "logout A"
                latch.countDown()
                done()
            }.start()
        }
        queue.enqueue { done ->
            log += "identify B"
            latch.countDown()
            done()
            done() // a second done() must not run the next operation twice
        }
        queue.enqueue { done ->
            log += "check B"
            latch.countDown()
            done()
        }
        assertTrue(latch.await(2, TimeUnit.SECONDS))
        assertEquals(listOf("logout A", "identify B", "check B"), log.toList())
    }
}
