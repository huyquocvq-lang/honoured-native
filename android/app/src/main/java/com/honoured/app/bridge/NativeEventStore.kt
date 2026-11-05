package com.honoured.app.bridge

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

/** A broadcast that must reach the page even after a relaunch. */
data class StoredEvent(val id: String, val type: String, val payload: JSONObject, val createdAt: Long)

/**
 * Durable, bounded, oldest-first event queue (`docs/phase1/bridge.md`, "Event
 * queue"), the Android twin of iOS `NativeEventStore`. Only events the person
 * would notice losing are kept, and never anything carrying a token: the file
 * is not encrypted. Cleared on sign-out and on a session for another person.
 * Blocking IO, serialised on one lock.
 */
class NativeEventStore(private val file: File, private val limit: Int = LIMIT) {
    private val lock = Any()
    private var events: MutableList<StoredEvent>? = null

    fun append(type: String, payload: JSONObject, createdAt: Long = System.currentTimeMillis()) = synchronized(lock) {
        require(type in DURABLE_TYPES) { "$type is not a durable event" }
        require(!containsSecret(payload)) { "Durable events never carry token material" }
        val next = loadLocked().toMutableList()
        next += StoredEvent(UUID.randomUUID().toString(), type, JSONObject(payload.toString()), createdAt)
        next.sortBy { it.createdAt }
        while (next.size > limit) next.removeAt(0)
        persist(next)
        events = next
    }

    /** Returns and removes everything, oldest first. */
    fun drain(): List<StoredEvent> = synchronized(lock) {
        val drained = loadLocked()
        if (drained.isEmpty()) return@synchronized emptyList()
        events = mutableListOf()
        // If the emptied file cannot be written the events are still handed
        // out: delivering twice after a relaunch beats never delivering.
        runCatching { persist(emptyList()) }
        drained
    }

    fun clear() = synchronized(lock) {
        events = mutableListOf()
        if (file.exists() && !file.delete()) throw IllegalStateException("Could not clear native events")
    }

    val size: Int get() = synchronized(lock) { loadLocked().size }

    private fun loadLocked(): List<StoredEvent> {
        events?.let { return it }
        val loaded = runCatching {
            val array = JSONArray(file.readText())
            (0 until array.length()).mapNotNull { i ->
                val o = array.optJSONObject(i) ?: return@mapNotNull null
                val type = o.optString("type").takeIf { it in DURABLE_TYPES } ?: return@mapNotNull null
                StoredEvent(o.optString("id"), type, o.optJSONObject("payload") ?: JSONObject(), o.optLong("createdAt"))
            }
        }.getOrDefault(emptyList())
        return loaded.toMutableList().also { events = it }
    }

    private fun persist(list: List<StoredEvent>) {
        val array = JSONArray()
        list.forEach {
            array.put(JSONObject().put("id", it.id).put("type", it.type).put("payload", it.payload).put("createdAt", it.createdAt))
        }
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeText(array.toString())
        if (!tmp.renameTo(file)) {
            tmp.delete()
            throw IllegalStateException("Could not persist native events")
        }
    }

    companion object {
        const val LIMIT = 50

        /** Events the person would notice losing (iOS keeps the same kind on disk). */
        val DURABLE_TYPES = setOf("NOTIFICATION_OPENED", "CONTRACT_LINK_OPENED", "GOAL_REACHED", "TIMER_COMPLETED")

        private val SECRET_KEYS = setOf("accesstoken", "refreshtoken", "access_token", "refresh_token", "idtoken", "session", "password")

        fun containsSecret(json: JSONObject): Boolean {
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                if (key.lowercase() in SECRET_KEYS) return true
                val value = json.opt(key)
                if (value is JSONObject && containsSecret(value)) return true
            }
            return false
        }
    }
}
