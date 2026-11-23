package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.graph.ContextFlag
import com.hackasol.scamshield.core.graph.FlagKind

/**
 * What a user-trusted sender may and may not change. Trust never changes a verdict label; it only lets a
 * SUSPICIOUS heads-up from that sender stay quiet (still logged) when nothing hard backs it. SCAM always alerts.
 */
object Trust {
    /** A hard signal: rules alone say SCAM, or the context layer found a fake credit, a reported entity, a lookalike link or a fake bank SMS. */
    fun hardSignal(text: String, flags: List<ContextFlag>): Boolean =
        RuleScorer.score(text).score >= RuleScorer.SCAM_AT ||
            flags.any { it.kind in HARD_KINDS }

    private val HARD_KINDS = setOf(FlagKind.FAKE_CREDIT, FlagKind.REPORTED_ENTITY, FlagKind.LOOKALIKE_LINK, FlagKind.DEBIT_SCARE, FlagKind.SPOOFED_BANK_SMS)

    /** Skip the alert (not the log): trusted sender, a SUSPICIOUS verdict, and no hard signal. */
    fun quietAlert(label: Label, trusted: Boolean, hard: Boolean): Boolean =
        trusted && label == Label.SUSPICIOUS && !hard
}
