package com.honoured.app

import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.ProgressBar
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var webView: WebView
    private lateinit var loadingIndicator: ProgressBar
    private lateinit var errorView: View
    private lateinit var errorMessage: TextView
    private lateinit var bridge: NativeBridge

    /**
     * Set when the main frame fails so [WebViewClient.onPageFinished], which still
     * runs for the error page, does not hide the error state again.
     */
    private var mainFrameFailed = false
    private var isLoading = false

    private val timeoutHandler = Handler(Looper.getMainLooper())

    /**
     * A host that accepts the connection but never answers produces no
     * WebViewClient error callback, so the shell would spin forever.
     */
    private val loadTimeout = Runnable {
        if (!isLoading) return@Runnable
        webView.stopLoading()
        showError(getString(R.string.error_timeout))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        SubscriptionService.configureIfPossible(this)

        if (BuildConfig.DEBUG) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        setContentView(R.layout.activity_main)
        webView = findViewById(R.id.webView)
        loadingIndicator = findViewById(R.id.loadingIndicator)
        errorView = findViewById(R.id.errorView)
        errorMessage = findViewById(R.id.errorMessage)

        webView.apply {
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

        findViewById<Button>(R.id.retryButton).setOnClickListener { load() }

        if (savedInstanceState == null) {
            load()
        } else {
            showLoading()
            webView.restoreState(savedInstanceState)
        }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (webView.canGoBack()) webView.goBack() else finish()
            }
        })
    }

    private fun load() {
        mainFrameFailed = false
        showLoading()
        webView.loadUrl(AppConfig.WEB_APP_URL)
    }

    private fun showLoading() {
        isLoading = true
        loadingIndicator.visibility = View.VISIBLE
        errorView.visibility = View.GONE
        timeoutHandler.removeCallbacks(loadTimeout)
        timeoutHandler.postDelayed(loadTimeout, LOAD_TIMEOUT_MS)
    }

    private fun showContent() {
        isLoading = false
        timeoutHandler.removeCallbacks(loadTimeout)
        loadingIndicator.visibility = View.GONE
        errorView.visibility = View.GONE
    }

    private fun showError(detail: String) {
        isLoading = false
        mainFrameFailed = true
        timeoutHandler.removeCallbacks(loadTimeout)
        loadingIndicator.visibility = View.GONE
        errorView.visibility = View.VISIBLE
        errorMessage.text = getString(R.string.error_body) + "\n\n" + detail
    }

    override fun onSaveInstanceState(outState: Bundle) {
        webView.saveState(outState)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        timeoutHandler.removeCallbacks(loadTimeout)
        webView.removeJavascriptInterface("HonouredNative")
        (webView.parent as? ViewGroup)?.removeView(webView)
        webView.destroy()
        super.onDestroy()
    }

    private companion object {
        const val LOAD_TIMEOUT_MS = 30_000L
    }

    private inner class HonouredWebViewClient : WebViewClient() {
        override fun onPageFinished(view: WebView, url: String) {
            if (mainFrameFailed) return

            showContent()
            bridge.send(
                "NATIVE_READY",
                org.json.JSONObject()
                    .put("platform", "android")
                    .put("bridgeVersion", AppConfig.BRIDGE_VERSION)
            )
        }

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError
        ) {
            if (!request.isForMainFrame) return
            showError("${error.description} (${error.errorCode})")
        }

        override fun onReceivedHttpError(
            view: WebView,
            request: WebResourceRequest,
            errorResponse: WebResourceResponse
        ) {
            if (!request.isForMainFrame) return
            showError("HTTP ${errorResponse.statusCode}")
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
