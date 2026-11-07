package com.honoured.app.bridge

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class NativeEventStoreTest {
    private val file = File(Files.createTempDirectory("events").toFile(), "honoured/native-events.json")

    @Test fun secretsAreFoundUnderAnySpellingAndInsideArrays() {
        listOf(
            JSONObject().put("id_token", "x"),
            JSONObject().put("provider_refresh_token", "x"),
            JSONObject().put("Provider-Token", "x"),
            JSONObject().put("items", org.json.JSONArray().put(JSONObject().put("refreshToken", "x"))),
            JSONObject().put("nested", JSONObject().put("list", org.json.JSONArray().put(org.json.JSONArray().put(JSONObject().put("session", "x"))))),
        ).forEach { assertTrue(it.toString(), NativeEventStore.containsSecret(it)) }
        assertFalse(NativeEventStore.containsSecret(JSONObject().put("eventId", "e").put("contractId", "c").put("healthDay", "2026-11-07")))
    }

    @Test fun keepsOnlyDurableTypesAndNeverTokens() {
        val store = NativeEventStore(file)
        assertTrue(runCatching { store.append("ACCESS_STATUS", JSONObject()) }.isFailure)
        assertTrue(runCatching { store.append("NOTIFICATION_OPENED", JSONObject().put("accessToken", "x")) }.isFailure)
        assertTrue(runCatching { store.append("NOTIFICATION_OPENED", JSONObject().put("meta", JSONObject().put("refresh_token", "x"))) }.isFailure)
        assertEquals(0, store.size)
    }

    @Test fun deliversOnceOldestFirstAcrossARelaunch() {
        NativeEventStore(file).apply {
            append("CONTRACT_LINK_OPENED", JSONObject().put("n", 2), createdAt = 2)
            append("NOTIFICATION_OPENED", JSONObject().put("n", 1), createdAt = 1)
        }
        val relaunched = NativeEventStore(file)
        assertEquals(listOf(1, 2), relaunched.drain().map { it.payload.getInt("n") })
        assertTrue(relaunched.drain().isEmpty())
        assertTrue("drained on disk too", NativeEventStore(file).drain().isEmpty())
    }

    @Test fun isBoundedToTheNewest() {
        val store = NativeEventStore(file, limit = 3)
        (1..5).forEach { store.append("NOTIFICATION_OPENED", JSONObject().put("n", it), createdAt = it.toLong()) }
        assertEquals(listOf(3, 4, 5), store.drain().map { it.payload.getInt("n") })
    }

    @Test fun clearAndCorruptFile() {
        val store = NativeEventStore(file)
        store.append("NOTIFICATION_OPENED", JSONObject())
        store.clear()
        assertFalse(file.exists())
        assertTrue(store.drain().isEmpty())
        file.parentFile!!.mkdirs()
        file.writeText("{not json")
        assertTrue(NativeEventStore(file).drain().isEmpty())
    }
}

class BridgeEventQueueTest {
    private val sent = mutableListOf<String>()
    private var stored = mutableListOf<StoredEvent>()
    private fun queue(limit: Int = 50) = BridgeEventQueue(
        dispatch = { type, payload -> sent += "$type:${payload.optString("n")}" },
        drainStored = { stored.toList().also { stored.clear() } },
        limit = limit,
    )

    @Test fun holdsUntilThePageSpeaksThenFlushesMergedByTime() {
        val q = queue()
        q.broadcast("A", JSONObject().put("n", "1"), createdAt = 10)
        q.broadcast("C", JSONObject().put("n", "3"), createdAt = 30)
        stored += StoredEvent("id", "NOTIFICATION_OPENED", JSONObject().put("n", "2"), 20)
        assertTrue(sent.isEmpty())
        q.inboundMessageReceived()
        assertEquals(listOf("A:1", "NOTIFICATION_OPENED:2", "C:3"), sent)
        q.inboundMessageReceived()
        assertEquals("only the first message flushes", 3, sent.size)
        q.broadcast("D", JSONObject().put("n", "4"))
        assertEquals("ready: sent at once", "D:4", sent.last())
    }

    @Test fun aNewPageWaitsAgain() {
        val q = queue()
        q.inboundMessageReceived()
        q.pageWillChange()
        q.broadcast("A", JSONObject().put("n", "1"))
        assertTrue(sent.isEmpty())
        q.inboundMessageReceived()
        assertEquals(listOf("A:1"), sent)
    }

    @Test fun isBoundedAndClearable() {
        val q = queue(limit = 2)
        (1..4).forEach { q.broadcast("E", JSONObject().put("n", "$it"), createdAt = it.toLong()) }
        assertEquals(2, q.pendingCount)
        q.clear()
        q.inboundMessageReceived()
        assertTrue(sent.isEmpty())
        val q2 = queue(limit = 2)
        (1..4).forEach { q2.broadcast("E", JSONObject().put("n", "$it"), createdAt = it.toLong()) }
        q2.inboundMessageReceived()
        assertEquals(listOf("E:3", "E:4"), sent)
    }
}

class CapabilitiesTest {
    @Test fun advertisesTheSessionHandOffAsOneCapability() {
        val google = JSONObject().put("supported", true)
        val on = Capabilities.build(google, sessionRefreshSupported = true)
        assertEquals(google.toString(), on.getJSONObject("googleSignIn").toString())
        val session = on.getJSONObject("sessionRefresh")
        assertEquals(1, session.getInt("protocolVersion"))
        assertTrue(session.getBoolean("supported"))
        assertEquals("trusted-auth-v1", session.getString("transport"))
        assertFalse(Capabilities.build(google, sessionRefreshSupported = false).getJSONObject("sessionRefresh").getBoolean("supported"))
    }

    @Test fun offersIconRevisionsAndListsMissingFeaturesAsUnsupported() {
        val c = Capabilities.build(JSONObject(), false)
        assertTrue(c.getJSONObject("iconRevisions").getBoolean("supported"))
        for (key in listOf("healthConnect", "phoneSteps", "backgroundTracking", "notifications")) {
            assertFalse(key, c.getJSONObject(key).getBoolean("supported"))
            assertEquals(key, 1, c.getJSONObject(key).getInt("protocolVersion"))
        }
        assertFalse("no Live Activities, Word Tracker or web credentials on Android", c.has("liveActivities") || c.has("wordTracker") || c.has("webCredentials"))
    }
}
