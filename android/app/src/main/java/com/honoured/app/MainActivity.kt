package com.honoured.app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.annotation.VisibleForTesting
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import com.honoured.app.auth.AuthBridge
import com.honoured.app.billing.SubscriptionService
import com.honoured.app.bridge.Capabilities
import com.honoured.app.bridge.NativeBridge
import com.honoured.app.auth.TrustedWebOrigin
import com.honoured.app.deeplink.ContractDeepLink
import com.honoured.app.download.DownloadSaver
import com.honoured.app.permissions.PermissionCoordinator
import com.honoured.app.permissions.PermissionGate
import androidx.appcompat.app.AlertDialog
import androidx.webkit.ScriptHandler
import com.honoured.app.session.SessionServices
import java.util.UUID

class MainActivity : AppCompatActivity() {
    private lateinit var webViewContainer: FrameLayout
    private lateinit var webView: WebView
    private lateinit var loadingIndicator: ProgressBar
    private lateinit var errorView: View
    private lateinit var errorMessage: TextView
    private lateinit var bridge: NativeBridge
    private lateinit var authBridge: AuthBridge
    private lateinit var session: SessionServices
    private lateinit var permissions: PermissionCoordinator
    private lateinit var downloads: DownloadSaver
    private var downloadScript: ScriptHandler? = null

    private var microphoneDialog: AlertDialog? = null

    /** Microphone requests of the current page still waiting for an answer. */
    private val pendingMicrophoneRequests = mutableSetOf<PermissionRequest>()

    /** Renderer losses in the last [RENDERER_CRASH_WINDOW_MS], to stop a crash loop. */
    private val rendererLosses = ArrayDeque<Long>()

    /** Bumped each time a WebView is built (first launch, renderer recovery). */
    @VisibleForTesting
    var webViewGeneration = 0
        private set

    @VisibleForTesting
    fun currentWebView(): WebView = webView

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
        // Android 15 draws every targetSdk 35 app edge to edge; do the same on
        // older versions and keep the page out from under the bars ourselves.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        // Registers an activity-result launcher, so it must exist before STARTED.
        permissions = PermissionCoordinator(this)
        downloads = DownloadSaver(this, TrustedWebOrigin.from(AppConfig.WEB_APP_URL))

        SubscriptionService.configureIfPossible(this)

        if (BuildConfig.DEBUG || BuildConfig.WEBVIEW_DEBUGGING) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        setContentView(R.layout.activity_main)
        applySystemBarInsets(findViewById(R.id.root))
        webViewContainer = findViewById(R.id.webViewContainer)
        loadingIndicator = findViewById(R.id.loadingIndicator)
        errorView = findViewById(R.id.errorView)
        errorMessage = findViewById(R.id.errorMessage)

        session = SessionServices.get(this)
        buildWebView()

        findViewById<Button>(R.id.retryButton).setOnClickListener { retry() }

        // A WebView too old to parse the web app would only show a black page.
        val provider = WebViewSupport.provider(this)
        if (!WebViewSupport.isSupported(provider?.major)) {
            showOutdatedWebView(provider)
            return
        }

        // After process death (or a recreation outside configChanges) the saved
        // WebView state is not trusted: the page keeps its own state in
        // localStorage and the native session lives in the encrypted store, so
        // a fresh load is both simpler and correct. Pending links wait in the
        // durable event store until the new page speaks.
        load()

