package com.honoured.app

import android.content.Intent
import android.net.Uri
import android.webkit.WebView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.honoured.app.session.SessionServices
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Shell lifecycle on the real WebView with the configured web app (network
 * needed): contract deep links on a cold and a warm start, renderer loss,
 * recreation without trusting saved WebView state, and system-bar insets.
 * A document-start script records every `honoured:native` event, so even the
 * events flushed on the page's first message are observed.
 */
@RunWith(AndroidJUnit4::class)
class ShellLifecycleTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val services = SessionServices.get(context)
    private var scenario: ActivityScenario<MainActivity>? = null

    @Before fun setUp() {
        assumeTrue(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT))
        services.events.clear()
        MainActivity.webViewCreatedHook = { view ->
            WebViewCompat.addDocumentStartJavaScript(
                view,
                "window.__events=[];window.addEventListener('honoured:native',function(e){window.__events.push(JSON.stringify(e.detail));});",
                setOf("*"),
            )
        }
    }

    @After fun tearDown() {
        scenario?.close()
        MainActivity.webViewCreatedHook = null
        services.events.clear()
    }

    private fun linkIntent(link: String) = Intent(Intent.ACTION_VIEW, Uri.parse(link))
        .setClass(context, MainActivity::class.java)

    @Test fun aColdStartLinkIsDeliveredOnceAfterThePageSpeaks() {
        scenario = ActivityScenario.launch(linkIntent("honoured://contract/cold-contract?day=2026-11-05"))
        waitForPage()
        val links = waitForEvents("CONTRACT_LINK_OPENED", 1)
        val payload = links.single().getJSONObject("payload")
        assertEquals("cold-contract", payload.getString("contractId"))
        assertEquals("2026-11-05", payload.getString("healthDay"))
        assertTrue(payload.getString("eventId").isNotBlank())
        assertEquals(setOf("eventId", "contractId", "healthDay"), payload.keys().asSequence().toSet())
        assertEquals("delivered from the durable store", 0, services.events.size)
    }

    @Test fun aWarmLinkArrivesThroughOnNewIntent() {
        scenario = ActivityScenario.launch(MainActivity::class.java)
        waitForPage()
        val generation = onActivity { it.webViewGeneration }
        context.startActivity(linkIntent("honoured://contract/warm%20id").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val payload = waitForEvents("CONTRACT_LINK_OPENED", 1).single().getJSONObject("payload")
        assertEquals("warm id", payload.getString("contractId"))
        assertFalse(payload.has("healthDay"))
        // singleTask: the same activity and page took it.
        assertEquals(generation, onActivity { it.webViewGeneration })
    }

    @Test fun aMalformedLinkIsDroppedWithoutCrashing() {
        scenario = ActivityScenario.launch(linkIntent("honoured://contract/x?day=2026-02-30&access_token=abc"))
        waitForPage()
        Thread.sleep(1500)
        assertTrue(events("CONTRACT_LINK_OPENED").isEmpty())
        assertEquals(0, services.events.size)
    }

    @Test fun aRecreationLoadsFreshAndDoesNotReplayTheLink() {
        scenario = ActivityScenario.launch(linkIntent("honoured://contract/once"))
        waitForPage()
        waitForEvents("CONTRACT_LINK_OPENED", 1)
        scenario!!.recreate()
        waitForPage()
        // A new document (fresh load, not restoreState) that never hears the old link again.
        assertEquals("true", jsString("String(window.__events !== undefined)"))
        Thread.sleep(1500)
        assertTrue(events("CONTRACT_LINK_OPENED").isEmpty())
        assertTrue(events("NATIVE_READY").isNotEmpty())
    }

    @Test fun aRendererCrashIsReplacedAndTheAppKeepsRunning() {
        scenario = ActivityScenario.launch(MainActivity::class.java)
        waitForPage()
        val before = onActivity { it.webViewGeneration }
        onActivity { it.currentWebView().loadUrl("chrome://crash") }
        waitFor(30) { onActivity { it.webViewGeneration } == before + 1 }
        waitForPage()
        assertFalse(onActivity { it.isFinishing || it.isDestroyed })
        assertTrue(events("NATIVE_READY").isNotEmpty())
    }

    @Test fun contentStaysOutOfTheSystemBars() {
        scenario = ActivityScenario.launch(MainActivity::class.java)
        waitForPage()
        val (top, bottom, webTop) = onActivity { a ->
            val root = a.findViewById<android.view.View>(R.id.root)
            val loc = IntArray(2)
            a.currentWebView().getLocationOnScreen(loc)
            Triple(root.paddingTop, root.paddingBottom, loc[1])
        }
        assertTrue("status bar inset applied ($top)", top > 0)
        assertTrue("navigation bar inset applied ($bottom)", bottom > 0)
        assertTrue("web content starts below the status bar ($webTop >= $top)", webTop >= top)
    }

    // ---- helpers ----

    private fun waitForPage() = waitFor(60) {
        jsString(
            "String(document.readyState === 'complete' && typeof HonouredNative === 'object' && Array.isArray(window.__events) && window.__events.some(function(e){return JSON.parse(e).type === 'NATIVE_READY'}))"
        ) == "true"
    }

    private fun events(type: String): List<JSONObject> {
        val raw = jsString("JSON.stringify(window.__events || [])")
        if (raw == "null") return emptyList()
        val array = JSONArray(raw)
        return (0 until array.length()).map { JSONObject(array.getString(it)) }.filter { it.optString("type") == type }
    }

    private fun waitForEvents(type: String, count: Int): List<JSONObject> {
        var found = emptyList<JSONObject>()
        waitFor(20) { events(type).also { found = it }.size >= count }
        Thread.sleep(1000)
        val settled = events(type)
        assertEquals("exactly $count $type", count, settled.size)
        return settled.ifEmpty { found }
    }

    private fun <T> onActivity(block: (MainActivity) -> T): T {
        var out: T? = null
        scenario!!.onActivity { out = block(it) }
        @Suppress("UNCHECKED_CAST")
        return out as T
    }

    private fun jsString(script: String): String {
        val latch = CountDownLatch(1)
        var result = "null"
        scenario!!.onActivity { activity ->
            activity.currentWebView().evaluateJavascript(script) { value ->
                result = value ?: "null"
                latch.countDown()
            }
        }
        latch.await(10, TimeUnit.SECONDS)
        return if (result == "null") "null" else JSONArray("[$result]").getString(0)
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
