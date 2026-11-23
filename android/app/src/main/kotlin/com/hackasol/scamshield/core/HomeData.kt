package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.graph.ClaimVsContext
import com.hackasol.scamshield.core.graph.GraphSnapshot
import com.hackasol.scamshield.core.graph.SenderRecord

/**
 * Home-screen queries (pure, JVM-testable). Both read stored entities only: neither the graph nor the
 * verdict log holds raw message text, so nothing here can expose any.
 */
object GraphSummary {
    private val LONG_DIGITS = Regex("\\d{6}")

    /** Only a brand-style DLT header (AX-HDFCBK) may be shown by name; phone numbers, UPI ids and anything else are counted. */
    internal fun showable(sender: String) = ClaimVsContext.isDltHeader(sender) && !LONG_DIGITS.containsMatchIn(sender)

    const val RECENT_LIMIT = 20
    const val SENDER_LIMIT = 12

    /**
     * Channel-shaped summary of a graph snapshot. Phone numbers and UPI ids are reported as counts only.
     * The Demo Lab never writes to graph.db (it runs on its own in-memory graph), so no demo events can appear.
     */
    fun build(s: GraphSnapshot): Map<String, Any?> {
        val (named, personal) = s.senders.partition { showable(it.sender) }
        val brands = s.events.groupBy { it.brand }.map { (brand, ev) ->
            mapOf(
                "brand" to brand,
                "count" to ev.size,
                "lastMs" to ev.maxOf { it.tsMs },
                "types" to ev.groupingBy { it.type.name }.eachCount(),
            )
        }.sortedByDescending { it["lastMs"] as Long }
        return mapOf(
            "empty" to (s.ingested == 0),
            "ingested" to s.ingested,
            "brands" to brands,
            "recent" to s.events.sortedByDescending { it.tsMs }.take(RECENT_LIMIT)
                .map { mapOf("brand" to it.brand, "type" to it.type.name, "tsMs" to it.tsMs) },
            "senders" to named.sortedWith(compareByDescending<SenderRecord> { it.count }.thenByDescending { it.lastSeenMs }).take(SENDER_LIMIT)
                .map { mapOf("sender" to it.sender, "count" to it.count, "firstMs" to it.firstSeenMs, "lastMs" to it.lastSeenMs, "dlt" to it.isDlt) },
            "personalSenders" to personal.size,
            "personalMessages" to personal.sumOf { it.count },
            "numbers" to s.numbers.size,
            "upiIds" to s.upiIds.size,
        )
    }
}

/** "Make evidence": which flagged events go into the pack, and the case card that wraps them. */
object EvidenceMake {
    /** One event by [id] (any age), else every non-SAFE event of the last 24 h; oldest first. */
    fun select(all: List<VerdictEvent>, id: Long?, nowMs: Long): List<VerdictEvent> =
        (if (id != null) all.filter { it.id == id } else all.filter { it.tsMs in (nowMs - ReportPack.DEFAULT_WINDOW_MS)..nowMs })
            .filter { it.label != Label.SAFE }
            .sortedBy { it.tsMs }

    /** Card for [events]; the golden-hour clock field just records when the pack was made. */
    fun card(events: List<VerdictEvent>, nowMs: Long): CaseCard =
        CaseCard(GoldenHour(nowMs), ReportPack.build(events, moneyLost = false, nowMs = nowMs, windowMs = Long.MAX_VALUE / 2))
}