        // A link that started this activity. Not on a recreation (it was handled
        // the first time) and not from Recents (that replays the old intent).
        if (savedInstanceState == null) routeDeepLink(intent)

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = handleBack()
        })
    }

    /**
     * Back first asks the page to close whatever is on top (a dialog, a sheet,
     * a sub-screen) through `window.__honouredBack()`, which returns true when
     * it did. Otherwise WebView history, and finally the app goes to the
     * background like the Home button — never finish(), which would throw away
     * an unsigned contract or an open timer screen. A page without the hook
     * (older web) gets the background behaviour.
     */
    private fun handleBack() {
        val view = webView
        val onApp = !mainFrameFailed && runCatching { Uri.parse(view.url).host }.getOrNull() == AppConfig.WEB_APP_HOST
        if (!onApp) {
            if (view.canGoBack()) view.goBack() else moveTaskToBack(true)
            return
        }
        backPending = true
        timeoutHandler.removeCallbacks(backFallback)
        // A page whose script is stuck never answers: Back must still work.
        timeoutHandler.postDelayed(backFallback, BACK_TIMEOUT_MS)
        view.evaluateJavascript(BACK_SCRIPT) { result ->
            if (!backPending) return@evaluateJavascript
            backPending = false
            timeoutHandler.removeCallbacks(backFallback)
            if (view !== webView || isFinishing || isDestroyed) return@evaluateJavascript
            when (result) {
                "\"handled\"" -> Unit
                // The page owns Back and had nothing to close (or something
                // must not be closed now, like an unsigned draft): keep it all
                // and go to the background. History would undo page state.
                "\"unhandled\"" -> moveTaskToBack(true)
                // An older page without the hook.
                else -> if (view.canGoBack()) view.goBack() else moveTaskToBack(true)
            }
        }
    }

    private var backPending = false

    private val backFallback = Runnable {
        if (!backPending) return@Runnable
        backPending = false
        if (!isFinishing && !isDestroyed) moveTaskToBack(true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // getIntent() stays the launch intent: nothing reads it after onCreate.
        routeDeepLink(intent)
    }

    /**
     * `honoured://contract/<id>?day=<YYYY-MM-DD>` becomes a durable
     * `CONTRACT_LINK_OPENED`, delivered once the page is ready. A malformed
     * link is dropped. Navigation only: the page decides what the id means.
     */
    private fun routeDeepLink(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val target = ContractDeepLink.parse(intent.dataString) ?: return
        bridge.broadcastDurable(
            "CONTRACT_LINK_OPENED",
            ContractDeepLink.eventPayload(target, UUID.randomUUID().toString()),
        )
    }

    /** Pads the content out from under the status, navigation and cutout areas, and above the keyboard. */
    private fun applySystemBarInsets(root: View) {
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )
            val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
            view.setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, ime.bottom))
            WindowInsetsCompat.CONSUMED
        }
    }

    /** Creates the WebView and both bridges. The secure auth transport is installed before any load. */
    private fun buildWebView() {
        val view = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            setBackgroundColor(Color.BLACK)
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = false
            settings.allowContentAccess = false
            settings.setSupportMultipleWindows(false)
            // Serve repeat launches from the HTTP cache instead of revalidating
            // every asset against the network.
            settings.cacheMode = WebSettings.LOAD_DEFAULT
            // The ambient restriction tone starts from a timer rather than from
            // a tap on the audio element, which WebView otherwise blocks.
            settings.mediaPlaybackRequiresUserGesture = false
            webViewClient = HonouredWebViewClient()
            webChromeClient = HonouredChromeClient()
        }
        webViewContainer.addView(view)
        webView = view
        downloadScript = downloads.install(view)
        authBridge = AuthBridge(this, view, lifecycleScope, session).also { it.install() }
        bridge = NativeBridge(this, view, session) {
            Capabilities.build(authBridge.capability(), authBridge.isSessionSupported)
        }
        view.addJavascriptInterface(bridge, "HonouredNative")
        webViewGeneration++
        webViewCreatedHook?.invoke(view)
    }

    /** Detaches and destroys the current WebView and its bridges. Safe on a WebView whose renderer is gone. */
    private fun tearDownWebView() {
        pendingMicrophoneRequests.clear()
        runCatching { authBridge.destroy() }
        runCatching { bridge.destroy() }
        val old = webView
        downloads.uninstall(old, downloadScript)
        downloadScript = null
        runCatching { old.removeJavascriptInterface("HonouredNative") }
        webViewContainer.removeView(old)
        runCatching { old.destroy() }
    }

    /**
     * The renderer crashed or was killed to free memory. The WebView is dead
     * and must never be touched again: replace it and load the app from the
     * start, so the shell itself survives. A renderer that keeps dying ends on
     * the error screen instead of a crash loop.
     */
    private fun recoverFromRendererLoss(didCrash: Boolean) {
        val now = SystemClock.elapsedRealtime()
        // Only real crashes count towards the loop limit: the system killing a
        // background renderer to free memory is normal and just reloads.
        if (didCrash) rendererLosses.addLast(now)
        while (rendererLosses.isNotEmpty() && now - rendererLosses.first() > RENDERER_CRASH_WINDOW_MS) {
            rendererLosses.removeFirst()
        }
        Log.w(TAG, "WebView renderer gone (crashed=$didCrash), rebuilding")
        tearDownWebView()
        buildWebView()
        if (rendererLosses.size > MAX_RENDERER_LOSSES) {
            showError(getString(R.string.error_renderer))
        } else {
            load()
        }
    }

    private fun retry() {
        rendererLosses.clear()
        load()
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

    /** Asks for a WebView update instead of loading a page this WebView cannot run. */
    private fun showOutdatedWebView(provider: WebViewSupport.Provider?) {
        isLoading = false
        mainFrameFailed = true
        loadingIndicator.visibility = View.GONE
        errorView.visibility = View.VISIBLE
        findViewById<TextView>(R.id.errorTitle).setText(R.string.webview_outdated_title)
        errorMessage.setText(R.string.webview_outdated_body)
        val packageName = provider?.packageName ?: "com.google.android.webview"
        findViewById<Button>(R.id.retryButton).apply {
            setText(R.string.webview_outdated_action)
            setOnClickListener {
                val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))
                val web = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$packageName"))
                try {
                    startActivity(market)
                } catch (e: ActivityNotFoundException) {
                    try {
                        startActivity(web)
                    } catch (e: ActivityNotFoundException) {
                    }
                }
            }
        }
    }

    private fun showMicrophoneBlocked() {
        if (isFinishing || isDestroyed) return
        if (microphoneDialog?.isShowing == true) return
        microphoneDialog = AlertDialog.Builder(this)
            .setTitle(R.string.microphone_blocked_title)
            .setMessage(R.string.microphone_blocked_body)
            .setPositiveButton(R.string.microphone_blocked_settings) { _, _ -> permissions.openAppSettings() }
            .setNegativeButton(R.string.microphone_blocked_dismiss, null)
            .setOnDismissListener { microphoneDialog = null }
            .show()
    }

    @VisibleForTesting
    fun isShowingError(): Boolean = errorView.visibility == View.VISIBLE

    private fun showError(detail: String) {
        isLoading = false
        mainFrameFailed = true
        timeoutHandler.removeCallbacks(loadTimeout)
        loadingIndicator.visibility = View.GONE
        errorView.visibility = View.VISIBLE
        errorMessage.text = getString(R.string.error_body) + "\n\n" + detail
    }

    /**
     * Stops the compositor, animations and media the WebView would otherwise keep
     * running while the app is not on screen. JavaScript timers keep ticking, so
     * an in-flight restriction countdown is unaffected.
     */
    override fun onPause() {
        webView.onPause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        webView.onResume()
    }

    override fun onDestroy() {
        timeoutHandler.removeCallbacks(loadTimeout)
        timeoutHandler.removeCallbacks(backFallback)
        // Answer each pending request exactly once, then let the gate's own
        // cancel find nothing left to answer.
        val pending = pendingMicrophoneRequests.toList()
        pendingMicrophoneRequests.clear()
        pending.forEach { runCatching { it.deny() } }
        permissions.destroy()
        microphoneDialog?.dismiss()
        microphoneDialog = null
        tearDownWebView()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "Honoured"
        private const val LOAD_TIMEOUT_MS = 30_000L
        private const val RENDERER_CRASH_WINDOW_MS = 60_000L
        private const val MAX_RENDERER_LOSSES = 3

        /** Android's own answer to a blocked permission comes back without any UI, well under this. */
        private const val INSTANT_DENIAL_MS = 400L

        private const val BACK_TIMEOUT_MS = 1_500L

        /** "handled", "unhandled", or "missing" for a page without the hook. */
        private const val BACK_SCRIPT =
            "(function(){try{if(typeof window.__honouredBack!=='function')return 'missing';" +
                "return window.__honouredBack()===true?'handled':'unhandled'}catch(e){return 'unhandled'}})()"

        /** Instrumentation only: runs on each new WebView before its first load. */
        @VisibleForTesting
        @JvmStatic
        var webViewCreatedHook: ((WebView) -> Unit)? = null
    }

    private inner class HonouredChromeClient : WebChromeClient() {
        override fun onPermissionRequest(request: PermissionRequest) {
            runOnUiThread {
                val trustedOrigin = request.origin.host == AppConfig.WEB_APP_HOST
                val audioOnly = request.resources.contentEquals(
                    arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE)
                )
                if (!trustedOrigin || !audioOnly) {
                    request.deny()
                    return@runOnUiThread
                }
                pendingMicrophoneRequests += request
                val askedAt = SystemClock.elapsedRealtime()
                permissions.request(Manifest.permission.RECORD_AUDIO) { outcome ->
                    // Cancelled by the page, or its WebView was replaced meanwhile.
                    if (!pendingMicrophoneRequests.remove(request)) return@request
                    // A request answers once; Chromium throws on a second answer.
                    if (outcome == PermissionGate.Outcome.GRANTED) {
                        runCatching { request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE)) }
                        return@request
                    }
                    runCatching { request.deny() }
                    // "Don't allow" was chosen for good: Android answered without
                    // showing anything, so only Settings can turn it back on. A
                    // BUSY answer (another prompt was open) is not that.
                    val instant = SystemClock.elapsedRealtime() - askedAt < INSTANT_DENIAL_MS
                    if (outcome == PermissionGate.Outcome.DENIED && instant &&
                        permissions.status(Manifest.permission.RECORD_AUDIO) == PermissionGate.Status.BLOCKED
                    ) {
                        showMicrophoneBlocked()
                    }
                }
            }
        }

        override fun onPermissionRequestCanceled(request: PermissionRequest) {
            runOnUiThread { pendingMicrophoneRequests.remove(request) }
        }
    }

    private inner class HonouredWebViewClient : WebViewClient() {
        override fun onPageFinished(view: WebView, url: String) {
            if (view !== webView || mainFrameFailed) return

            showContent()
            bridge.send("NATIVE_READY", bridge.readyPayload())
        }

        override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
            if (view !== webView) return
            // A new main-frame document: no Google result or session reply may
            // reach the old one, and broadcasts wait for the new one.
            authBridge.documentWillChange()
            bridge.pageWillChange()
        }

        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            // Returning true keeps the app alive; an older WebView is already gone.
            if (view === webView && !isFinishing && !isDestroyed) {
                recoverFromRendererLoss(detail.didCrash())
            }
            return true
        }

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError
        ) {
            if (view !== webView || !request.isForMainFrame) return
            showError("${error.description} (${error.errorCode})")
        }

        override fun onReceivedHttpError(
            view: WebView,
            request: WebResourceRequest,
            errorResponse: WebResourceResponse
        ) {
            if (view !== webView || !request.isForMainFrame) return
            showError("HTTP ${errorResponse.statusCode}")
        }

        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val uri = request.url
            return if (uri.host == AppConfig.WEB_APP_HOST || uri.scheme == "about") {
                false
            } else if (request.isForMainFrame) {
                // A link with no handler on the device (e.g. mailto: without a
                // mail app) is dropped instead of crashing the shell.
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri.toString())))
                } catch (e: ActivityNotFoundException) {
                }
                true
            } else {
                false
            }
        }
    }
}
