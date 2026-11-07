package com.honoured.app.session

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * `POST {supabaseUrl}/auth/v1/token?grant_type=refresh_token` with the anon
 * key, over `HttpURLConnection` (no extra HTTP dependency). The URL must be
 * HTTPS. Neither the request nor the response is ever logged.
 */
class HttpRefreshTransport(
    private val supabaseUrl: String,
    private val anonKey: String,
    private val clock: () -> Double = { System.currentTimeMillis() / 1000.0 },
) : RefreshTransport {

    val isConfigured: Boolean
        get() = anonKey.isNotBlank() && runCatching { URL(supabaseUrl.trim()).protocol == "https" }.getOrDefault(false)

    override suspend fun refresh(current: NativeAuthSession): SessionRefresher.RefreshResult = withContext(Dispatchers.IO) {
        if (!isConfigured) throw RefreshError.NotConfigured()
        val url = URL(supabaseUrl.trim().trimEnd('/') + "/auth/v1/token?grant_type=refresh_token")
        val connection = url.openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.doOutput = true
            connection.useCaches = false
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("apikey", anonKey)
            val body = JSONObject().put("refresh_token", current.refreshToken).toString()
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.use { it.readBytes().toString(Charsets.UTF_8) }.orEmpty()
            RefreshResponse.parse(current, status, text, clock())
        } finally {
            connection.disconnect()
        }
    }

    private companion object {
        // Worst case 25 s, inside the page's 30 s wait for REFRESH_AUTH_SESSION on
        // Android, so the page never gives up while native is still refreshing.
        const val CONNECT_TIMEOUT_MS = 10_000
        const val READ_TIMEOUT_MS = 15_000
    }
}
