package com.honoured.app.auth

import java.net.URI
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicBoolean

/**
 * One Google presentation or cleanup at a time; a cleanup still running blocks
 * a new sign-in. Main thread only.
 */
class ProviderPresentationGate {
    enum class Holder { GOOGLE, GOOGLE_CLEANUP }

    var holder: Holder? = null
        private set
    private var token = 0

    fun acquire(holder: Holder): Int? {
        if (this.holder != null) return null
        this.holder = holder
        token += 1
        return token
    }

    /** Releases only the holder that owns [token]; a stale release is ignored. */
    fun release(token: Int) {
        if (token == this.token) holder = null
    }
}

object AuthNonce {
    private val random = SecureRandom()

    /** 32 random bytes as 64 hex characters, and the SHA-256 hex of that string. */
    fun make(): Pair<String, String> {
        val bytes = ByteArray(32).also(random::nextBytes)
        val raw = bytes.toHex()
        return raw to sha256Hex(raw)
    }

    fun sha256Hex(input: String): String =
        MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8)).toHex()

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}

/**
 * The exact origin (scheme, host, port) the auth transport trusts, derived from
 * the configured web app URL. HTTPS only, no wildcard, no suffix matching.
 */
class TrustedWebOrigin private constructor(val scheme: String, val host: String, val port: Int) {
    /** The rule for `WebViewCompat.addWebMessageListener`: exactly this origin. */
    val listenerRule: String
        get() = if (port == 443) "$scheme://$host" else "$scheme://$host:$port"

    fun matches(scheme: String?, host: String?, port: Int): Boolean {
        val s = scheme?.lowercase() ?: return false
        val h = host?.lowercase() ?: return false
        val resolvedPort = if (port <= 0) (if (s == "https") 443 else -1) else port
        return s == this.scheme && h == this.host && resolvedPort == this.port
    }

    fun matches(url: String?): Boolean {
        val uri = url?.let { runCatching { URI(it) }.getOrNull() } ?: return false
        return matches(uri.scheme, uri.host, uri.port)
    }

    companion object {
        fun from(url: String): TrustedWebOrigin? {
            val uri = runCatching { URI(url.trim()) }.getOrNull() ?: return null
            val scheme = uri.scheme?.lowercase()
            val host = uri.host?.lowercase()
            if (scheme != "https" || host.isNullOrEmpty()) return null
            return TrustedWebOrigin(scheme, host, if (uri.port <= 0) 443 else uri.port)
        }
    }
}

object GoogleClientConfig {
    private const val SUFFIX = ".apps.googleusercontent.com"

    /**
     * The Web application (server) client ID Google embeds as the ID token
     * audience. Null when missing or malformed, which turns the feature off.
     */
    fun serverClientId(raw: String): String? {
        val value = raw.trim()
        if (!value.endsWith(SUFFIX) || value.length <= SUFFIX.length) return null
        val prefix = value.dropLast(SUFFIX.length)
        return value.takeIf { prefix.all { it.isLetterOrDigit() || it == '-' } }
    }
}

/**
 * Runs callback-style operations strictly one after another in submission
 * order. RevenueCat identify/logout go through it, so a slow logout for the
 * previous account cannot land after the next account's sign-in. Thread-safe.
 */
class SerialCallbackQueue {
    private val lock = Any()
    private val pending = ArrayDeque<(done: () -> Unit) -> Unit>()
    private var running = false

    fun enqueue(operation: (done: () -> Unit) -> Unit) {
        synchronized(lock) {
            pending.addLast(operation)
            if (running) return
            running = true
        }
        runNext()
    }

    private fun runNext() {
        val next = synchronized(lock) {
            pending.pollFirst() ?: run {
                running = false
                null
            }
        } ?: return
        val finished = AtomicBoolean(false)
        next { if (finished.compareAndSet(false, true)) runNext() }
    }
}
