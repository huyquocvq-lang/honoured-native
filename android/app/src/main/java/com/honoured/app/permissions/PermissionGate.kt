package com.honoured.app.permissions

/**
 * One runtime-permission prompt at a time (Phase 5 M2, A5). The pure half of
 * [PermissionCoordinator]: the platform calls are injected, so the ordering
 * rules run in local unit tests.
 *
 * - A permission already granted answers at once without a prompt.
 * - While a prompt is showing, any other request is answered `false` at once:
 *   two system dialogs never stack and no caller waits on another's prompt.
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

    private var inFlight: Pair<String, (Boolean) -> Unit>? = null

    val isPrompting: Boolean get() = inFlight != null

    fun status(permission: String): Status = when {
        isGranted(permission) -> Status.GRANTED
        // Asked before, refused, and Android no longer explains why it would
        // ask: the person chose "Don't ask again" (or policy blocks it).
        wasRequested(permission) && !shouldShowRationale(permission) -> Status.BLOCKED
        else -> Status.CAN_ASK
    }

    fun request(permission: String, onResult: (Boolean) -> Unit) {
        if (isGranted(permission)) {
            onResult(true)
            return
        }
        if (inFlight != null) {
            onResult(false)
            return
        }
        inFlight = permission to onResult
        markRequested(permission)
        try {
            launch(permission)
        } catch (e: RuntimeException) {
            inFlight = null
            onResult(false)
        }
    }

    /** The system answered the prompt launched by [request]. */
    fun onSystemResult(granted: Boolean) {
        val (_, callback) = inFlight ?: return
        inFlight = null
        callback(granted)
    }

    /** The owner is going away: the pending caller hears `false`, once. */
    fun cancel() = onSystemResult(false)
}
