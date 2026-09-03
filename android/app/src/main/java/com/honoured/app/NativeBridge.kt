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
            "CHECK_ACCESS" -> SubscriptionService.checkAccess { status ->
                send("ACCESS_STATUS", status)
            }
            "START_PURCHASE" -> {
                val packageIdentifier = payload.optString("packageIdentifier").takeIf { it.isNotBlank() }
                activity.runOnUiThread {
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
            }
            "RESTORE_PURCHASES" -> SubscriptionService.restore { outcome ->
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
            "START_SESSION" -> send(
                "ERROR",
                JSONObject().put("message", "START_SESSION is reserved for the trial-engine step")
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
