package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.graph.ContextFlag
import com.hackasol.scamshield.core.graph.FlagKind

/** Every fusion weight/threshold lives here (and nowhere else). */
object FusionWeights {
    const val GEMMA = 0.7
    const val RULES = 0.3
    /** Rule score at/above which a non-SCAM model label is raised to SCAM. */
    const val RAISE_TO_SCAM_AT = 0.85
    /** Rule score at/above which a SAFE model label is raised to SUSPICIOUS. */
    const val RAISE_TO_SUSPICIOUS_AT = RuleScorer.SUSPICIOUS_AT
    /** Model confidence is replaced by this when rules raised the label (model did not vouch for it). */
    const val RAISED_MODEL_CONF = 0.5

    // Context (claim-vs-context / context rules). [VERIFY] heuristic weights; flags are combined noisy-OR.
    /** Combined flag score at/above which a SAFE label is raised to SUSPICIOUS. */
    const val CONTEXT_SUSPICIOUS_AT = 0.40
    /** Combined flag score at/above which a SUSPICIOUS label is raised to SCAM. */
    const val CONTEXT_SCAM_AT = 0.75
    /** Confidence floor for a label raised by context (the model did not vouch for it). */
    const val CONTEXT_RAISED_CONF = 0.6
    /** Context reasons added to triggers. */
    const val MAX_CONTEXT_REASONS = 3

    /** Weak signals (normal number, unknown link) must not raise a SAFE message on their own. */
    /** "No money arrived" plus a return-money request: confidence once the context layer has raised it to SUSPICIOUS. */
    const val FAKE_CREDIT_RETURN_CONF = 0.85

    fun contextWeight(k: FlagKind): Double = when (k) {
        FlagKind.NO_MATCHING_EVENT -> 0.5
        FlagKind.FAKE_CREDIT -> 0.6
        FlagKind.RETURN_VIA_BANK_ONLY -> 0.5
        FlagKind.NON_1600_BANK_CALL -> 0.5
        FlagKind.UNVERIFIED_DELIVERY -> 0.4
        FlagKind.NON_DLT_SENDER -> 0.15
        FlagKind.LINK_NOT_ALLOWLISTED -> 0.2
        FlagKind.LOOKALIKE_LINK -> 0.6
        FlagKind.NEW_UPI_PAY -> 0.4
        FlagKind.DEBIT_SCARE -> 0.5
        FlagKind.REPORTED_ENTITY -> 0.8
    }
}

data class FusedResult(
    val label: Label,
    val confidence: Double,
    val scamType: ScamType?,
    val triggers: List<String>,
    val engine: String,      // "gemma+rules" | "rules-only"
    val reason: String,
)

/** Pure fusion: SLM decides the label, rules can only raise it. */
object Fusion {
    /** [ruleType] is RuleScorer.scamType(text); used when the SLM gives no type or when no model ran. */
    fun fuse(llm: LlmResult?, rules: RuleResult, ruleType: ScamType?): FusedResult {
        if (llm == null) {
            return FusedResult(rules.label, RuleScorer.confidence(rules), ruleType, rules.triggers, "rules-only", rules.reason)
        }
        var label = llm.label
        var modelConf = llm.confidence
        if (rules.score >= FusionWeights.RAISE_TO_SCAM_AT && label != Label.SCAM) {
            label = Label.SCAM; modelConf = FusionWeights.RAISED_MODEL_CONF
        } else if (rules.score >= FusionWeights.RAISE_TO_SUSPICIOUS_AT && label == Label.SAFE) {
            label = Label.SUSPICIOUS; modelConf = FusionWeights.RAISED_MODEL_CONF
        }
        val confidence = (FusionWeights.GEMMA * modelConf + FusionWeights.RULES * RuleScorer.support(rules, label))
            .coerceIn(0.0, 1.0)
        val type = if (label == Label.SAFE) null else llm.scamType ?: ruleType
        return FusedResult(label, confidence, type, rules.triggers, "gemma+rules", llm.reason.ifBlank { rules.reason })
    }

    /** Noisy-OR of the flags' weights (0..1). */
    fun contextScore(flags: List<ContextFlag>): Double =
        1.0 - flags.fold(1.0) { acc, f -> acc * (1.0 - FusionWeights.contextWeight(f.kind)) }

    /**
     * Context can only raise, one step: SAFE -> SUSPICIOUS, SUSPICIOUS -> SCAM. SCAM and an un-raised SAFE are
     * returned untouched. When raised, the context reasons lead the triggers (alerts show the first trigger)
     * and become the reason; otherwise they are appended to the triggers of a SUSPICIOUS/SCAM result.
     */
    fun raiseForContext(fused: FusedResult, flags: List<ContextFlag>, lang: String = "en"): FusedResult {
        if (flags.isEmpty()) return fused
        val score = contextScore(flags)
        val label = when {
            fused.label == Label.SUSPICIOUS && score >= FusionWeights.CONTEXT_SCAM_AT -> Label.SCAM
            fused.label == Label.SAFE && score >= FusionWeights.CONTEXT_SUSPICIOUS_AT -> Label.SUSPICIOUS
            else -> fused.label
        }
        if (label == Label.SAFE) return fused
        val reasons = flags.map { it.reason }.distinct().take(FusionWeights.MAX_CONTEXT_REASONS)
        if (label == fused.label) return fused.copy(triggers = (fused.triggers + reasons).distinct())
        val type = fused.scamType ?: if (flags.any { it.kind == FlagKind.FAKE_CREDIT || it.kind == FlagKind.RETURN_VIA_BANK_ONLY })
            ScamType.MISTAKEN_TRANSFER else ScamType.OTHER
        return fused.copy(
            label = label,
            confidence = maxOf(fused.confidence, FusionWeights.CONTEXT_RAISED_CONF),
            scamType = type,
            triggers = (reasons + fused.triggers).distinct(),
            reason = L10n.flagReason(flags.first(), lang),
        )
    }

    /**
     * FAKE_CREDIT is only ever flagged together with a return-money request (ContextRules.mistakenTransfer), and no money
     * arrived: that pair is a scam. Raises a SUSPICIOUS result to SCAM; never lowers, never touches SAFE (raiseForContext
     * already turned SAFE into SUSPICIOUS when it fired). A lone fake-credit SMS carries no FAKE_CREDIT flag, so it is unchanged.
     */
    fun raiseForFakeCreditReturn(fused: FusedResult, flags: List<ContextFlag>): FusedResult =
        if (fused.label == Label.SUSPICIOUS && flags.any { it.kind == FlagKind.FAKE_CREDIT })
            fused.copy(label = Label.SCAM, confidence = maxOf(fused.confidence, FusionWeights.FAKE_CREDIT_RETURN_CONF))
        else fused
}
