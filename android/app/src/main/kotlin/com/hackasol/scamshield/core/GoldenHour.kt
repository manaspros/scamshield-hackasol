package com.hackasol.scamshield.core

/** 60-minute "golden hour" after money is lost; reporting fast improves the chance of a freeze. */
data class GoldenHour(val startMs: Long, val durationMs: Long = DURATION_MS) {
    fun remainingMs(nowMs: Long): Long = (startMs + durationMs - nowMs).coerceIn(0L, durationMs)
    fun expired(nowMs: Long): Boolean = nowMs >= startMs + durationMs

    companion object { const val DURATION_MS = 60L * 60 * 1000 }
}

/**
 * Case card: timer + pre-filled ReportPack. [graph] is an optional pre-serialised JSON value
 * (knowledge graph, not available yet); it is embedded verbatim, so callers must pass valid JSON.
 */
data class CaseCard(val goldenHour: GoldenHour, val pack: ReportPack, val graphJson: String? = null) {
    fun toJson(): String =
        "{\"golden_hour\":{\"start_ms\":${goldenHour.startMs},\"duration_ms\":${goldenHour.durationMs}}," +
            "\"report\":${pack.toJson()},\"graph\":${graphJson ?: "null"}}"

    companion object {
        /** Money-lost case, evidence pre-filled from the log; the timer starts at startMs. */
        fun fromLog(log: VerdictLog, startMs: Long, nowMs: Long, graphJson: String? = null): CaseCard =
            CaseCard(
                GoldenHour(startMs),
                ReportPack.build(log.since(nowMs - ReportPack.DEFAULT_WINDOW_MS), moneyLost = true, nowMs = nowMs),
                graphJson,
            )
    }
}
