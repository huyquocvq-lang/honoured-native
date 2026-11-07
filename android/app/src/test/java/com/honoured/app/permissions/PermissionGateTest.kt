package com.honoured.app.permissions

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

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
        val results = mutableListOf<Boolean>()
        gate.request(mic) { results += it }
        assertEquals(listOf(true), results)
        assertTrue(launched.isEmpty())
        assertEquals(PermissionGate.Status.GRANTED, gate.status(mic))
    }

    @Test
    fun oneSystemPromptAtATime() {
        val first = mutableListOf<Boolean>()
        val second = mutableListOf<Boolean>()
        gate.request(mic) { first += it }
        gate.request("android.permission.POST_NOTIFICATIONS") { second += it }
        assertEquals(listOf(mic), launched)
        assertEquals(listOf(false), second)
        assertTrue(first.isEmpty())
        assertTrue(gate.isPrompting)

        gate.onSystemResult(true)
        assertEquals(listOf(true), first)
        assertFalse(gate.isPrompting)
        // A late or duplicate system answer reaches nobody.
        gate.onSystemResult(false)
        assertEquals(listOf(true), first)
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
        val again = mutableListOf<Boolean>()
        gate.request(mic) { again += it }
        assertEquals(2, launched.size)
    }

    @Test
    fun aLaunchFailureAnswersFalseAndFreesTheGate() {
        launchThrows = true
        val results = mutableListOf<Boolean>()
        gate.request(mic) { results += it }
        assertEquals(listOf(false), results)
        assertFalse(gate.isPrompting)
    }

    @Test
    fun cancelAnswersThePendingCallerOnce() {
        val results = mutableListOf<Boolean>()
        gate.request(mic) { results += it }
        gate.cancel()
        gate.cancel()
        assertEquals(listOf(false), results)
    }
}
