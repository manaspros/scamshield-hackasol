package com.hackasol.scamshield.core.graph

/** One sender's history. Entities only, never message text. */
data class SenderRecord(val sender: String, val firstSeenMs: Long, val lastSeenMs: Long, val count: Int, val isDlt: Boolean)

/** Everything one ingested message added. Written through the store as it happens. */
data class IngestDelta(
    val sender: String,           // trimmed; may be blank
    val tsMs: Long,
    val isDlt: Boolean,
    val numbers: List<String>,
    val upiIds: List<String>,
    val events: List<GraphEvent>,
)

data class GraphSnapshot(
    val ingested: Int,
    val senders: List<SenderRecord>,
    val numbers: List<String>,
    val upiIds: List<String>,
    val events: List<GraphEvent>,
) {
    companion object { val EMPTY = GraphSnapshot(0, emptyList(), emptyList(), emptyList(), emptyList()) }
}

/** Persistence port for [KnowledgeGraph]; the SQLite implementation lives outside core. Implementations must not throw. */
interface GraphStore {
    fun load(): GraphSnapshot
    fun apply(delta: IngestDelta)

    companion object {
        /** [VERIFY] events older than this are dropped on load; keeps the table bounded. */
        const val EVENT_RETENTION_MS = 90L * 24 * 60 * 60 * 1000
    }
}
