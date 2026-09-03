package com.honoured.app

import android.net.Uri

object AppConfig {
    const val BRIDGE_VERSION = 1
    const val REVENUECAT_ENTITLEMENT_ID = "honoured_plus"

    val WEB_APP_URL: String
        get() = BuildConfig.HONOURED_WEB_APP_URL.trim().also {
            require(it.isNotEmpty()) {
                "HONOURED_WEB_APP_URL is not configured. Copy android/local.properties.example to android/local.properties and set it."
            }
        }

    val WEB_APP_HOST: String
        get() = Uri.parse(WEB_APP_URL).host.orEmpty()
}
