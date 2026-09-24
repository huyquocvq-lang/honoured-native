package com.honoured.app.bridge

import android.app.Activity
import android.webkit.JavascriptInterface
import android.webkit.WebView
import com.honoured.app.AppConfig
import com.honoured.app.auth.AuthBridge
import com.honoured.app.billing.PurchaseOutcome
import com.honoured.app.billing.SubscriptionService
import org.json.JSONObject

class NativeBridge(
    private val activity: Activity,
    private val webView: WebView,
    /** Capabilities added to NATIVE_READY / PLATFORM_INFO (Google Sign-In). */
    private val capabilities: () -> JSONObject = { JSONObject() },
) {

    /** Same payload for every NATIVE_READY / PLATFORM_INFO path. */
    fun readyPayload(): JSONObject = JSONObject()
        .put("platform", "android")
        .put("bridgeVersion", AppConfig.BRIDGE_VERSION)
        .put("capabilities", capabilities())

    @JavascriptInterface
    fun postMessage(rawMessage: String) {
        val message = runCatching { JSONObject(rawMessage) }.getOrNull()
        val type = message?.optString("type").orEmpty()
        val payload = message?.optJSONObject("payload") ?: JSONObject()
        val requestId = payload.optString("requestId").takeIf { it.isNotBlank() }
        val reply: (String, JSONObject) -> Unit = { replyType, replyPayload ->
            send(replyType, replyPayload, requestId)
        }

        when (type) {
            "APP_READY" -> reply("NATIVE_READY", readyPayload())
            "GET_PLATFORM_INFO" -> reply("PLATFORM_INFO", readyPayload())
            // Google auth runs only on the origin-scoped HonouredAuth transport.
            in AuthBridge.MESSAGE_TYPES -> reply(
                "ERROR",
                JSONObject()
                    .put("message", "$type is only accepted on the secure auth transport")
                    .put("code", "insecure_transport")
            )
            "IDENTIFY_USER" -> {
                val userId = payload.optString("userId")
                if (userId.isBlank()) {
                    reply("IDENTIFY_FAILED", JSONObject().put("message", "Missing userId"))
                } else {
                    SubscriptionService.identify(userId) { outcome ->
                        when (outcome) {
                            is PurchaseOutcome.Completed -> {
                                reply("IDENTIFY_SUCCESS", outcome.status)
                                // The already-identified shortcut skips the CustomerInfo
                                // fetch, so its payload carries no verdict. Broadcasting it
                                // as a status would read as "not subscribed". A verdict for a
                                // user RevenueCat is no longer bound to is not sent.
                                if (outcome.status.has("isSubscribed") && SubscriptionService.isIdentified(userId)) {
                                    reply("ACCESS_STATUS", outcome.status)
                                }
                            }
                            PurchaseOutcome.Cancelled -> reply(
                                "IDENTIFY_FAILED",
                                JSONObject().put("message", "Unexpected cancellation")
                            )
                            is PurchaseOutcome.Failed -> reply(
                                "IDENTIFY_FAILED",
                                JSONObject().put("message", outcome.message)
                            )
                        }
                    }
                }
            }
            "LOGOUT_USER" -> SubscriptionService.logout { outcome ->
                when (outcome) {
                    is PurchaseOutcome.Completed -> {
                        reply("LOGOUT_SUCCESS", JSONObject().put("isSubscribed", false))
                        // A sign-in queued after this logout may already own the identity.
                        if (SubscriptionService.isAnonymous) {
                            reply(
                                "ACCESS_STATUS",
                                JSONObject().put("isSubscribed", false).put("source", "logout")
                            )
                        }
                    }
                    PurchaseOutcome.Cancelled -> reply(
                        "LOGOUT_FAILED",
                        JSONObject().put("message", "Unexpected cancellation")
                    )
                    is PurchaseOutcome.Failed -> reply(
                        "LOGOUT_FAILED",
                        JSONObject().put("message", outcome.message)
                    )
                }
            }
            "CHECK_ACCESS" -> {
                val userId = payload.optString("userId")
                if (userId.isBlank()) {
                    reply(
                        "ACCESS_STATUS",
                        JSONObject().put("isSubscribed", false).put("source", "missing_user_id")
                    )
                    return
                }
                SubscriptionService.identify(userId) { identifyOutcome ->
                    when (identifyOutcome) {
                        is PurchaseOutcome.Completed -> SubscriptionService.checkAccess { status ->
                            if (SubscriptionService.isIdentified(userId)) {
                                reply("ACCESS_STATUS", status)
                            } else {
                                reply(
                                    "ACCESS_STATUS",
                                    JSONObject().put("isSubscribed", false).put("source", "identity_changed")
                                )
                            }
                        }
                        PurchaseOutcome.Cancelled -> reply(
                            "ACCESS_STATUS",
                            JSONObject().put("isSubscribed", false).put("source", "identify_cancelled")
                        )
                        is PurchaseOutcome.Failed -> reply(
                            "ACCESS_STATUS",
                            JSONObject()
                                .put("isSubscribed", false)
                                .put("source", "identify_failed")
                                .put("message", identifyOutcome.message)
                        )
                    }
                }
            }
            "START_PURCHASE" -> {
                val userId = payload.optString("userId")
                val packageIdentifier = payload.optString("packageIdentifier").takeIf { it.isNotBlank() }
                if (userId.isBlank()) {
                    reply("PURCHASE_FAILED", JSONObject().put("message", "Missing userId"))
                    return
                }
                activity.runOnUiThread {
                    SubscriptionService.identify(userId) { identifyOutcome ->
                        when (identifyOutcome) {
                            is PurchaseOutcome.Completed -> {
                                SubscriptionService.purchase(activity, packageIdentifier) { outcome ->
                                    when (outcome) {
                                        is PurchaseOutcome.Completed -> {
                                            reply("PURCHASE_SUCCESS", outcome.status)
                                            reply("ACCESS_STATUS", outcome.status)
                                        }
                                        PurchaseOutcome.Cancelled -> reply("PURCHASE_CANCELLED", JSONObject())
                                        is PurchaseOutcome.Failed -> reply(
                                            "PURCHASE_FAILED",
                                            JSONObject().put("message", outcome.message)
                                        )
                                    }
                                }
                            }
                            PurchaseOutcome.Cancelled -> reply(
                                "PURCHASE_FAILED",
                                JSONObject().put("message", "Could not identify signed-in user")
                            )
                            is PurchaseOutcome.Failed -> reply(
                                "PURCHASE_FAILED",
                                JSONObject().put("message", identifyOutcome.message)
                            )
                        }
                    }
                }
            }
            "RESTORE_PURCHASES" -> {
                val userId = payload.optString("userId")
                if (userId.isBlank()) {
                    reply("RESTORE_FAILED", JSONObject().put("message", "Missing userId"))
                    return
                }
                SubscriptionService.identify(userId) { identifyOutcome ->
                    when (identifyOutcome) {
                        is PurchaseOutcome.Completed -> SubscriptionService.restore { outcome ->
                            when (outcome) {
                                is PurchaseOutcome.Completed -> {
                                    reply("RESTORE_SUCCESS", outcome.status)
                                    reply("ACCESS_STATUS", outcome.status)
                                }
                                PurchaseOutcome.Cancelled -> reply(
                                    "RESTORE_SUCCESS",
                                    JSONObject().put("isSubscribed", false)
                                )
                                is PurchaseOutcome.Failed -> reply(
                                    "RESTORE_FAILED",
                                    JSONObject().put("message", outcome.message)
                                )
                            }
                        }
                        PurchaseOutcome.Cancelled -> reply(
                            "RESTORE_FAILED",
                            JSONObject().put("message", "Could not identify signed-in user")
                        )
                        is PurchaseOutcome.Failed -> reply(
                            "RESTORE_FAILED",
                            JSONObject().put("message", identifyOutcome.message)
                        )
                    }
                }
            }
            "START_SESSION" -> reply(
                "ERROR",
                JSONObject().put(
                    "message",
                    "Trial sessions are enforced by Supabase RPC from the authenticated web app"
                )
            )
            // Live Activities are iOS-only. The web app checks the capability in
            // NATIVE_READY first; a stray call still gets a correlated answer.
            "TRACK_CONTRACT", "SYNC_TRACKED_CONTRACTS", "STOP_TRACKING_CONTRACT",
            "GET_LIVE_ACTIVITY_STATE" -> reply(
                "ERROR",
                JSONObject()
                    .put("message", "$type is not implemented on Android")
                    .put("code", "not_implemented")
            )
            else -> reply(
                "ERROR",
                JSONObject().put("message", "Unsupported bridge message: $type")
            )
        }
    }

    /**
     * @param requestId echoed back from the inbound message that caused this reply.
     * The web app uses its presence to tell a solicited reply from an unsolicited
     * broadcast, so that answering a request cannot trigger another request.
     */
    fun send(type: String, payload: JSONObject, requestId: String? = null) {
        val payload = if (requestId == null) payload
        else JSONObject(payload.toString()).put("requestId", requestId)

        val detail = JSONObject()
            .put("bridgeVersion", AppConfig.BRIDGE_VERSION)
            .put("type", type)
            .put("payload", payload)

        val script = "window.dispatchEvent(new CustomEvent('honoured:native',{detail:${detail}}));"
        webView.post { webView.evaluateJavascript(script, null) }
    }
}
