package com.honoured.app.permissions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import com.honoured.app.permissions.PermissionGate.Outcome

class PermissionGateTest {
    private val mic = "android.permission.RECORD_AUDIO"
    private val granted = mutableSetOf<String>()
    private val rationale = mutableSetOf<String>()
    private val requested = mutableSetOf<String>()
    private val launched = mutableListOf<String>()
    private var launchThrows = false

    private val gate = PermissionGate(
        isGranted = { it in granted },
        shouldShowRationale = { it in rationale },
        wasRequested = { it in requested },
        markRequested = { requested += it },
        launch = {
            if (launchThrows) throw IllegalStateException("no activity")
            launched += it
        },
    )

    @Test
    fun grantedAnswersAtOnceWithoutAPrompt() {
        granted += mic
        val results = mutableListOf<Outcome>()
        gate.request(mic) { results += it }
        assertEquals(listOf(Outcome.GRANTED), results)
        assertTrue(launched.isEmpty())
        assertEquals(PermissionGate.Status.GRANTED, gate.status(mic))
    }

    @Test
    fun oneSystemPromptAtATime() {
        val first = mutableListOf<Outcome>()
        val second = mutableListOf<Outcome>()
        gate.request(mic) { first += it }
        gate.request("android.permission.POST_NOTIFICATIONS") { second += it }
        assertEquals(listOf(mic), launched)
        // Busy, not refused: the caller must not read it as "blocked".
        assertEquals(listOf(Outcome.BUSY), second)
        assertTrue(first.isEmpty())
        assertTrue(gate.isPrompting)

        gate.onSystemResult(true)
        assertEquals(listOf(Outcome.GRANTED), first)
        assertFalse(gate.isPrompting)
        // A late or duplicate system answer reaches nobody.
        gate.onSystemResult(false)
        assertEquals(listOf(Outcome.GRANTED), first)
    }

    @Test
    fun blockedOnlyAfterARefusalWithoutRationale() {
        assertEquals(PermissionGate.Status.CAN_ASK, gate.status(mic))
        gate.request(mic) {}
        gate.onSystemResult(false)
        rationale += mic // first refusal: Android would explain next time
        assertEquals(PermissionGate.Status.CAN_ASK, gate.status(mic))
        rationale -= mic // "Don't ask again"
        assertEquals(PermissionGate.Status.BLOCKED, gate.status(mic))
        // Still asks: Android answers false at once without UI when blocked.
        val again = mutableListOf<Outcome>()
        gate.request(mic) { again += it }
        assertEquals(2, launched.size)
    }

    @Test
    fun aLaunchFailureAnswersFalseAndFreesTheGate() {
        launchThrows = true
        val results = mutableListOf<Outcome>()
        gate.request(mic) { results += it }
        assertEquals(listOf(Outcome.DENIED), results)
        assertFalse(gate.isPrompting)
    }

    @Test
    fun cancelAnswersThePendingCallerOnce() {
        val results = mutableListOf<Outcome>()
        gate.request(mic) { results += it }
        gate.cancel()
        gate.cancel()
        assertEquals(listOf(Outcome.DENIED), results)
    }
}
