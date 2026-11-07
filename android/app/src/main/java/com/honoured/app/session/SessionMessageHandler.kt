package com.honoured.app.session

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * `SET_AUTH_SESSION`, `CLEAR_AUTH_SESSION` and `REFRESH_AUTH_SESSION`
 * (`docs/phase1/bridge.md`, "v2 — auth session" and "Session refresh"). Only
 * the trusted `HonouredAuth` transport may call [handle]; the legacy
 * `HonouredNative` interface refuses these types without reading them.
 *
 * [reply] may be called from any thread and must deliver only to the
 * document that asked. Replies carry tokens only for `AUTH_SESSION_REFRESHED`,
 * and nothing here is queued, stored outside [SessionStore] or logged.
 */
class SessionMessageHandler(
    private val store: SessionStore,
    private val refresher: SessionRefresher,
    private val mutations: SerialMutationQueue,
    private val registry: AccountScopedRegistry,
    private val scope: CoroutineScope,
    /** Synchronous, before any await: a different owner invalidates a Google attempt. */
    private val onOwnerChanged: (String?) -> Unit,
) {
    fun handle(type: String, payload: JSONObject, reply: (String, JSONObject) -> Unit) {
        when (type) {
            SET -> set(payload, reply)
            CLEAR -> clear(reply)
            REFRESH -> refresh(payload, reply)
            else -> reply("ERROR", error("unsupported_message", "Unsupported auth message: $type"))
        }
    }

    private fun set(payload: JSONObject, reply: (String, JSONObject) -> Unit) {
        val session = NativeAuthSession.fromSetPayload(payload)
            ?: return reply("ERROR", error("invalid_auth_session", "Invalid auth session"))
        onOwnerChanged(session.userId)
        mutations.enqueue {
            var switching = false
            try {
                val stored = store.load()
                // The previous owner is unknown when the stored copy could not be read.
                switching = (stored != null && stored.userId != session.userId) || store.lastReadWasUnreadable
                if (switching) {
                    // First, so a failure further on cannot leave the previous
                    // account's state for the next one.
                    refresher.forget()
                    registry.clearAll()
                }
                if (SessionFreshness.keepStored(stored, session)) {
                    // Same person, and native already holds a later session (it
                    // refreshed, and the reply never reached this page). Storing
                    // the older one would make native spend a rotated token.
                    reply(ACCEPTED, JSONObject().put("userId", session.userId))
                    return@enqueue
                }
                store.save(session)
                reply(ACCEPTED, JSONObject().put("userId", session.userId))
            } catch (e: Exception) {
                // Never leave the previous account's session behind a failed switch.
                if (switching) runCatching { store.clear() }
                reply("ERROR", error("auth_session_store_failed", "The session could not be stored"))
            }
        }
    }

    private fun clear(reply: (String, JSONObject) -> Unit) {
        onOwnerChanged(null)
        mutations.enqueue {
            try {
                refresher.forget()
                store.clear()
                registry.clearAll()
                reply(CLEARED, JSONObject())
            } catch (e: Exception) {
                reply("ERROR", error("auth_session_clear_failed", "The session could not be cleared"))
            }
        }
    }

    private fun refresh(payload: JSONObject, reply: (String, JSONObject) -> Unit) {
        val userId = (payload.opt("userId") as? String)?.takeIf { it.isNotEmpty() }
            ?: return reply("ERROR", error("invalid_refresh_request", "userId must be a non-empty string"))
        // Not behind the mutation queue: a refresh must not wait for a clear,
        // and the store refuses to save over a session that changed.
        scope.launch {
            when (val outcome = refresher.refreshForWeb(userId)) {
                is SessionRefresher.WebOutcome.Refreshed -> reply(REFRESHED, JSONObject().put("session", outcome.response))
                is SessionRefresher.WebOutcome.Declined -> reply(DECLINED, JSONObject().put("reason", outcome.reason))
                SessionRefresher.WebOutcome.Failed -> reply("ERROR", error("auth_refresh_failed", "The session could not be refreshed right now"))
            }
        }
    }

    private fun error(code: String, message: String) = JSONObject().put("code", code).put("message", message)

    companion object {
        const val SET = "SET_AUTH_SESSION"
        const val CLEAR = "CLEAR_AUTH_SESSION"
        const val REFRESH = "REFRESH_AUTH_SESSION"
        const val ACCEPTED = "AUTH_SESSION_ACCEPTED"
        const val CLEARED = "AUTH_SESSION_CLEARED"
        const val REFRESHED = "AUTH_SESSION_REFRESHED"
        const val DECLINED = "AUTH_REFRESH_DECLINED"

        /** Token-carrying messages: trusted transport only. */
        val MESSAGE_TYPES = setOf(SET, CLEAR, REFRESH)
    }
}

/** Which of two sessions of the same person is the later one. */
object SessionFreshness {
    /**
     * True when [stored] belongs to the same user as [incoming], carries a
     * different refresh token and expires later: it was issued after the
     * incoming one, so the incoming one is stale. Supabase sets expires_at at
     * issue time, so a later expiry means a later session.
     */
    fun keepStored(stored: NativeAuthSession?, incoming: NativeAuthSession): Boolean =
        stored != null &&
            stored.userId == incoming.userId &&
            stored.refreshToken != incoming.refreshToken &&
            stored.expiresAt > incoming.expiresAt
}
