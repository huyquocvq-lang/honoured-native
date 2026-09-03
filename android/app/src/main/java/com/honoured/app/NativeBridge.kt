package com.honoured.app

import android.webkit.JavascriptInterface
import android.webkit.WebView
import org.json.JSONObject

class NativeBridge(private val webView: WebView) {

    @JavascriptInterface
    fun postMessage(rawMessage: String) {
        val message = runCatching { JSONObject(rawMessage) }.getOrNull()
        val type = message?.optString("type").orEmpty()

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
            "CHECK_ACCESS" -> send(
                "ACCESS_STATUS",
                JSONObject()
                    .put("isSubscribed", false)
                    .put("trialActive", false)
                    .put("source", "foundation_stub")
            )
            "START_PURCHASE", "RESTORE_PURCHASES", "START_SESSION" -> send(
                "ERROR",
                JSONObject().put("message", "$type is reserved for a later implementation step")
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
