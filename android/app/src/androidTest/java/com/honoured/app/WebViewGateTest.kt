package com.honoured.app

import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs on every device: a WebView older than the web app's build target gets
 * the update screen instead of a black page; a current one loads the app.
 */
@RunWith(AndroidJUnit4::class)
class WebViewGateTest {
    @Test fun theShellMatchesTheInstalledWebView() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val supported = WebViewSupport.isSupported(context)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            Thread.sleep(if (supported) 8000 else 2000)
            scenario.onActivity { activity ->
                if (supported) {
                    assertFalse("the app loads", activity.isShowingError())
                } else {
                    assertEquals(true, activity.isShowingError())
                    assertEquals(
                        context.getString(R.string.webview_outdated_title),
                        activity.findViewById<TextView>(R.id.errorTitle).text.toString(),
                    )
                }
            }
        }
    }
}
