package com.hackasol.scamshield.core

/** Pure-Kotlin data types for the Text API (no Android deps, so unit-testable). */

enum class Label { SAFE, SUSPICIOUS, SCAM;
    companion object {
        fun parse(s: String?): Label? = when (s?.trim()?.uppercase()) {
            "SAFE", "GENUINE", "NEUTRAL", "POSITIVE" -> SAFE
            "SUSPICIOUS", "SUSPECT", "WARNING" -> SUSPICIOUS
            "SCAM", "FRAUD", "NEGATIVE" -> SCAM
            else -> null
        }
    }
}

enum class Source { CAPTION, PASTE, SHARE, SMS, WHATSAPP, NOTIFICATION, RECORDING, SIGNAL;
    companion object {
        /** Parse the string source values sent by older MainActivity/Dart callers. */
        fun parse(s: String?): Source {
            val normalized = s?.trim()?.lowercase()?.replace('-', '_')?.replace(' ', '_')
            return when (normalized) {
                "caption" -> CAPTION
                "paste", "manual", "try_api", "tryapi" -> PASTE
                "share" -> SHARE
                "sms" -> SMS
                "whatsapp", "whats_app" -> WHATSAPP
                "notification" -> NOTIFICATION
                "signal" -> SIGNAL
                "recording" -> RECORDING
                else -> CAPTION
            }
        }
    }
}

data class ClassifyRequest(
    val text: String,
    val context: List<String> = emptyList(),
    val source: Source = Source.PASTE,
)

data class RuleResult(
    val score: Double,            // 0..1 noisy-OR of matched rule weights
    val label: Label,
    val triggers: List<String>,   // matched phrases as they appeared in the text
    val reason: String,
)

enum class ScamType { OTP, KYC, DIGITAL_ARREST, COURIER_CUSTOMS, FAKE_QR, LOAN_APP, INVESTMENT, JOB, MISTAKEN_TRANSFER, OTHER;
    companion object {
        /** Null for blank/unknown/"NONE"; accepts any case and space/hyphen separators. */
        fun parse(s: String?): ScamType? {
            val n = s?.trim()?.uppercase()?.replace('-', '_')?.replace(' ', '_') ?: return null
            return values().firstOrNull { it.name == n }
        }
    }
}

data class LlmResult(val label: Label, val confidence: Double, val reason: String, val scamType: ScamType? = null)

data class Verdict(
    val text: String,
    val label: Label,
    val confidence: Double,
    val reason: String,
    val triggers: List<String>,
    val engine: String,           // "gemma+rules" | "rules-only"
    val latencyMs: Long,
    val source: Source,
    val preliminary: Boolean = false,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "text" to text,
        "label" to label.name,
        "confidence" to confidence,
        "reason" to reason,
        "triggers" to triggers,
        "engine" to engine,
        "latencyMs" to latencyMs,
        "source" to source.name.lowercase(),
        "preliminary" to preliminary,
    )

    /** 0..1 risk used by the call-level tracker. */
    val risk: Double get() = when (label) {
        Label.SAFE -> (1 - confidence) * 0.3
        Label.SUSPICIOUS -> 0.4 + 0.2 * confidence
        Label.SCAM -> 0.6 + 0.4 * confidence
    }
}
