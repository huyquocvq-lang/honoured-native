package com.honoured.app

import android.net.Uri

object AppConfig {
    const val BRIDGE_VERSION = 1

    /**
     * The RevenueCat entitlement the shell checks. Production is
     * `honoured_plus`; a developer build can point at its own entitlement with
     * REVENUECAT_ENTITLEMENT_ID in `.env` or `android/local.properties`, so
     * testing against a personal RevenueCat project never edits tracked
     * source. An unset value keeps the production identifier.
     */
    val REVENUECAT_ENTITLEMENT_ID: String
        get() = BuildConfig.REVENUECAT_ENTITLEMENT_ID.trim().ifEmpty { "honoured_plus" }

    val WEB_APP_URL: String
        get() = BuildConfig.HONOURED_WEB_APP_URL.trim().also {
            require(it.isNotEmpty()) {
                "HONOURED_WEB_APP_URL is not configured. Copy android/local.properties.example to android/local.properties and set it."
            }
        }

    /** Public Web application client ID (Google ID token audience). */
    val GOOGLE_WEB_CLIENT_ID: String
        get() = BuildConfig.GOOGLE_WEB_CLIENT_ID.trim()

    val WEB_APP_HOST: String
        get() = Uri.parse(WEB_APP_URL).host.orEmpty()
}
