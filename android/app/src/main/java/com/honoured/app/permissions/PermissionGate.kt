package com.honoured.app.permissions

/**
 * One runtime-permission prompt at a time (Phase 5 M2, A5). The pure half of
 * [PermissionCoordinator]: the platform calls are injected, so the ordering
 * rules run in local unit tests.
 *
 * - A permission already granted answers at once without a prompt.
 * - While a prompt is showing, any other request is answered [Outcome.BUSY] at
 *   once: two system dialogs never stack and no caller waits on another's
 *   prompt. BUSY is not a refusal and says nothing about the permission.
 * - A denied permission is not remembered as final here. Android itself stops
 *   showing the dialog after "Don't ask again" and answers `false` at once, so
 *   asking again costs nothing; [status] reports [Status.BLOCKED] so a caller
 *   can offer the app's Settings page instead.
 */
class PermissionGate(
    private val isGranted: (String) -> Boolean,
    private val shouldShowRationale: (String) -> Boolean,
    private val wasRequested: (String) -> Boolean,
    private val markRequested: (String) -> Unit,
    private val launch: (String) -> Unit,
) {
    enum class Status { GRANTED, CAN_ASK, BLOCKED }

    /** What one [request] ended with. */
    enum class Outcome {
        GRANTED,
        /** Refused (or the prompt was dismissed, which Android reports the same way). */
        DENIED,
        /** Another prompt was showing; nothing was asked. */
        BUSY,
    }

    private var inFlight: Pair<String, (Outcome) -> Unit>? = null

    val isPrompting: Boolean get() = inFlight != null

    fun status(permission: String): Status = when {
        isGranted(permission) -> Status.GRANTED
        // Asked before, refused, and Android no longer explains why it would
        // ask: the person chose "Don't ask again" (or policy blocks it).
        wasRequested(permission) && !shouldShowRationale(permission) -> Status.BLOCKED
        else -> Status.CAN_ASK
    }

    fun request(permission: String, onResult: (Outcome) -> Unit) {
        if (isGranted(permission)) {
            onResult(Outcome.GRANTED)
            return
        }
        if (inFlight != null) {
            onResult(Outcome.BUSY)
            return
        }
        inFlight = permission to onResult
        markRequested(permission)
        try {
            launch(permission)
        } catch (e: RuntimeException) {
            inFlight = null
            onResult(Outcome.DENIED)
        }
    }

    /** The system answered the prompt launched by [request]. */
    fun onSystemResult(granted: Boolean) {
        val (_, callback) = inFlight ?: return
        inFlight = null
        callback(if (granted) Outcome.GRANTED else Outcome.DENIED)
    }

    /** The owner is going away: the pending caller hears DENIED, once. */
    fun cancel() = onSystemResult(false)
}
