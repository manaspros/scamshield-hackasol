package com.hackasol.scamshield.core

import kotlin.math.exp
import kotlin.math.ln

/**
 * Call-level risk as ONE running belief that the whole call is a scam, updated statement by statement.
 *
 * The SLM still reads each statement, but its verdict is evidence, not a fresh answer: the belief starts at a
 * low prior and every verdict adds to it in log-odds (SCAM a lot, SUSPICIOUS a little, SAFE takes some away).
 * So three "your KYC is pending" lines compound to SCAM, and a long stretch of ordinary talk brings the belief
 * back down. Two guards keep it honest:
 *  - SAFE can only undo evidence: the belief never drops below the prior, so polite small talk at the start
 *    of a call does not make the next scam line harder to catch.
 *  - Once a SCAM statement has been heard, SAFE lines count for much less: scammers mix in normal chat.
 * Levels use hysteresis (enter higher than they leave) so the call colour does not flicker.
 *
 * Every weight here is a [VERIFY] heuristic, to be tuned on whole-call transcripts.
 */
class CallRiskTracker(private val resetAfterMs: Long = Long.MAX_VALUE) {
    companion object {
        const val PRIOR = 0.08
        val PRIOR_LOGIT = logit(PRIOR)
        /** Upper clamp, so a long scam call can still come back down within a few minutes of SAFE talk. */
        const val MAX_LOGIT = 5.0
        // Evidence per statement, in log-odds: base + slope * confidence.
        const val SCAM_BASE = 2.0; const val SCAM_SLOPE = 3.0
        const val SUSPICIOUS_BASE = 0.8; const val SUSPICIOUS_SLOPE = 1.2
        const val SAFE_BASE = 0.3; const val SAFE_SLOPE = 0.7
        /** SAFE evidence is scaled by this once the call has had a SCAM statement. */
        const val SAFE_AFTER_SCAM = 0.35
        // Level hysteresis on the belief (0..1).
        const val SCAM_ENTER = 0.75; const val SCAM_LEAVE = 0.55
        const val SUSPICIOUS_ENTER = 0.30; const val SUSPICIOUS_LEAVE = 0.20

        fun logit(p: Double) = ln(p / (1 - p))
        fun sigmoid(x: Double) = 1 / (1 + exp(-x))

        /** Log-odds one verdict adds to the belief (negative for SAFE). */
        fun evidence(v: Verdict, scamSeen: Boolean): Double {
            val c = v.confidence.coerceIn(0.0, 1.0)
            return when (v.label) {
                Label.SCAM -> SCAM_BASE + SCAM_SLOPE * c
                Label.SUSPICIOUS -> SUSPICIOUS_BASE + SUSPICIOUS_SLOPE * c
                Label.SAFE -> -(SAFE_BASE + SAFE_SLOPE * c) * (if (scamSeen) SAFE_AFTER_SCAM else 1.0)
            }
        }
    }

    private var belief = PRIOR_LOGIT
    private var level = Label.SAFE
    private var scamSeen = false
    private var lastUpdateMs = 0L
    var statements = 0; private set

    /** Belief that this call is a scam, 0..1. 0 before any statement, so an idle call shows no risk. */
    val risk: Double get() = if (statements == 0) 0.0 else sigmoid(belief)

    fun reset() {
        belief = PRIOR_LOGIT; level = Label.SAFE; scamSeen = false; statements = 0
    }

    /** Only for callers that pass a finite [resetAfterMs]; the live service resets on call start instead. */
    fun maybeExpire(nowMs: Long) {
        if (statements > 0 && nowMs - lastUpdateMs > resetAfterMs) reset()
    }

    /**
     * Adds one verdict to the belief and returns the label to *display* for that statement: a SCAM statement is
     * shown red only once the call as a whole has reached SCAM, otherwise as SUSPICIOUS. A confident scam line
     * ("share the OTP") gets there on its own; a weak one needs another before the screen goes red.
     */
    fun record(v: Verdict, nowMs: Long): Label {
        maybeExpire(nowMs)
        lastUpdateMs = nowMs
        statements++
        belief = (belief + evidence(v, scamSeen)).coerceIn(PRIOR_LOGIT, MAX_LOGIT)
        if (v.label == Label.SCAM) scamSeen = true
        level = nextLevel(level, sigmoid(belief))
        return if (v.label == Label.SCAM && level != Label.SCAM) Label.SUSPICIOUS else v.label
    }

    fun level(): Label = if (statements == 0) Label.SAFE else level

    private fun nextLevel(cur: Label, p: Double): Label = when (cur) {
        Label.SCAM -> when {
            p >= SCAM_LEAVE -> Label.SCAM
            p >= SUSPICIOUS_LEAVE -> Label.SUSPICIOUS
            else -> Label.SAFE
        }
        Label.SUSPICIOUS -> when {
            p >= SCAM_ENTER -> Label.SCAM
            p >= SUSPICIOUS_LEAVE -> Label.SUSPICIOUS
            else -> Label.SAFE
        }
        Label.SAFE -> when {
            p >= SCAM_ENTER -> Label.SCAM
            p >= SUSPICIOUS_ENTER -> Label.SUSPICIOUS
            else -> Label.SAFE
        }
    }
}
