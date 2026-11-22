package com.hackasol.scamshield.core

data class ActionSpec(val label: String, val route: String)

data class NotificationFields(
    val channelId: String,
    val title: String,
    val text: String,
    val priorityHigh: Boolean,
    val actions: List<ActionSpec>,
)

/** Pure plan -> notification mapping (no Android types). AlertDispatcher turns the result into a Notification. */
object AlertNotificationMapper {
    const val CHANNEL_ID = "scam_alerts"
    const val ROUTE_REPORT = "report"
    private const val MAX_TRIGGER = 40

    private fun typeHi(t: ScamType?): String? = when (t) {
        ScamType.OTP -> "OTP ठगी"
        ScamType.KYC -> "KYC ठगी"
        ScamType.DIGITAL_ARREST -> "डिजिटल अरेस्ट"
        ScamType.COURIER_CUSTOMS -> "कूरियर/कस्टम्स ठगी"
        ScamType.FAKE_QR -> "नकली QR"
        ScamType.LOAN_APP -> "लोन ऐप ठगी"
        ScamType.INVESTMENT -> "निवेश ठगी"
        ScamType.JOB -> "नौकरी ठगी"
        ScamType.MISTAKEN_TRANSFER -> "गलत ट्रांसफर ठगी"
        ScamType.OTHER, null -> null
    }

    /** Null when the plan does not notify (SAFE, or a live SUSPICIOUS that gets a bubble only). */
    fun fields(plan: AlertPlan, v: Verdict, scamType: ScamType? = null): NotificationFields? {
        if (!plan.notify) return null
        val title = when (v.label) {
            Label.SCAM -> "स्कैम की चेतावनी (SCAM)"
            Label.SUSPICIOUS -> "संदिग्ध (SUSPICIOUS)"
            Label.SAFE -> return null
        }
        val advice = if (v.label == Label.SCAM) "OTP/PIN/पैसे न दें" else "निजी जानकारी न दें"
        val trigger = v.triggers.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }?.take(MAX_TRIGGER)?.let { "\"$it\"" }
        val text = listOfNotNull(typeHi(scamType), trigger, advice).joinToString(" · ")
        // Report action is unconditional whenever we notify (T1.7 requirement).
        return NotificationFields(CHANNEL_ID, title, text, priorityHigh = true,
            actions = listOf(ActionSpec("रिपोर्ट करें (Report)", ROUTE_REPORT)))
    }
}
