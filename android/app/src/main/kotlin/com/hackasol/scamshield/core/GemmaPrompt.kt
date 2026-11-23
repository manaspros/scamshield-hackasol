package com.hackasol.scamshield.core

/**
 * Few-shot prompt for on-device Gemma. Pure Kotlin; the Python port (ml/scamshield_ml/prompt.py)
 * must reproduce `build` byte for byte (see data/golden/prompt_golden.json).
 *
 * Format of `build(text, context, contextLabel = "Earlier in this call")`:
 *  1. HEADER: fixed text ending with the "Answer with ONLY one line of JSON: ..." line, a blank line,
 *     then 6 few-shot pairs. Each pair is `STATEMENT: "<example>"\n` + one JSON answer line + `\n`.
 *     Answer shape: {"label":"SAFE|SUSPICIOUS|SCAM","scam_type":"<TYPE|NONE>","confidence":<0..1>,"reason":"<text>"}
 *     scam_type is one of the ScamType names, or NONE when label is SAFE.
 *  2. Optional context: the last 2 non-blank entries of `context` (in order), each cut to 150 chars with
 *     `"` kept as is, wrapped in double quotes and joined by " | ", emitted as
 *     `\n<contextLabel>: <joined>\n` (note the leading blank line). The default label is "Earlier in this call"
 *     (live call captions); notification context from the knowledge graph uses "Known context".
 *     `contextLabel` is a trusted constant, never user text, and is not escaped.
 *  3. Query: `STATEMENT: "<text>"\n` where text is cut to the first 300 chars and every `"` becomes `'`.
 * The model is expected to continue with one JSON line (parsed by [LlmOutputParser]).
 * Lengths are in UTF-16 code units (Kotlin String.take); Python must slice the same way for non-BMP text.
 */
object GemmaPrompt {
    private const val HEADER = """You are a fraud detector for Indian phone calls. Classify the caller's STATEMENT as SAFE, SUSPICIOUS or SCAM. Text may be English, Hindi (Devanagari) or Hinglish.
SCAM: asks for OTP/PIN/CVV/password, threatens arrest or "digital arrest", says police/CBI/customs/courier has a case against you, asks to move money to a "safe account", install AnyDesk/an app, or keep the call secret.
SUSPICIOUS: unsolicited bank/KYC/prize/loan/refund claims, urgency, asks for personal details, but no direct demand yet.
SAFE: normal conversation.
For SCAM or SUSPICIOUS also give scam_type: OTP, KYC, DIGITAL_ARREST, COURIER_CUSTOMS, FAKE_QR, LOAN_APP, INVESTMENT, JOB, MISTAKEN_TRANSFER or OTHER. For SAFE use NONE.
Answer with ONLY one line of JSON: {"label":"SAFE|SUSPICIOUS|SCAM","scam_type":"OTP|KYC|DIGITAL_ARREST|COURIER_CUSTOMS|FAKE_QR|LOAN_APP|INVESTMENT|JOB|MISTAKEN_TRANSFER|OTHER|NONE","confidence":0.0-1.0,"reason":"max 10 words"}

STATEMENT: "Sir aapke phone pe ek OTP aaya hoga, woh jaldi bata dijiye"
{"label":"SCAM","scam_type":"OTP","confidence":0.97,"reason":"Asks you to share OTP"}
STATEMENT: "मैं सीबीआई ऑफिस से बोल रहा हूं, आप डिजिटल अरेस्ट में हैं"
{"label":"SCAM","scam_type":"DIGITAL_ARREST","confidence":0.98,"reason":"Fake CBI digital arrest threat"}
STATEMENT: "Your parcel to Taiwan has drugs, press 1 to talk to customs officer"
{"label":"SCAM","scam_type":"COURIER_CUSTOMS","confidence":0.93,"reason":"Fake customs parcel story"}
STATEMENT: "Main SBI bank se bol raha hoon, aapka KYC pending hai"
{"label":"SUSPICIOUS","scam_type":"KYC","confidence":0.75,"reason":"Unsolicited bank KYC claim"}
STATEMENT: "Beta khana kha liya? Kal shaam ko milte hain"
{"label":"SAFE","scam_type":"NONE","confidence":0.95,"reason":"Normal family conversation"}
STATEMENT: "Your order will be delivered tomorrow between 10 and 12"
{"label":"SAFE","scam_type":"NONE","confidence":0.85,"reason":"Routine delivery update"}
"""

    const val CALL_CONTEXT_LABEL = "Earlier in this call"

    fun build(text: String, context: List<String>, contextLabel: String = CALL_CONTEXT_LABEL): String {
        val sb = StringBuilder(HEADER)
        val ctx = context.filter { it.isNotBlank() }.takeLast(2)
        if (ctx.isNotEmpty()) sb.append('\n').append(contextLabel).append(": ").append(ctx.joinToString(" | ") { "\"${it.take(150)}\"" }).append('\n')
        sb.append("STATEMENT: \"").append(text.take(300).replace("\"", "'")).append("\"\n")
        return sb.toString()
    }
}
