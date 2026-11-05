package com.honoured.app.session

import org.json.JSONObject

/**
 * The signed-in person's Supabase session as native keeps it
 * (`docs/phase1/bridge.md`, "v2 — auth session"). Token material never
 * appears in [toString], logs, the event queue or a broadcast that is not a
 * direct reply on the trusted transport.
 */
class NativeAuthSession(
    val userId: String,
    val accessToken: String,
    val refreshToken: String,
    /** Unix seconds, exactly as Supabase reports `expires_at`. */
    val expiresAt: Double,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("userId", userId)
        .put("accessToken", accessToken)
        .put("refreshToken", refreshToken)
        .put("expiresAt", expiresAt)

    override fun equals(other: Any?): Boolean =
        other is NativeAuthSession &&
            other.userId == userId &&
            other.accessToken == accessToken &&
            other.refreshToken == refreshToken &&
            other.expiresAt == expiresAt

    override fun hashCode(): Int = listOf(userId, accessToken, refreshToken, expiresAt).hashCode()

    /** Never prints a token. */
    override fun toString(): String = "NativeAuthSession(userId=$userId, expiresAt=$expiresAt, tokens=<redacted>)"

    companion object {
        fun fromJson(json: JSONObject): NativeAuthSession? {
            val userId = json.opt("userId") as? String ?: return null
            val access = json.opt("accessToken") as? String ?: return null
            val refresh = json.opt("refreshToken") as? String ?: return null
            val expiresAt = (json.opt("expiresAt") as? Number)?.toDouble() ?: return null
            return validated(userId, access, refresh, expiresAt)
        }

        /** `SET_AUTH_SESSION` payload: the same checks iOS applies. */
        fun fromSetPayload(payload: JSONObject): NativeAuthSession? {
            val userId = payload.opt("userId") as? String ?: return null
            val access = payload.opt("accessToken") as? String ?: return null
            val refresh = payload.opt("refreshToken") as? String ?: return null
            val expiresAt = (payload.opt("expiresAt") as? Number)?.toDouble() ?: return null
            return validated(userId, access, refresh, expiresAt)
        }

        private fun validated(userId: String, access: String, refresh: String, expiresAt: Double): NativeAuthSession? {
            if (userId.isEmpty() || access.isEmpty() || refresh.isEmpty()) return null
            if (!expiresAt.isFinite() || expiresAt <= 0) return null
            return NativeAuthSession(userId, access, refresh, expiresAt)
        }
    }
}
