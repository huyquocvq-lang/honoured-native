package com.honoured.app.session

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch

/**
 * Runs suspend blocks strictly one after another, in the order they were
 * enqueued (iOS `authMutations`). Sign-in, sign-out and account switches go
 * through it, so a slow clear for the previous account can never land after
 * the next account's session was stored. A failing block does not stop the
 * queue.
 */
class SerialMutationQueue(scope: CoroutineScope) {
    private val jobs = Channel<suspend () -> Unit>(Channel.UNLIMITED)

    init {
        scope.launch {
            for (job in jobs) {
                runCatching { job() }
            }
        }
    }

    fun enqueue(block: suspend () -> Unit) {
        jobs.trySend(block)
    }
}

/**
 * Everything native keeps per account registers a clear here: the durable
 * event queue now, health/timer/push state in M3–M5. A sign-out or a session
 * for another person runs every clear before the new state is stored.
 */
class AccountScopedRegistry {
    private val lock = Any()
    private val clearers = linkedMapOf<String, suspend () -> Unit>()

    fun register(name: String, clear: suspend () -> Unit) = synchronized(lock) { clearers[name] = clear }

    fun unregister(name: String) = synchronized(lock) { clearers.remove(name) }

    /** Runs every clear in registration order; the first failure is rethrown after all have run. */
    suspend fun clearAll() {
        val all = synchronized(lock) { clearers.values.toList() }
        var first: Throwable? = null
        for (clear in all) {
            try {
                clear()
            } catch (e: Throwable) {
                if (first == null) first = e
            }
        }
        first?.let { throw it }
    }
}
