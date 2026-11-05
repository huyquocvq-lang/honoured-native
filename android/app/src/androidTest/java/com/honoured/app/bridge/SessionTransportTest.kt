package com.honoured.app.bridge

import android.webkit.WebView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.honoured.app.MainActivity
import com.honoured.app.R
import com.honoured.app.session.SessionServices
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The real shell, the real WebView, the configured web app (network needed):
 * token-carrying messages are refused on the legacy `HonouredNative`
 * interface and handled only on the origin-scoped `HonouredAuth` transport.
 * Uses a made-up session; the refresh goes to the real Supabase with a bogus
 * token, which must come back as a decline and never as a stored session.
 */
@RunWith(AndroidJUnit4::class)
class SessionTransportTest {
    private lateinit var scenario: ActivityScenario<MainActivity>
    private val services = SessionServices.get(InstrumentationRegistry.getInstrumentation().targetContext)

    @Before fun setUp() {
        services.store.clear()
        scenario = ActivityScenario.launch(MainActivity::class.java)
        // The page has loaded and the bridge objects are injected.
        waitFor(60) { jsString("String(document.readyState === 'complete' && typeof HonouredAuth === 'object' && typeof HonouredNative === 'object')") == "true" }
        js(
            """
            (function(){
              window.__legacy = []; window.__trusted = [];
              window.addEventListener('honoured:native', function(e){ window.__legacy.push(JSON.stringify(e.detail)); });
              HonouredAuth.addEventListener('message', function(e){ window.__trusted.push(e.data); });
              return 'ok';
            })()
            """.trimIndent(),
        )
    }

    @After fun tearDown() {
        services.store.clear()
        scenario.close()
    }

    @Test fun capabilitiesAdvertiseTheSessionHandOff() {
        post("HonouredNative", "GET_PLATFORM_INFO", JSONObject().put("requestId", "p1"))
        val info = waitForReply("legacy", "PLATFORM_INFO")
        val caps = info.getJSONObject("payload").getJSONObject("capabilities")
        assertTrue(caps.getJSONObject("sessionRefresh").getBoolean("supported"))
        assertEquals("trusted-auth-v1", caps.getJSONObject("sessionRefresh").getString("transport"))
        assertTrue(caps.getJSONObject("iconRevisions").getBoolean("supported"))
    }

    @Test fun theLegacyInterfaceRefusesTokensAndStoresNothing() {
        post("HonouredNative", "SET_AUTH_SESSION", session("legacy-1"))
        val reply = waitForReply("legacy", "ERROR")
        assertEquals("insecure_transport", reply.getJSONObject("payload").getString("code"))
        assertEquals("legacy-1", reply.getJSONObject("payload").getString("requestId"))
        assertTrue("no token echoed", !reply.toString().contains("test-refresh"))
        Thread.sleep(500)
        assertNull(services.store.load())
        post("HonouredNative", "REFRESH_AUTH_SESSION", JSONObject().put("requestId", "legacy-2").put("userId", "android-test-user"))
        assertEquals("insecure_transport", waitForReply("legacy", "ERROR", "legacy-2").getJSONObject("payload").getString("code"))
    }

    @Test fun theTrustedTransportStoresRefreshesAndClears() {
        post("HonouredAuth", "SET_AUTH_SESSION", session("t-1"))
        val accepted = waitForReply("trusted", "AUTH_SESSION_ACCEPTED", "t-1")
        assertEquals("android-test-user", accepted.getJSONObject("payload").getString("userId"))
        assertTrue("no token echoed", !accepted.toString().contains("test-refresh"))
        assertNotNull(services.store.load())

        post("HonouredAuth", "REFRESH_AUTH_SESSION", JSONObject().put("requestId", "t-2").put("userId", "someone-else"))
        assertEquals("other_user", waitForReply("trusted", "AUTH_REFRESH_DECLINED", "t-2").getJSONObject("payload").getString("reason"))

        // Real Supabase, bogus token: the grant is refused and nothing is adopted.
        post("HonouredAuth", "REFRESH_AUTH_SESSION", JSONObject().put("requestId", "t-3").put("userId", "android-test-user"))
        val refreshed = waitForReply("trusted", "AUTH_REFRESH_DECLINED", "t-3", timeoutSeconds = 30)
        assertEquals("invalid_session", refreshed.getJSONObject("payload").getString("reason"))
        assertEquals("test-refresh", services.store.load()!!.refreshToken)

        post("HonouredAuth", "CLEAR_AUTH_SESSION", JSONObject().put("requestId", "t-4"))
        waitForReply("trusted", "AUTH_SESSION_CLEARED", "t-4")
        assertNull(services.store.load())
    }

    // ---- helpers ----

    private fun session(requestId: String) = JSONObject()
        .put("requestId", requestId)
        .put("userId", "android-test-user")
        .put("accessToken", "test-access")
        .put("refreshToken", "test-refresh")
        .put("expiresAt", 2_000_000_000)

    private fun post(channel: String, type: String, payload: JSONObject) {
        val envelope = JSONObject().put("bridgeVersion", 1).put("type", type).put("payload", payload).toString()
        js("$channel.postMessage(${JSONObject.quote(envelope)}); 'ok'")
    }

    private fun waitForReply(channel: String, type: String, requestId: String? = null, timeoutSeconds: Long = 15): JSONObject {
        val list = if (channel == "legacy") "__legacy" else "__trusted"
        var found: JSONObject? = null
        waitFor(timeoutSeconds) {
            val raw = JSONArray(jsString("JSON.stringify(window.$list || [])"))
            found = (0 until raw.length()).map { JSONObject(raw.getString(it)) }.firstOrNull {
                it.optString("type") == type && (requestId == null || it.optJSONObject("payload")?.optString("requestId") == requestId)
            }
            found != null
        }
        return found!!
    }

    /** Evaluates [script] on the main thread; returns the raw JSON-encoded result. */
    private fun js(script: String): String {
        val latch = CountDownLatch(1)
        var result = "null"
        scenario.onActivity { activity ->
            activity.findViewById<WebView>(R.id.webView).evaluateJavascript(script) { value ->
                result = value ?: "null"
                latch.countDown()
            }
        }
        latch.await(10, TimeUnit.SECONDS)
        return result
    }

    /** [js] for a script that returns a string. */
    private fun jsString(script: String): String {
        val raw = js(script)
        return if (raw == "null") "null" else JSONArray("[$raw]").getString(0)
    }

    private fun waitFor(seconds: Long, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + seconds * 1000
        while (System.currentTimeMillis() < deadline) {
            if (runCatching(condition).getOrDefault(false)) return
            Thread.sleep(250)
        }
        throw AssertionError("Timed out after ${seconds}s")
    }
}
