package com.hackasol.scamshield.core

/** One speech-to-text chunk of a recorded call. Reused by the STT engine (T2.6). */
data class SttSegment(val text: String, val startMs: Long)

data class StatementResult(val startMs: Long, val verdict: Verdict, val shown: Label)

data class CallReport(
    val overall: Label,
    val risk: Double,
    val perStatement: List<StatementResult>,
    val topTriggers: List<String>,
)

/**
 * Offline pipeline for a recorded call: STT segments -> [StatementSegmenter] -> [classify]
 * (always called with [Source.RECORDING]) -> [CallRiskTracker] -> [CallReport].
 *
 * Segments are appended to a growing transcript and fed as one caption snapshot, which is the
 * input shape the segmenter's overlap logic expects (it would drop repeated leading words if
 * fed disjoint chunks).
 */
class RecordingPipeline(
    private val classify: (text: String, source: Source) -> Verdict,
    private val segmenter: StatementSegmenter = StatementSegmenter(),
    // Recorded calls can have long silent gaps; never auto-expire the risk state.
    private val tracker: CallRiskTracker = CallRiskTracker(resetAfterMs = Long.MAX_VALUE),
    private val maxTriggers: Int = 5,
) {
    private val transcript = StringBuilder()
    private val results = mutableListOf<StatementResult>()
    private var lastMs = 0L

    /** Feed segments in order; returns the statements completed by this segment. */
    fun onSegment(seg: SttSegment): List<StatementResult> {
        val flushed = process(segmenter.onTick(seg.startMs), seg.startMs)
        if (seg.text.isBlank()) return flushed
        if (transcript.isNotEmpty()) transcript.append(' ')
        transcript.append(seg.text.trim())
        lastMs = seg.startMs
        return flushed + process(segmenter.onSnapshot(transcript.toString(), seg.startMs), seg.startMs)
    }

    /** Flushes the pending tail and builds the report. */
    fun finish(): CallReport {
        val endMs = lastMs + 10_000
        process(segmenter.onTick(endMs), endMs)
        val triggers = results.flatMap { it.verdict.triggers }
            .groupBy { it.trim().lowercase() }
            .entries.sortedByDescending { it.value.size }
            .map { it.value.first() }
            .take(maxTriggers)
        return CallReport(tracker.level(), tracker.risk, results.toList(), triggers)
    }

    fun run(segments: List<SttSegment>): CallReport {
        segments.forEach { onSegment(it) }
        return finish()
    }

    private fun process(statements: List<String>, nowMs: Long): List<StatementResult> =
        statements.map { text ->
            val v = classify(text, Source.RECORDING)
            StatementResult(nowMs, v, tracker.record(v, nowMs))
        }.also { results += it }
}
