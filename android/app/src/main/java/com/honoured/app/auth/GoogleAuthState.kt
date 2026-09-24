package com.honoured.app.auth

import java.util.UUID

/** What the web app asked Google Sign-In for. */
enum class GoogleSignInIntent(val wire: String) {
    SIGN_IN("sign_in"),
    LINK("link");

    companion object {
        fun from(value: String?): GoogleSignInIntent? = entries.firstOrNull { it.wire == value }
    }
}

/**
 * A failure reported as `GOOGLE_SIGN_IN_FAILED`. Messages are written here,
 * never copied from an exception that could carry token material.
 */
data class GoogleAuthFailure(val code: String, val message: String) {
    companion object {
        val CANCELLED = GoogleAuthFailure("cancelled", "Google sign-in was cancelled.")
        val IN_PROGRESS = GoogleAuthFailure("in_progress", "Another sign-in is already in progress.")
        val NOT_CONFIGURED = GoogleAuthFailure("not_configured", "Google sign-in is not configured in this build.")
        val UNSUPPORTED = GoogleAuthFailure("unsupported", "Google sign-in is not available on this device.")
        val STALE_CONTEXT = GoogleAuthFailure("stale_context", "The sign-in request no longer matches this page. Try again.")
        val NO_CREDENTIAL = GoogleAuthFailure("no_credential", "No Google account is available on this device.")
        val NETWORK = GoogleAuthFailure("network_error", "Google could not be reached. Check your connection and try again.")
        val PROVIDER = GoogleAuthFailure("provider_error", "Google sign-in failed. Try again.")
        val TIMEOUT = GoogleAuthFailure("timeout", "Google sign-in took too long. Try again.")

        fun invalidPayload(message: String) = GoogleAuthFailure("invalid_payload", message)
    }
}

/** Which document and owner a Google request belongs to. Memory only, no token. */
data class GoogleAuthContext(val id: String, val userId: String?, val documentGeneration: Int)

/** One Google presentation, bound to the page, context, intent and request. */
data class GoogleAuthAttempt(
    val requestId: String,
    val contextId: String,
    val intent: GoogleSignInIntent,
    val documentGeneration: Int,
    val rawNonce: String,
)

sealed class BeginResult {
    data class Started(val attempt: GoogleAuthAttempt) : BeginResult()
    data class Rejected(val failure: GoogleAuthFailure) : BeginResult()
}

/**
 * Ownership rules for Google Sign-In, free of Android and Google types so they
 * run as plain JVM tests. Same rules as the iOS `GoogleAuthState`:
 *
 * - A new page, a different owner or an explicit clear replaces the context
 *   and invalidates every attempt of the old one.
 * - An attempt yields at most one result, and only while it is still the
 *   current attempt of the current context on the same page.
 *
 * Confined to the main thread by its owner.
 */
class GoogleAuthState(private val makeId: () -> String = { UUID.randomUUID().toString() }) {
    var documentGeneration = 0
        private set
    var context: GoogleAuthContext? = null
        private set
    var attempt: GoogleAuthAttempt? = null
        private set
    private val usedRequestIds = mutableSetOf<String>()

    /** A main-frame navigation started: the old document can no longer receive a credential. */
    fun documentWillChange() {
        documentGeneration += 1
        context = null
        attempt = null
        usedRequestIds.clear()
    }

    /** `SYNC_AUTH_CONTEXT`. Idempotent for the same user on the same page. */
    fun sync(userId: String?): GoogleAuthContext {
        val normalized = userId?.takeIf { it.isNotEmpty() }
        context?.let {
            if (it.userId == normalized && it.documentGeneration == documentGeneration) return it
        }
        return replaceContext(normalized)
    }

    /** `CLEAR_GOOGLE_SIGN_IN`: invalidate now, hand back a fresh signed-out context. */
    fun clear(): GoogleAuthContext = replaceContext(null)

    private fun replaceContext(userId: String?): GoogleAuthContext {
        attempt = null
        usedRequestIds.clear()
        return GoogleAuthContext(makeId(), userId, documentGeneration).also { context = it }
    }

    fun begin(requestId: String?, intent: String?, contextId: String?, rawNonce: String): BeginResult {
        if (requestId.isNullOrEmpty()) return BeginResult.Rejected(GoogleAuthFailure.invalidPayload("requestId is required."))
        val parsedIntent = GoogleSignInIntent.from(intent)
            ?: return BeginResult.Rejected(GoogleAuthFailure.invalidPayload("intent must be sign_in or link."))
        if (contextId.isNullOrEmpty()) return BeginResult.Rejected(GoogleAuthFailure.invalidPayload("authContextId is required."))
        val current = context
        if (current == null || current.id != contextId || current.documentGeneration != documentGeneration) {
            return BeginResult.Rejected(GoogleAuthFailure.STALE_CONTEXT)
        }
        if (requestId in usedRequestIds) {
            return BeginResult.Rejected(GoogleAuthFailure.invalidPayload("This requestId was already used."))
        }
        if (parsedIntent == GoogleSignInIntent.SIGN_IN && current.userId != null) {
            return BeginResult.Rejected(GoogleAuthFailure.invalidPayload("sign_in needs a signed-out context."))
        }
        if (parsedIntent == GoogleSignInIntent.LINK && current.userId == null) {
            return BeginResult.Rejected(GoogleAuthFailure.invalidPayload("link needs a signed-in context."))
        }
        if (attempt != null) return BeginResult.Rejected(GoogleAuthFailure.IN_PROGRESS)
        usedRequestIds += requestId
        val started = GoogleAuthAttempt(requestId, contextId, parsedIntent, documentGeneration, rawNonce)
        attempt = started
        return BeginResult.Started(started)
    }

    fun isCurrent(candidate: GoogleAuthAttempt): Boolean =
        attempt == candidate &&
            context?.id == candidate.contextId &&
            candidate.documentGeneration == documentGeneration

    /** Consumes the attempt once if still current; null means drop the result. */
    fun finish(candidate: GoogleAuthAttempt): GoogleAuthAttempt? {
        if (!isCurrent(candidate)) return null
        attempt = null
        return candidate
    }

    /** `CANCEL_GOOGLE_SIGN_IN`: returns the cancelled attempt so it is answered once. */
    fun cancel(contextId: String?, targetRequestId: String?): GoogleAuthAttempt? {
        val current = attempt ?: return null
        if (context?.id != contextId || current.contextId != contextId || current.requestId != targetRequestId) return null
        attempt = null
        return current
    }
}
