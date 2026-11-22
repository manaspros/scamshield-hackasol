package com.hackasol.scamshield.core

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
}
