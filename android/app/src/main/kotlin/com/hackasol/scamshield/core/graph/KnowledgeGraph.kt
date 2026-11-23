package com.hackasol.scamshield.core.graph

enum class EventType { ORDER, BILL, CREDIT, OUT_FOR_DELIVERY }

data class GraphEvent(val brand: String, val type: EventType, val tsMs: Long, val sender: String)

/**
 * In-memory entity store, fed only by messages seen since install. Stores extracted entities only, never raw text.
 * Events are recorded only from DLT-header senders, so a scammer's "credited" or "order placed" text cannot create one.
 * "Known" means "seen before", not "trusted": T5.3 decides what to ingest.
 * Persistence lives in [PersistentKnowledgeGraph]; this class keeps its original fields.
 */
open class KnowledgeGraph {
    private var ingested = 0
    private val senders = mutableSetOf<String>()
    private val brands = mutableSetOf<String>()
    private val numbers = mutableSetOf<String>()
    private val upiIds = mutableSetOf<String>()
    // shortcut: unbounded list, fine for one install-session; T5.3 persistence should prune.
    private val events = mutableListOf<GraphEvent>()

    @Synchronized
    fun ingest(message: String, sender: String, tsMs: Long) {
        ingested++
        val s = sender.trim()
        if (s.isNotEmpty()) senders += s
        val c = ClaimParsers.parse(message, s)
        c.brand?.let { brands += it }
        val nums = c.numbers + ClaimParsers.numbers(s)
        numbers += nums
        upiIds += c.upiIds
        val brand = c.brand
        val dlt = ClaimVsContext.isDltHeader(s)
        val added = if (brand != null && dlt) ClaimParsers.eventTypes(message).map { GraphEvent(brand, it, tsMs, s) } else emptyList()
        events += added
        onIngested(IngestDelta(s, tsMs, dlt, nums.distinct(), c.upiIds, added))
    }

    /** Hook for subclasses that persist; called under the graph lock after the in-memory update. */
    protected open fun onIngested(delta: IngestDelta) {}

    /** For subclasses: load a stored snapshot into the in-memory sets. */
    @Synchronized
    protected fun restore(s: GraphSnapshot) {
        ingested = s.ingested
        s.senders.mapTo(senders) { it.sender }
        numbers += s.numbers
        upiIds += s.upiIds
        events += s.events
    }

    @Synchronized
    fun eventsFor(brand: String): List<GraphEvent> {
        val b = ClaimParsers.normalizeBrand(brand)
        return events.filter { ClaimParsers.sameBrand(it.brand, b) }
    }

    fun hasEvent(brand: String, type: EventType, sinceMs: Long): Boolean =
        eventsFor(brand).any { it.type == type && it.tsMs >= sinceMs }

    @Synchronized
    fun hasAnyEvent(type: EventType, sinceMs: Long): Boolean = events.any { it.type == type && it.tsMs >= sinceMs }

    @Synchronized fun knownSender(sender: String): Boolean = sender.trim() in senders
    @Synchronized fun knownNumber(number: String): Boolean = ClaimParsers.numbers(number).any { it in numbers }
    @Synchronized fun knownUpi(id: String): Boolean = id.trim().lowercase() in upiIds

    @get:Synchronized val isEmpty: Boolean get() = ingested == 0

    /** Non-null when nothing has been ingested: callers must say this instead of claiming certainty. */
    val coldStartNote: String? get() = if (isEmpty) COLD_START_TEXT else null

    companion object {
        const val COLD_START_TEXT = "No record since ScamShield was installed"
    }
}

/** A [KnowledgeGraph] that loads from and writes through to a [GraphStore]. */
class PersistentKnowledgeGraph(private val store: GraphStore) : KnowledgeGraph() {
    init { restore(store.load()) }

    override fun onIngested(delta: IngestDelta) = store.apply(delta)
}
