package com.honoured.app.bridge

import org.json.JSONObject

/**
 * `capabilities` in `NATIVE_READY` / `PLATFORM_INFO`. The web app feature-
 * detects on these, never on `bridgeVersion` (Android stays at 1). Features
 * Android does not have yet are listed as unsupported, so the web can gate on
 * a capability instead of on the platform.
 */
object Capabilities {
    const val TRUSTED_TRANSPORT = "trusted-auth-v1"

    fun build(googleSignIn: JSONObject, sessionRefreshSupported: Boolean): JSONObject = JSONObject()
        .put("googleSignIn", googleSignIn)
        // One capability for the whole hand-off: native stores the session it is
        // given on the trusted transport AND is the only refresher. Storing a
        // refresh token without owning the refresh is what signed people out.
        .put(
            "sessionRefresh",
            JSONObject()
                .put("protocolVersion", 1)
                .put("supported", sessionRefreshSupported)
                .put("transport", TRUSTED_TRANSPORT),
        )
        // No Icon card on Android, so nothing can show a stale target or
        // signature: revisions are safe to offer (Phase 5 M2, D8).
        .put("iconRevisions", JSONObject().put("protocolVersion", 1).put("supported", true))
        .put("healthConnect", unsupported())
        .put("phoneSteps", unsupported())
        .put("backgroundTracking", unsupported())
        .put("notifications", unsupported())

    private fun unsupported() = JSONObject().put("protocolVersion", 1).put("supported", false)
}
