package com.honoured.app.session

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.io.IOException

/**
 * Supabase rotates the refresh token on every use, and a refresh with a token
 * that was already used revokes the whole session ("refresh token reuse").
 * The page and native share one session, so two refreshers holding copies of
 * the same token sign the person out (iOS, Oct 2–6). Inside the app native is
 * the only refresher: the page hands every refresh over
 * (`REFRESH_AUTH_SESSION`, `docs/phase1/bridge.md`, "Session refresh"), and
 * each token is refreshed once however many callers ask at the same time.
 * Mirrors `AuthSessionStore.refreshForWeb` / `RefreshCoalescer` on iOS.
 */
class SessionRefresher(
    private val store: SessionStore,
    private val transport: RefreshTransport,
    /** Outlives any caller, so a cancelled caller never cancels a shared refresh. */
    private val scope: CoroutineScope,
) {
    sealed class WebOutcome {
        /** Supabase's token response, already stored. Handed to the page unchanged. */
        class Refreshed(val response: JSONObject) : WebOutcome() {
            /** The response carries tokens: never print it. */
            override fun toString(): String = "Refreshed(<redacted>)"
        }
        /** The page refreshes for itself, as it would outside the app. */
        data class Declined(val reason: String) : WebOutcome()
        /** Offline or a server error: retry later. Never answered with the page's own token. */
        data object Failed : WebOutcome()
    }

    class RefreshResult(val session: NativeAuthSession, val response: JSONObject)

    private val lock = Mutex()
    private var running: Pair<String, Deferred<RefreshResult>>? = null

    /**
     * The last finished refresh, keyed by the refresh token it spent. A caller
     * that read the session just before that refresh stored its result gets
     * the same result instead of spending the old token a second time.
     */
    private var lastCompleted: Pair<String, RefreshResult>? = null

    /** A refresh the page handed over. Blocking IO: call on an IO dispatcher. */
    suspend fun refreshForWeb(userId: String): WebOutcome {
        val current = store.load()
        WebRefreshPolicy.decide(current?.userId, userId)?.let { return WebOutcome.Declined(it) }
        current ?: return WebOutcome.Declined(WebRefreshPolicy.NO_SESSION)
        return try {
            WebOutcome.Refreshed(refresh(current).response)
        } catch (e: RefreshError.InvalidSession) {
            // Native's copy is dead; the page may hold a newer sign-in.
            WebOutcome.Declined("invalid_session")
        } catch (e: RefreshError.Superseded) {
            WebOutcome.Declined("superseded")
        } catch (e: RefreshError.NotConfigured) {
            WebOutcome.Declined("not_configured")
        } catch (e: Exception) {
            WebOutcome.Failed
        }
    }

    /**
     * The stored session, refreshed first when it expires within a minute
     * (or always with [force]). For native work while the page is not running
     * (M4 background sync). Null when nothing is stored.
     */
    suspend fun refreshedSessionIfNeeded(nowSeconds: Double, force: Boolean = false): NativeAuthSession? {
        val current = store.load() ?: return null
        if (!force && current.expiresAt > nowSeconds + 60) return current
        return refresh(current).session
    }

    /**
     * Refreshes [current] once, however many callers ask meanwhile, and stores
     * the result. Like the iOS actor, "spend the token, store the result" is
     * one step: it runs inside the shared task, so every caller of one refresh
     * sees the same outcome and none of them can start a second refresh on the
     * token the first one just spent.
     */
    private suspend fun refresh(current: NativeAuthSession): RefreshResult {
        val task = lock.withLock {
            lastCompleted?.takeIf { it.first == current.refreshToken }?.let { return it.second }
            running?.takeIf { it.first == current.refreshToken }?.second
                ?: scope.async {
                    val result = transport.refresh(current)
                    // The page may have signed out, switched account or stored a
                    // newer session while the request was in flight: only the
                    // session this refresh started from may be replaced.
                    if (!store.replaceIf(current, result.session)) throw RefreshError.Superseded()
                    lock.withLock { lastCompleted = current.refreshToken to result }
                    result
                }.also { running = current.refreshToken to it }
        }
        try {
            return task.await()
        } finally {
            lock.withLock { if (running?.second === task) running = null }
        }
    }

    /** Sign-out or another account: nothing of the previous session may be handed out again. */
    suspend fun forget() = lock.withLock { lastCompleted = null }
}

/** What native does with a refresh the page hands over. Same rules as iOS `WebRefreshPolicy`. */
object WebRefreshPolicy {
    const val NO_SESSION = "no_session"
    const val OTHER_USER = "other_user"

    /** Null = refresh native's copy; otherwise the decline reason. */
    fun decide(storedUserId: String?, requestUserId: String): String? = when {
        storedUserId == null -> NO_SESSION
        storedUserId != requestUserId -> OTHER_USER
        else -> null
    }
}

sealed class RefreshError(message: String) : Exception(message) {
    class NotConfigured : RefreshError("Supabase native session is not configured")
    class InvalidResponse : RefreshError("Supabase returned an invalid auth response")
    class InvalidSession : RefreshError("The Supabase session is no longer valid")
    class Superseded : RefreshError("The Supabase session changed while it was being refreshed")
    class Http(val code: Int) : RefreshError("Supabase auth refresh failed with HTTP $code")
}

/** One refresh-token grant against Supabase. */
fun interface RefreshTransport {
    /** Throws [RefreshError] or [IOException]; never logs the body or tokens. */
    suspend fun refresh(current: NativeAuthSession): SessionRefresher.RefreshResult
}

/** Parses Supabase's token response for [current]'s user. Shared by the real transport and tests. */
object RefreshResponse {
    fun parse(current: NativeAuthSession, status: Int, body: String, nowSeconds: Double): SessionRefresher.RefreshResult {
        if (status !in 200..299) {
            if (status == 400 || status == 401) throw RefreshError.InvalidSession()
            throw RefreshError.Http(status)
        }
        val json = runCatching { JSONObject(body) }.getOrNull() ?: throw RefreshError.InvalidResponse()
        val access = json.opt("access_token") as? String
        val refresh = json.opt("refresh_token") as? String
        val userId = json.optJSONObject("user")?.opt("id") as? String
        if (access.isNullOrEmpty() || refresh.isNullOrEmpty() || userId.isNullOrEmpty()) throw RefreshError.InvalidResponse()
        if (userId != current.userId) throw RefreshError.InvalidSession()
        val expiresAt = (json.opt("expires_at") as? Number)?.toDouble()
            ?: (json.opt("expires_in") as? Number)?.toDouble()?.let { nowSeconds + it }
            ?: throw RefreshError.InvalidResponse()
        if (!expiresAt.isFinite() || expiresAt <= 0) throw RefreshError.InvalidResponse()
        return SessionRefresher.RefreshResult(NativeAuthSession(userId, access, refresh, expiresAt), json)
    }
}
