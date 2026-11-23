package com.hackasol.scamshield.core

/** One logged verdict. Deliberately has no raw message text field. */
data class VerdictEvent(
    val id: Long,
    val tsMs: Long,
    val source: Source,
    val label: Label,
    val confidence: Double,
    val scamType: ScamType?,
    val triggers: List<String>,
    val engine: String,
)

interface VerdictLog {
    fun append(e: VerdictEvent)
    fun since(tsMs: Long): List<VerdictEvent>
    fun latest(): VerdictEvent?
    fun countsByType(): Map<ScamType, Int>
    /** Delete every event of THIS log only (the real log; the Demo Lab keeps its own separate in-memory log). */
    fun clear()
}

class InMemoryVerdictLog : VerdictLog {
    private val events = ArrayList<VerdictEvent>()

    @Synchronized override fun append(e: VerdictEvent) { events.add(e) }

    /** Events with tsMs >= the argument, oldest first. */
    @Synchronized override fun since(tsMs: Long): List<VerdictEvent> =
        events.filter { it.tsMs >= tsMs }.sortedBy { it.tsMs }

    @Synchronized override fun latest(): VerdictEvent? = events.asReversed().maxByOrNull { it.tsMs }  // reversed: on a ts tie the last appended wins, like Sqlite (ts DESC, id DESC)

    @Synchronized override fun clear() { events.clear() }

    /** Events with a null scamType are not counted. */
    @Synchronized override fun countsByType(): Map<ScamType, Int> =
        events.mapNotNull { it.scamType }.groupingBy { it }.eachCount()
}

/** Minimal JSON string quoting shared by the hand-written serialisers in core/ (no org.json on the test classpath). */
internal fun jsonQuote(s: String): String {
    val sb = StringBuilder("\"")
    for (c in s) when {
        c == '"' -> sb.append("\\\"")
        c == '\\' -> sb.append("\\\\")
        c == '\n' -> sb.append("\\n")
        c == '\r' -> sb.append("\\r")
        c == '\t' -> sb.append("\\t")
        c < ' ' -> sb.append("\\u%04x".format(c.code))
        else -> sb.append(c)
    }
    return sb.append('"').toString()
}
