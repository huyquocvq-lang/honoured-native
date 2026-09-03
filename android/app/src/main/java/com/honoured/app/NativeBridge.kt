package com.honoured.app

import android.app.Activity
import android.webkit.JavascriptInterface
import android.webkit.WebView
import org.json.JSONObject

class NativeBridge(
    private val activity: Activity,
    private val webView: WebView
) {

    @JavascriptInterface
    fun postMessage(rawMessage: String) {
        val message = runCatching { JSONObject(rawMessage) }.getOrNull()
        val type = message?.optString("type").orEmpty()
        val payload = message?.optJSONObject("payload") ?: JSONObject()

        when (type) {
            "APP_READY" -> send(
                "NATIVE_READY",
                JSONObject()
                    .put("platform", "android")
                    .put("bridgeVersion", AppConfig.BRIDGE_VERSION)
            )
            "GET_PLATFORM_INFO" -> send(
                "PLATFORM_INFO",
                JSONObject()
                    .put("platform", "android")
                    .put("bridgeVersion", AppConfig.BRIDGE_VERSION)
            )
            "IDENTIFY_USER" -> {
                val userId = payload.optString("userId")
                if (userId.isBlank()) {
                    send("IDENTIFY_FAILED", JSONObject().put("message", "Missing userId"))
                } else {
                    SubscriptionService.identify(userId) { outcome ->
                        when (outcome) {
                            is PurchaseOutcome.Completed -> {
                                send("IDENTIFY_SUCCESS", outcome.status)
                                send("ACCESS_STATUS", outcome.status)
                            }
                            PurchaseOutcome.Cancelled -> send(
                                "IDENTIFY_FAILED",
                                JSONObject().put("message", "Unexpected cancellation")
                            )
                            is PurchaseOutcome.Failed -> send(
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
                        send("LOGOUT_SUCCESS", JSONObject().put("isSubscribed", false))
                        send(
                            "ACCESS_STATUS",
                            JSONObject().put("isSubscribed", false).put("source", "logout")
                        )
                    }
                    PurchaseOutcome.Cancelled -> send(
                        "LOGOUT_FAILED",
                        JSONObject().put("message", "Unexpected cancellation")
                    )
                    is PurchaseOutcome.Failed -> send(
                        "LOGOUT_FAILED",
                        JSONObject().put("message", outcome.message)
                    )
                }
            }
            "CHECK_ACCESS" -> {
                val userId = payload.optString("userId")
                if (userId.isBlank()) {
                    send(
                        "ACCESS_STATUS",
                        JSONObject().put("isSubscribed", false).put("source", "missing_user_id")
                    )
                    return
                }
                SubscriptionService.identify(userId) { identifyOutcome ->
                    when (identifyOutcome) {
                        is PurchaseOutcome.Completed -> SubscriptionService.checkAccess { status ->
                            send("ACCESS_STATUS", status)
                        }
                        PurchaseOutcome.Cancelled -> send(
                            "ACCESS_STATUS",
                            JSONObject().put("isSubscribed", false).put("source", "identify_cancelled")
                        )
                        is PurchaseOutcome.Failed -> send(
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
                    send("PURCHASE_FAILED", JSONObject().put("message", "Missing userId"))
                    return
                }
                activity.runOnUiThread {
                    SubscriptionService.identify(userId) { identifyOutcome ->
                        when (identifyOutcome) {
                            is PurchaseOutcome.Completed -> {
                                SubscriptionService.purchase(activity, packageIdentifier) { outcome ->
                                    when (outcome) {
                                        is PurchaseOutcome.Completed -> {
                                            send("PURCHASE_SUCCESS", outcome.status)
                                            send("ACCESS_STATUS", outcome.status)
                                        }
                                        PurchaseOutcome.Cancelled -> send("PURCHASE_CANCELLED", JSONObject())
                                        is PurchaseOutcome.Failed -> send(
                                            "PURCHASE_FAILED",
                                            JSONObject().put("message", outcome.message)
                                        )
                                    }
                                }
                            }
                            PurchaseOutcome.Cancelled -> send(
                                "PURCHASE_FAILED",
                                JSONObject().put("message", "Could not identify signed-in user")
                            )
                            is PurchaseOutcome.Failed -> send(
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
                    send("RESTORE_FAILED", JSONObject().put("message", "Missing userId"))
                    return
                }
                SubscriptionService.identify(userId) { identifyOutcome ->
                    when (identifyOutcome) {
                        is PurchaseOutcome.Completed -> SubscriptionService.restore { outcome ->
                            when (outcome) {
                                is PurchaseOutcome.Completed -> {
                                    send("RESTORE_SUCCESS", outcome.status)
                                    send("ACCESS_STATUS", outcome.status)
                                }
                                PurchaseOutcome.Cancelled -> send(
                                    "RESTORE_SUCCESS",
                                    JSONObject().put("isSubscribed", false)
                                )
                                is PurchaseOutcome.Failed -> send(
                                    "RESTORE_FAILED",
                                    JSONObject().put("message", outcome.message)
                                )
                            }
                        }
                        PurchaseOutcome.Cancelled -> send(
                            "RESTORE_FAILED",
                            JSONObject().put("message", "Could not identify signed-in user")
                        )
                        is PurchaseOutcome.Failed -> send(
                            "RESTORE_FAILED",
                            JSONObject().put("message", identifyOutcome.message)
                        )
                    }
                }
            }
            "START_SESSION" -> send(
                "ERROR",
                JSONObject().put(
                    "message",
                    "Trial sessions are enforced by Supabase RPC from the authenticated web app"
                )
            )
            else -> send(
                "ERROR",
                JSONObject().put("message", "Unsupported bridge message: $type")
            )
        }
    }

    fun send(type: String, payload: JSONObject) {
        val detail = JSONObject()
            .put("bridgeVersion", AppConfig.BRIDGE_VERSION)
            .put("type", type)
            .put("payload", payload)

        val script = "window.dispatchEvent(new CustomEvent('honoured:native',{detail:${detail}}));"
        webView.post { webView.evaluateJavascript(script, null) }
    }
}
