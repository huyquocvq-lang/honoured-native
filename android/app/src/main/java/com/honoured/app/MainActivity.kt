package com.honoured.app

import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var webView: WebView
    private lateinit var bridge: NativeBridge

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        SubscriptionService.configureIfPossible(this)

        webView = WebView(this).apply {
            setBackgroundColor(Color.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.setSupportMultipleWindows(false)
            webViewClient = HonouredWebViewClient()
        }

        bridge = NativeBridge(this, webView)
        webView.addJavascriptInterface(bridge, "HonouredNative")
        setContentView(webView)

        if (savedInstanceState == null) {
            webView.loadUrl(AppConfig.WEB_APP_URL)
        } else {
            webView.restoreState(savedInstanceState)
        }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (webView.canGoBack()) webView.goBack() else finish()
            }
        })
    }

    override fun onSaveInstanceState(outState: Bundle) {
        webView.saveState(outState)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        webView.removeJavascriptInterface("HonouredNative")
        webView.destroy()
        super.onDestroy()
    }

    private inner class HonouredWebViewClient : WebViewClient() {
        override fun onPageFinished(view: WebView, url: String) {
            bridge.send(
                "NATIVE_READY",
                org.json.JSONObject()
                    .put("platform", "android")
                    .put("bridgeVersion", AppConfig.BRIDGE_VERSION)
            )
        }

        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val uri = request.url
            return if (uri.host == AppConfig.WEB_APP_HOST || uri.scheme == "about") {
                false
            } else if (request.isForMainFrame) {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri.toString())))
                true
            } else {
                false
            }
        }
    }
}
