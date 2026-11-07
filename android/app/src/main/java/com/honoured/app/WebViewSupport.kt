package com.honoured.app

import android.content.Context
import androidx.webkit.WebViewCompat

/**
 * The web app is built for Chrome 111+ (Vite's `baseline-widely-available`
 * target). An older Android System WebView cannot even parse it and would
 * leave a black screen, so the shell checks the installed provider first and
 * asks for an update instead (Phase 5 M2, A5). Phones with Google Play keep
 * WebView current; this mostly catches old or Play-less devices.
 */
object WebViewSupport {
    const val MIN_MAJOR_VERSION = 111

    data class Provider(val packageName: String, val versionName: String, val major: Int?)

    fun provider(context: Context): Provider? {
        val info = runCatching { WebViewCompat.getCurrentWebViewPackage(context) }.getOrNull() ?: return null
        val versionName = info.versionName.orEmpty()
        return Provider(info.packageName, versionName, parseMajor(versionName))
    }

    /** True unless the installed WebView is known to be too old. Unknown counts as supported. */
    fun isSupported(context: Context): Boolean = isSupported(provider(context)?.major)

    fun isSupported(major: Int?): Boolean = major == null || major >= MIN_MAJOR_VERSION

    /** "124.0.6367.219" → 124; null when the name does not start with a number. */
    fun parseMajor(versionName: String?): Int? =
        versionName?.trim()?.takeWhile { it.isDigit() }?.takeIf { it.isNotEmpty() && it.length <= 6 }?.toIntOrNull()
}
