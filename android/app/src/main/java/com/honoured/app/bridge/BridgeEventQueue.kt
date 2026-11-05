package com.honoured.app.bridge

import org.json.JSONObject

/**
 * The in-memory half of the event queue (`docs/phase1/bridge.md`, "Event
 * queue"). Broadcasts raised while the page is not ready wait here, bounded
 * to the last [limit], and are flushed in order — merged by time with the
 * durable store — right after native replied to the first message the page
 * sends after a load. Confined to the main thread by its owner.
 */
class BridgeEventQueue(
    private val dispatch: (type: String, payload: JSONObject) -> Unit,
    private val drainStored: () -> List<StoredEvent>,
    private val limit: Int = NativeEventStore.LIMIT,
) {
    private data class Pending(val type: String, val payload: JSONObject, val createdAt: Long)

    private val pending = ArrayDeque<Pending>()

    var isWebReady: Boolean = false
        private set

    /** A main-frame navigation started: hold broadcasts until the new page speaks. */
    fun pageWillChange() {
        isWebReady = false
    }

    /** Sends now when the page is ready, otherwise queues. */
    fun broadcast(type: String, payload: JSONObject, createdAt: Long = System.currentTimeMillis()) {
        if (!isWebReady) {
            enqueue(Pending(type, payload, createdAt))
            return
        }
        dispatch(type, payload)
    }

    /**
     * The page sent a message, so its bridge module is running. Idempotent:
     * only the first message after a load flushes.
     */
    fun inboundMessageReceived() {
        if (isWebReady) return
        isWebReady = true
        val stored = runCatching(drainStored).getOrDefault(emptyList())
            .map { Pending(it.type, it.payload, it.createdAt) }
        val batch = (pending + stored).sortedBy { it.createdAt }
        pending.clear()
        batch.forEach { dispatch(it.type, it.payload) }
    }

    /** Sign-out or another account: nothing of the previous account may reach the next page. */
    fun clear() {
        pending.clear()
    }

    val pendingCount: Int get() = pending.size

    private fun enqueue(event: Pending) {
        if (pending.size >= limit) pending.removeFirst()
        pending.addLast(event)
    }
}
