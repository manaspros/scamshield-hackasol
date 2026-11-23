package com.hackasol.scamshield.core

/** Pure permission-based risk scoring for an APK about to be installed (no Android deps). */

enum class ApkRiskLevel { LOW, MEDIUM, HIGH }

data class RiskyPermission(val permission: String, val hindiReason: String, val englishReason: String)

data class ApkRiskResult(val level: ApkRiskLevel, val score: Int, val risky: List<RiskyPermission>)

object ApkRisk {
    // [VERIFY] weights and thresholds are heuristic, tune against real scam-APK samples.
    const val HIGH_THRESHOLD = 60
    const val MEDIUM_THRESHOLD = 25
    const val COMBO_SCORE = 85            // SMS-read + INTERNET + CONTACTS (classic OTP stealer)
    const val UNKNOWN_SOURCE_BONUS = 10   // shared via chat / unknown source, only if something risky found

    private class Rule(val weight: Int, val hi: String, val en: String)

    // Keys are the permission name without the "android.permission." prefix.
    // [VERIFY] weights.
    private val RULES: Map<String, Rule> = mapOf(
        "RECEIVE_SMS" to Rule(30, "आपके SMS (OTP समेत) पढ़ सकता है", "Can read your incoming SMS, including OTPs"),
        "READ_SMS" to Rule(30, "आपके सारे SMS पढ़ सकता है", "Can read all your SMS messages"),
        "SEND_SMS" to Rule(25, "आपके नंबर से SMS भेज सकता है", "Can send SMS from your number"),
        "BIND_ACCESSIBILITY_SERVICE" to Rule(40, "स्क्रीन देख और नियंत्रित कर सकता है", "Can watch and control your screen"),
        "SYSTEM_ALERT_WINDOW" to Rule(25, "दूसरे ऐप्स के ऊपर नकली स्क्रीन दिखा सकता है", "Can draw fake screens over other apps"),
        "REQUEST_INSTALL_PACKAGES" to Rule(25, "और ऐप्स इंस्टॉल कर सकता है", "Can install further apps"),
        "BIND_NOTIFICATION_LISTENER_SERVICE" to Rule(35, "आपकी सभी नोटिफिकेशन (OTP) पढ़ सकता है", "Can read all your notifications, including OTPs"),
        "READ_CONTACTS" to Rule(15, "आपके कॉन्टैक्ट्स पढ़ सकता है", "Can read your contacts"),
        "READ_CALL_LOG" to Rule(15, "आपका कॉल इतिहास पढ़ सकता है", "Can read your call history"),
        "CALL_PHONE" to Rule(10, "आपकी तरफ से कॉल कर सकता है", "Can place calls on your behalf"),
        "BIND_DEVICE_ADMIN" to Rule(40, "फ़ोन पर एडमिन नियंत्रण ले सकता है, हटाना मुश्किल", "Can take device-admin control and resist removal"),
        "QUERY_ALL_PACKAGES" to Rule(10, "आपके फ़ोन के सारे ऐप्स की सूची देख सकता है", "Can list every app on your phone"),
    )

    private val SMS_READ = setOf("RECEIVE_SMS", "READ_SMS")
    private val APK_NAME = Regex("""[^\s/\\"']+\.apk\b""", RegexOption.IGNORE_CASE)

    /** First ".apk" file name mentioned in the given notification fields (e.g. a chat document), else null. */
    fun apkNameIn(vararg fields: String): String? = fields.firstNotNullOfOrNull { APK_NAME.find(it)?.value }

    fun assess(
        permissions: List<String>,
        fromUnknownSource: Boolean = false,
        label: String? = null,        // reserved for the warning text; not scored
        packageName: String? = null,  // reserved; not scored
    ): ApkRiskResult {
        val names = permissions.map { it.substringAfterLast('.') }.toSet()
        val hits = RULES.keys.filter { it in names }
        var score = hits.sumOf { RULES.getValue(it).weight }
        if (hits.isNotEmpty() && fromUnknownSource) score += UNKNOWN_SOURCE_BONUS
        val combo = names.any { it in SMS_READ } && "INTERNET" in names && "READ_CONTACTS" in names
        if (combo) score = maxOf(score, COMBO_SCORE)
        score = score.coerceIn(0, 100)
        val level = when {
            combo || score >= HIGH_THRESHOLD -> ApkRiskLevel.HIGH
            score >= MEDIUM_THRESHOLD -> ApkRiskLevel.MEDIUM
            else -> ApkRiskLevel.LOW
        }
        return ApkRiskResult(level, score, hits.map { RiskyPermission("android.permission.$it", RULES.getValue(it).hi, RULES.getValue(it).en) })
    }
}
