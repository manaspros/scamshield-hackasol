package com.hackasol.scamshield.core

/**
 * Parses Gemma's reply. Expected: {"label":"SCAM","confidence":0.9,"reason":"..."}.
 * Small models often add prose, code fences or break JSON, so this is regex-based and lenient.
 * Pure Kotlin (no org.json) so it runs in JVM unit tests.
 */
object LlmOutputParser {
    private val labelRe = Regex("\"?label\"?\\s*[:=]\\s*\"?([A-Za-z]+)", RegexOption.IGNORE_CASE)
    private val confRe = Regex("\"?confidence\"?\\s*[:=]\\s*\"?([0-9]*\\.?[0-9]+)\\s*(%)?", RegexOption.IGNORE_CASE)
    private val reasonRe = Regex("\"?reason\"?\\s*[:=]\\s*\"([^\"]*)\"", RegexOption.IGNORE_CASE)
    private val bareLabelRe = Regex("\\b(SCAM|SUSPICIOUS|SAFE)\\b")

    fun parse(raw: String): LlmResult? {
        val text = raw.replace("```json", "").replace("```", "").trim()
        val label = labelRe.find(text)?.groupValues?.get(1)?.let(Label::parse)
            ?: bareLabelRe.find(text)?.groupValues?.get(1)?.let(Label::parse)
            ?: return null
        val confMatch = confRe.find(text)
        var conf = confMatch?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.6
        if (confMatch?.groupValues?.get(2) == "%" || conf > 1.0) conf /= 100.0
        val reason = reasonRe.find(text)?.groupValues?.get(1)?.trim().orEmpty()
        return LlmResult(label, conf.coerceIn(0.0, 1.0), reason.take(120))
    }
}
