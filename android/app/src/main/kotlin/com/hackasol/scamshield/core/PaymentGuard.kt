package com.hackasol.scamshield.core

/**
 * Pure rules for the payment-moment guard: warn once, calmly, when a payment app opens shortly after a risky verdict
 * or a UPI collect request arrives. No Android types; the notification itself lives in PaymentGuardNotifier.
 */
object PaymentGuard {
    /** A victim coached by a scammer opens the payment app within minutes of the call/message; 10 min covers a call plus the walk to the app. */
    const val WINDOW_MS = 10 * 60_000L
    /** One calm nudge per risky window across both triggers (>= WINDOW_MS, else it re-fires inside the window); repeating would train people to dismiss it. */
    const val COOLDOWN_MS = WINDOW_MS
    const val CHANNEL_ID = "payment_guard"
    const val ROUTE_FAMILY = "family"
    const val HELPLINE = "1930"

    /** Null or future timestamps (clock change) never warn. */
    fun shouldWarnOnForeground(pkg: String, nowMs: Long, lastRiskyVerdictMs: Long?, lastWarnedMs: Long?): Boolean {
        if (pkg !in InCallSignals.PAYMENT_APPS) return false
        if (lastRiskyVerdictMs == null || lastRiskyVerdictMs > nowMs || nowMs - lastRiskyVerdictMs > WINDOW_MS) return false
        return !inCooldown(nowMs, lastWarnedMs)
    }

    /** Collect-request notifications have no window: they are the trigger. Cooldown still applies. */
    fun shouldWarnOnCollect(pkg: String, title: String, text: String, nowMs: Long, lastWarnedMs: Long?): Boolean =
        isUpiCollectRequest(pkg, title, text) && !inCooldown(nowMs, lastWarnedMs)

    private fun inCooldown(nowMs: Long, lastWarnedMs: Long?): Boolean =
        lastWarnedMs != null && lastWarnedMs <= nowMs && nowMs - lastWarnedMs < COOLDOWN_MS

    // Phrases that only appear in a request to take money out of you.
    private val STRONG = UnicodeRegex.of(
        "collect (request|money)|(enter|put) (your )?upi pin to (receive|get)|pin to receive|paise maange|paise maang|request bheji|request bheja|पैसे का अनुरोध|भुगतान का अनुरोध|पैसे माँगे|पैसे मांगे"
    )
    // Looser phrases, ignored when the text also looks like a receipt or an OTP.
    private val WEAK = UnicodeRegex.of(
        "money request|payment request|request(ed|s|ing)? (for )?(money|payment|rs\\.? ?\\d|₹)|approve (the |this )?(request|collect|to receive)"
    )
    private val RECEIPT_OR_OTP = UnicodeRegex.of("credited|successful|successfully|debited|received|\\botp\\b|ओटीपी")

    fun isUpiCollectRequest(pkg: String, title: String, text: String): Boolean {
        if (pkg !in InCallSignals.PAYMENT_APPS && NotificationMapper.sourceFor(pkg) != Source.SMS) return false
        val s = "$title $text"
        return STRONG.containsMatchIn(s) || (WEAK.containsMatchIn(s) && !RECEIPT_OR_OTP.containsMatchIn(s))
    }

    data class Content(val title: String, val text: String, val callFamily: String, val call1930: String, val channel: String)

    fun content(lang: String) = Content(
        L10n.payGuardTitle(lang), L10n.payGuardText(lang), L10n.callFamily(lang), L10n.call1930(lang), L10n.payGuardChannel(lang),
    )
}
