package com.hackasol.scamshield.core.graph

/** One sender's history. Entities only, never message text. */
data class SenderRecord(val sender: String, val firstSeenMs: Long, val lastSeenMs: Long, val count: Int, val isDlt: Boolean)

enum class TrustStatus { TRUSTED, REPORTED }

enum class EntityKind { SENDER, NUMBER, UPI }

/** The user's verdict on one entity: "this was a scam" (REPORTED) or "this is safe" (TRUSTED, senders only). */
data class TrustRecord(val kind: EntityKind, val key: String, val status: TrustStatus, val tsMs: Long)

/** Entities of one flagged alert, so "This was a scam / safe" can mark them later. Never any message text. */
data class AlertRef(val tsMs: Long, val sender: String, val numbers: List<String>, val upiIds: List<String>)

/** Everything one ingested message added. Written through the store as it happens. Never written for an untrusted ingest. */
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
    /** Last-seen time per number / UPI id (a missing entry means "unknown": treated as now on restore). */
    val numberLastSeen: Map<String, Long> = emptyMap(),
    val upiLastSeen: Map<String, Long> = emptyMap(),
    val trust: List<TrustRecord> = emptyList(),
) {
    companion object { val EMPTY = GraphSnapshot(0, emptyList(), emptyList(), emptyList(), emptyList()) }
}

/** Persistence port for [KnowledgeGraph]; the SQLite implementation lives outside core. Implementations must not throw. */
interface GraphStore {
    fun load(): GraphSnapshot
    fun apply(delta: IngestDelta)
    /** Drop events, senders, numbers and UPI ids last seen before [cutoffMs], and alert refs older than it. */
    fun prune(cutoffMs: Long)
    /** Delete everything the store holds. False if the delete failed. */
    fun clear(): Boolean
    fun mark(kind: EntityKind, key: String, status: TrustStatus, tsMs: Long)
    fun putAlertRef(r: AlertRef)
    fun alertRef(tsMs: Long): AlertRef?

    companion object {
        /** [VERIFY] events older than this are dropped by prune; keeps the table bounded. */
        const val EVENT_RETENTION_MS = 90L * 24 * 60 * 60 * 1000
        /** [VERIFY] senders, numbers and UPI ids not seen for this long are forgotten. */
        const val ENTITY_RETENTION_MS = 90L * 24 * 60 * 60 * 1000
        /** Prune at most this often (checked on ingest). */
        const val PRUNE_INTERVAL_MS = 6L * 60 * 60 * 1000
    }
}
