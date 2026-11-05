package com.honoured.app.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SessionOwnerChangedTest {
    private var counter = 0
    private fun state() = GoogleAuthState { "ctx-${++counter}" }
    private fun BeginResult.code() = (this as? BeginResult.Rejected)?.failure?.code

    @Test fun aTokenRefreshForTheSamePersonKeepsALinkFlowAlive() {
        val s = state()
        val ctx = s.sync("user-a")
        val attempt = (s.begin("r1", "link", ctx.id, "raw") as BeginResult.Started).attempt
        s.sessionOwnerChanged("user-a")
        assertEquals(ctx, s.context)
        assertEquals(attempt, s.finish(attempt))
    }

    @Test fun anotherOwnerOrSignOutVoidsTheContextAndItsAttempt() {
        for (next in listOf("user-b", null)) {
            val s = state()
            val ctx = s.sync("user-a")
            val attempt = (s.begin("r1", "link", ctx.id, "raw") as BeginResult.Started).attempt
            s.sessionOwnerChanged(next)
            assertNull(s.context)
            assertNull("a late Google result is dropped", s.finish(attempt))
            assertEquals("stale_context", s.begin("r2", "link", ctx.id, "raw").code())
        }
    }

    @Test fun withoutAContextNothingHappens() {
        val s = state()
        s.sessionOwnerChanged("user-a")
        assertNull(s.context)
        val ctx = s.sync(null)
        s.sessionOwnerChanged(null)
        assertNull("a signed-out context is void after a clear too", s.context)
        assertEquals("stale_context", s.begin("r", "sign_in", ctx.id, "raw").code())
    }
}
