package com.hackasol.scamshield.core.graph

enum class EventType { ORDER, BILL, CREDIT, DEBIT, REFUND, OUT_FOR_DELIVERY }

/** [amountRupees] is set on CREDIT / DEBIT / REFUND events (the message's amount), else null. */
data class GraphEvent(val brand: String, val type: EventType, val tsMs: Long, val sender: String, val amountRupees: Double? = null)

/**
 * In-memory entity store, fed only by messages seen since install. Stores extracted entities only, never raw text.
 * Events are recorded only from DLT-header senders, so a scammer's "credited" or "order placed" text cannot create one.
 * "Known" means "seen before", not "trusted": the caller passes `trusted = false` for a flagged message, which then
 * writes nothing at all: no sender, number, UPI id, event or cold-start count (poisoning guard).
 * With a [store] it loads on construction and writes through; without one it is purely in memory.
 */
open class KnowledgeGraph(private val store: GraphStore? = null, private val clock: () -> Long = System::currentTimeMillis) {
    private var ingested = 0
    private val senders = mutableMapOf<String, SenderRecord>()
    private val numbers = mutableMapOf<String, Long>()    // 10-digit number -> last seen
    private val upiIds = mutableMapOf<String, Long>()     // lowercase id -> last seen
    private val events = mutableListOf<GraphEvent>()
    private val trust = mutableMapOf<Pair<EntityKind, String>, TrustRecord>()
    private val alertRefs = mutableMapOf<Long, AlertRef>()
    private var lastPruneMs = 0L

    init {
        if (store != null) { restore(store.load()); prune(clock()) }   // retention also applies to what a restart loaded
        else lastPruneMs = clock()
    }

    private fun restore(s: GraphSnapshot) {
        ingested = s.ingested
        s.senders.forEach { senders[it.sender] = it }
        val fallback = System.currentTimeMillis()
        s.numbers.forEach { numbers[it] = s.numberLastSeen[it] ?: fallback }
        s.upiIds.forEach { upiIds[it] = s.upiLastSeen[it] ?: fallback }
        events += s.events
        s.trust.forEach { trust[it.kind to it.key] = it }
    }

    private fun norm(kind: EntityKind, raw: String): String = when (kind) {
        EntityKind.SENDER -> ClaimParsers.senderKey(raw)
        EntityKind.NUMBER -> ClaimParsers.numbers(raw).firstOrNull() ?: raw.trim()
        EntityKind.UPI -> raw.trim().lowercase()
    }

    @Synchronized
    fun ingest(message: String, sender: String, tsMs: Long, trusted: Boolean = true) {
        if (!trusted) return   // a flagged message writes nothing, not even the cold-start counter
        ingested++
        val s = sender.trim()
        val c = ClaimParsers.parse(message, s)
        val dlt = ClaimVsContext.isDltHeader(s)
        if (s.isNotEmpty()) {
            val old = senders[s]
            senders[s] = if (old == null) SenderRecord(s, tsMs, tsMs, 1, dlt)
            else old.copy(firstSeenMs = minOf(old.firstSeenMs, tsMs), lastSeenMs = maxOf(old.lastSeenMs, tsMs), count = old.count + 1)
        }
        val nums = (c.numbers + ClaimParsers.numbers(s)).distinct()
        nums.forEach { numbers[it] = maxOf(numbers[it] ?: 0L, tsMs) }
        c.upiIds.forEach { upiIds[it] = maxOf(upiIds[it] ?: 0L, tsMs) }
        // The header decides whose event it is: a text naming another brand ("HDFC credited" from VK-PROMOX) records nothing.
        val headerBrand = ClaimParsers.senderBrand(s)
        val textBrand = ClaimParsers.brandFromText(message)
        // shortcut: two names both missing from the brand table cannot be compared (header codes are abbreviations), so they pass; add the brand to Brands.ALL to get the check.
        val consistent = headerBrand != null && (textBrand == null || ClaimParsers.sameBrand(textBrand, headerBrand) ||
            !(Brands.isKnown(textBrand) || Brands.isKnown(headerBrand)))
        val brand = if (consistent) textBrand ?: headerBrand else null
        val withAmount = setOf(EventType.CREDIT, EventType.DEBIT, EventType.REFUND)
        val added = if (brand != null && dlt) {
            ClaimParsers.eventTypes(message)
                .map { GraphEvent(brand, it, tsMs, s, if (it in withAmount) c.amountRupees else null) }
                .filter { e -> events.none { it.brand == e.brand && it.type == e.type && it.sender == e.sender && it.tsMs == e.tsMs } }
        } else emptyList()
        events += added
        store?.apply(IngestDelta(s, tsMs, dlt, nums, c.upiIds, added))
        maybePrune()
    }

    // Wall clock, not the message time: a forged far-future timestamp must not trigger a prune or defer the next one.
    private fun maybePrune() {
        val nowMs = clock()
        if (nowMs - lastPruneMs >= GraphStore.PRUNE_INTERVAL_MS) prune(nowMs)
    }

