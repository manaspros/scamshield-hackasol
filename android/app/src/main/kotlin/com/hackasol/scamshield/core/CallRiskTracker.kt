package com.hackasol.scamshield.core

/** Call-level risk: EMA of statement risks combined with the peak, plus red-alert hysteresis. */
class CallRiskTracker(private val resetAfterMs: Long = 30_000) {
    private var ema = 0.0
    private var peak = 0.0
    private var lastUpdateMs = 0L
    private var prevWasScam = false
    var statements = 0; private set

    val risk: Double get() = maxOf(ema, 0.8 * peak)

    fun reset() { ema = 0.0; peak = 0.0; prevWasScam = false; statements = 0 }

    fun maybeExpire(nowMs: Long) {
        if (statements > 0 && nowMs - lastUpdateMs > resetAfterMs) reset()
    }

    /**
     * Records a verdict and returns the label to *display*: a single SCAM below 0.9 confidence
     * is shown as SUSPICIOUS unless the previous statement was SCAM too (avoids red flicker).
     */
    fun record(v: Verdict, nowMs: Long): Label {
        maybeExpire(nowMs)
        lastUpdateMs = nowMs
        statements++
        ema = if (statements == 1) v.risk else 0.6 * ema + 0.4 * v.risk
        peak = maxOf(peak, v.risk)
        val shown = if (v.label == Label.SCAM && v.confidence < 0.9 && !prevWasScam) Label.SUSPICIOUS else v.label
        prevWasScam = v.label == Label.SCAM
        return shown
    }

    fun level(): Label = when {
        risk >= 0.6 -> Label.SCAM
        risk >= 0.35 -> Label.SUSPICIOUS
        else -> Label.SAFE
    }
}
