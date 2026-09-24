package com.honoured.app.auth

import android.annotation.SuppressLint
import android.app.Activity
import android.net.Uri
import android.webkit.WebView
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.honoured.app.AppConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Google Sign-In over an origin-scoped `WebMessageListener` named
 * `HonouredAuth` (`docs/bridge.md`, "Google Sign-In"). The object is injected
 * only into frames of the exact configured origin; messages are further
 * accepted only from the main frame, and every reply goes back through the
 * requesting frame's own reply proxy. The legacy `HonouredNative` interface
 * refuses these messages. Main thread only.
 */
class AuthBridge(
    private val activity: Activity,
    private val webView: WebView,
    private val scope: CoroutineScope,
) : WebViewCompat.WebMessageListener {
    private val origin = TrustedWebOrigin.from(AppConfig.WEB_APP_URL)
    private val coordinator = GoogleSignInCoordinator(
        activity,
        GoogleClientConfig.serverClientId(AppConfig.GOOGLE_WEB_CLIENT_ID),
    )
    private val state = GoogleAuthState()
    private val gate = ProviderPresentationGate()

    /** The reply proxy of the document that synced the current context. */
    private var contextProxy: JavaScriptReplyProxy? = null
    private var presentation: Job? = null
    private var timeout: Job? = null
    private var cleanup: Job? = null
    private var installed = false

    /** True when this WebView can run the flow over the secure transport. */
    val isSupported: Boolean = origin != null &&
        WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)

    /** Capability advertised in `NATIVE_READY` / `PLATFORM_INFO`. */
    fun capability(): JSONObject = JSONObject()
        .put("protocolVersion", 1)
        .put("supported", isSupported && installed)
        .put("configured", coordinator.isConfigured)
        .put("transport", "trusted-auth-v1")
        .put("intents", JSONArray().put("sign_in").put("link"))

    /** Must run before the first page load so the object is injected into it. */
    @SuppressLint("RequiresFeature")
    fun install() {
        val origin = origin ?: return
        if (!isSupported || installed) return
        WebViewCompat.addWebMessageListener(webView, JS_OBJECT, setOf(origin.listenerRule), this)
        installed = true
    }

    /** A main-frame navigation started: nothing may reach the old document. */
    fun documentWillChange() {
        timeout?.cancel()
        presentation?.cancel()
        state.documentWillChange()
        contextProxy = null
    }

    @SuppressLint("RequiresFeature")
    fun destroy() {
        documentWillChange()
        cleanup?.cancel()
        if (installed) WebViewCompat.removeWebMessageListener(webView, JS_OBJECT)
        installed = false
    }

    override fun onPostMessage(
        view: WebView,
        message: WebMessageCompat,
        sourceOrigin: Uri,
        isMainFrame: Boolean,
        replyProxy: JavaScriptReplyProxy,
    ) {
        val trusted = origin ?: return
        if (!isMainFrame || !trusted.matches(sourceOrigin.scheme, sourceOrigin.host, sourceOrigin.port)) return
        if (!trusted.matches(view.url)) return
        val body = message.data?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return
        val type = body.optString("type")
        val payload = body.optJSONObject("payload") ?: JSONObject()
        val requestId = payload.optString("requestId").takeIf { it.isNotEmpty() }
        val reply: (String, JSONObject) -> Unit = { replyType, replyPayload ->
            post(replyProxy, replyType, replyPayload, requestId)
        }
        when (type) {
            "SYNC_AUTH_CONTEXT" -> {
                if (!payload.has("userId")) {
                    reply("ERROR", JSONObject().put("code", "invalid_payload").put("message", "userId must be a string or null"))
                    return
                }
                val userId = if (payload.isNull("userId")) null else payload.optString("userId")
                val context = state.sync(userId)
                contextProxy = replyProxy
                reply(
                    "AUTH_CONTEXT_SYNCED",
                    JSONObject().put("authContextId", context.id).put("userId", context.userId ?: JSONObject.NULL),
                )
            }
            "SIGN_IN_WITH_GOOGLE" -> start(payload, requestId, replyProxy, reply)
            "CANCEL_GOOGLE_SIGN_IN" -> cancel(payload, replyProxy, reply)
            "CLEAR_GOOGLE_SIGN_IN" -> clear(reply)
            else -> reply(
                "ERROR",
                JSONObject().put("code", "unsupported_message").put("message", "Unsupported auth message: $type"),
            )
        }
    }

    private fun start(
        payload: JSONObject,
        requestId: String?,
        replyProxy: JavaScriptReplyProxy,
        reply: (String, JSONObject) -> Unit,
    ) {
        val contextId = payload.optString("authContextId").takeIf { it.isNotEmpty() }
        if (!coordinator.isConfigured) return reply("GOOGLE_SIGN_IN_FAILED", failure(GoogleAuthFailure.NOT_CONFIGURED, contextId))
        // Only the document that synced the context may use it.
        if (replyProxy !== contextProxy) return reply("GOOGLE_SIGN_IN_FAILED", failure(GoogleAuthFailure.STALE_CONTEXT, contextId))
        val (rawNonce, hashedNonce) = AuthNonce.make()
        val attempt = when (val result = state.begin(requestId, payload.optString("intent").takeIf { it.isNotEmpty() }, contextId, rawNonce)) {
            is BeginResult.Rejected -> return reply("GOOGLE_SIGN_IN_FAILED", failure(result.failure, contextId))
            is BeginResult.Started -> result.attempt
        }
        val token = gate.acquire(ProviderPresentationGate.Holder.GOOGLE)
        if (token == null) {
            state.finish(attempt)
            return reply("GOOGLE_SIGN_IN_FAILED", failure(GoogleAuthFailure.IN_PROGRESS, contextId))
        }
        timeout = scope.launch {
            delay(TIMEOUT_MS)
            if (state.finish(attempt) != null) {
                post(replyProxy, "GOOGLE_SIGN_IN_FAILED", failure(GoogleAuthFailure.TIMEOUT, attempt.contextId), attempt.requestId)
                presentation?.cancel()
            }
        }
        presentation = scope.launch {
            try {
                val outcome = coordinator.present(hashedNonce)
                timeout?.cancel()
                // Reloaded, re-owned, cancelled or timed out meanwhile: drop it.
                val current = state.finish(attempt) ?: return@launch
                when (outcome) {
                    is GoogleSignInCoordinator.Outcome.Success -> post(
                        replyProxy,
                        "GOOGLE_SIGN_IN_SUCCESS",
                        JSONObject()
                            .put("intent", current.intent.wire)
                            .put("authContextId", current.contextId)
                            .put("idToken", outcome.idToken)
                            .put("rawNonce", current.rawNonce),
                        current.requestId,
                    )
                    is GoogleSignInCoordinator.Outcome.Failure -> post(
                        replyProxy,
                        "GOOGLE_SIGN_IN_FAILED",
                        failure(outcome.failure, current.contextId),
                        current.requestId,
                    )
                }
            } finally {
                gate.release(token)
            }
        }
    }

    private fun cancel(payload: JSONObject, replyProxy: JavaScriptReplyProxy, reply: (String, JSONObject) -> Unit) {
        val target = payload.optString("targetRequestId").takeIf { it.isNotEmpty() }
        val cancelled = if (replyProxy === contextProxy) {
            state.cancel(payload.optString("authContextId").takeIf { it.isNotEmpty() }, target)
        } else {
            null
        }
        if (cancelled != null) {
            timeout?.cancel()
            presentation?.cancel()
            post(replyProxy, "GOOGLE_SIGN_IN_FAILED", failure(GoogleAuthFailure.CANCELLED, cancelled.contextId), cancelled.requestId)
        }
        reply(
            "GOOGLE_SIGN_IN_CANCEL_ACCEPTED",
            JSONObject().put("targetRequestId", target ?: JSONObject.NULL).put("cancelled", cancelled != null),
        )
    }

    /**
     * Invalidation first and synchronously, then the provider cleanup once any
     * presentation has closed. Until the cleanup ends new requests get
     * `in_progress`, so it can never run after a newer sign-in.
     */
    private fun clear(reply: (String, JSONObject) -> Unit) {
        timeout?.cancel()
        val context = state.clear()
        val previous = presentation
        previous?.cancel()
        val previousCleanup = cleanup
        cleanup = scope.launch {
            previous?.join()
            previousCleanup?.join()
            var token = gate.acquire(ProviderPresentationGate.Holder.GOOGLE_CLEANUP)
            while (token == null) {
                delay(50)
                token = gate.acquire(ProviderPresentationGate.Holder.GOOGLE_CLEANUP)
            }
            try {
                val cleared = coordinator.isConfigured && coordinator.clear()
                val body = JSONObject().put("authContextId", context.id).put("providerCleared", cleared || !coordinator.isConfigured)
                if (coordinator.isConfigured && !cleared) body.put("warningCode", "provider_cleanup_failed")
                // The page may have changed while the cleanup ran; only the
                // context it was meant for may learn the new id.
                if (state.context?.id == context.id) reply("GOOGLE_SIGN_IN_CLEARED", body)
            } finally {
                gate.release(token)
            }
        }
    }

    private fun failure(failure: GoogleAuthFailure, contextId: String?): JSONObject = JSONObject()
        .put("code", failure.code)
        .put("message", failure.message)
        .put("authContextId", contextId ?: JSONObject.NULL)

    /** Direct reply to the requesting frame. Never queued, never logged. */
    @SuppressLint("RequiresFeature")
    private fun post(proxy: JavaScriptReplyProxy, type: String, payload: JSONObject, requestId: String?) {
        val body = if (requestId == null) payload else JSONObject(payload.toString()).put("requestId", requestId)
        val envelope = JSONObject()
            .put("bridgeVersion", AppConfig.BRIDGE_VERSION)
            .put("type", type)
            .put("payload", body)
        proxy.postMessage(envelope.toString())
    }

    companion object {
        const val JS_OBJECT = "HonouredAuth"
        const val TIMEOUT_MS = 120_000L

        /** Auth message types the legacy `HonouredNative` interface must refuse. */
        val MESSAGE_TYPES = setOf("SYNC_AUTH_CONTEXT", "SIGN_IN_WITH_GOOGLE", "CANCEL_GOOGLE_SIGN_IN", "CLEAR_GOOGLE_SIGN_IN")
    }
}