    /** Forget events and entities older than the retention window. Trust marks and the cold-start counter are kept. */
    @Synchronized
    fun prune(nowMs: Long) {
        lastPruneMs = maxOf(lastPruneMs, nowMs)
        val eventCut = nowMs - GraphStore.EVENT_RETENTION_MS
        val entityCut = nowMs - GraphStore.ENTITY_RETENTION_MS
        events.removeAll { it.tsMs < eventCut }
        senders.values.removeAll { it.lastSeenMs < entityCut }
        numbers.values.removeAll { it < entityCut }
        upiIds.values.removeAll { it < entityCut }
        alertRefs.keys.removeAll { it < entityCut }
        store?.prune(entityCut)
    }

    /** "Delete my data": forgets everything, memory and store. False when the store could not delete (memory is cleared anyway). */
    @Synchronized
    fun clear(): Boolean {
        ingested = 0
        senders.clear(); numbers.clear(); upiIds.clear(); events.clear(); trust.clear(); alertRefs.clear()
        lastPruneMs = 0L
        return store?.clear() ?: true
    }

    @Synchronized
    fun snapshot(): GraphSnapshot = GraphSnapshot(
        ingested, senders.values.toList(), numbers.keys.toList(), upiIds.keys.toList(), events.toList(),
        numbers.toMap(), upiIds.toMap(), trust.values.toList(),
    )

    @Synchronized
    fun eventsFor(brand: String): List<GraphEvent> = events.filter { ClaimParsers.sameBrand(it.brand, brand) }

    fun hasEvent(brand: String, type: EventType, sinceMs: Long): Boolean =
        eventsFor(brand).any { it.type == type && it.tsMs >= sinceMs }

    @Synchronized
    fun hasAnyEvent(type: EventType, sinceMs: Long): Boolean = events.any { it.type == type && it.tsMs >= sinceMs }

    /** Events of [type] since [sinceMs], optionally only for [brand]. */
    @Synchronized
    fun recentEvents(type: EventType, sinceMs: Long, brand: String? = null): List<GraphEvent> =
        events.filter { it.type == type && it.tsMs >= sinceMs && (brand == null || ClaimParsers.sameBrand(it.brand, brand)) }

    @Synchronized fun knownSender(sender: String): Boolean = sender.trim() in senders
    @Synchronized fun knownNumber(number: String): Boolean = ClaimParsers.numbers(number).any { it in numbers }
    @Synchronized fun knownUpi(id: String): Boolean = id.trim().lowercase() in upiIds

    // ---- user trust / reports ----

    /** The user's latest choice wins: REPORTED replaces TRUSTED and the other way round. */
    @Synchronized
    fun mark(kind: EntityKind, key: String, status: TrustStatus, tsMs: Long) {
        val k = norm(kind, key)
        if (k.isEmpty()) return
        trust[kind to k] = TrustRecord(kind, k, status, tsMs)
        store?.mark(kind, k, status, tsMs)
    }

    @Synchronized
    fun isTrusted(sender: String): Boolean = trust[EntityKind.SENDER to norm(EntityKind.SENDER, sender)]?.status == TrustStatus.TRUSTED

    @Synchronized
    fun isReported(kind: EntityKind, key: String): Boolean = trust[kind to norm(kind, key)]?.status == TrustStatus.REPORTED

    /** True when the sender, or any number or UPI id the message names, was reported by the user. */
    fun reportedIn(sender: String, claims: Claims): Boolean =
        (sender.isNotBlank() && isReported(EntityKind.SENDER, sender)) ||
            claims.numbers.any { isReported(EntityKind.NUMBER, it) } ||
            claims.upiIds.any { isReported(EntityKind.UPI, it) }

    @Synchronized
    fun rememberAlert(r: AlertRef) {
        alertRefs[r.tsMs] = r
        store?.putAlertRef(r)
    }

    @Synchronized
    fun alertRef(tsMs: Long): AlertRef? = alertRefs[tsMs] ?: store?.alertRef(tsMs)

    /** "This was a scam" marks the alert's sender, numbers and UPI ids REPORTED; "safe" marks the sender TRUSTED. False if the alert is unknown. */
    @Synchronized
    fun feedback(tsMs: Long, scam: Boolean, nowMs: Long): Boolean {
        val r = alertRef(tsMs) ?: return false
        if (scam) {
            if (r.sender.isNotBlank()) mark(EntityKind.SENDER, r.sender, TrustStatus.REPORTED, nowMs)
            r.numbers.forEach { mark(EntityKind.NUMBER, it, TrustStatus.REPORTED, nowMs) }
            r.upiIds.forEach { mark(EntityKind.UPI, it, TrustStatus.REPORTED, nowMs) }
        } else if (r.sender.isNotBlank()) mark(EntityKind.SENDER, r.sender, TrustStatus.TRUSTED, nowMs)
        return true
    }

    @get:Synchronized val isEmpty: Boolean get() = ingested == 0

    /** Non-null when nothing has been ingested: callers must say this instead of claiming certainty. */
    val coldStartNote: String? get() = if (isEmpty) COLD_START_TEXT else null

    companion object {
        const val COLD_START_TEXT = "No record since ScamShield was installed"
    }
}

/** A [KnowledgeGraph] that loads from and writes through to a [GraphStore]. */
class PersistentKnowledgeGraph(store: GraphStore, clock: () -> Long = System::currentTimeMillis) : KnowledgeGraph(store, clock)
