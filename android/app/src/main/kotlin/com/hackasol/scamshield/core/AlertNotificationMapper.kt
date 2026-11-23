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

    /** Null when the plan does not notify (SAFE, or a live SUSPICIOUS that gets a bubble only). */
    fun fields(plan: AlertPlan, v: Verdict, scamType: ScamType? = null, lang: String = "hi"): NotificationFields? {
        if (!plan.notify) return null
        val title = L10n.notifTitle(v.label, lang) ?: return null
        val advice = L10n.advice(v.label, lang)
        val trigger = v.triggers.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }?.take(MAX_TRIGGER)?.let { "\"$it\"" }
        val text = listOfNotNull(L10n.scamType(scamType, lang), trigger, advice).joinToString(" · ")
        // Report action is unconditional whenever we notify (T1.7 requirement).
        return NotificationFields(CHANNEL_ID, title, text, priorityHigh = true,
            actions = listOf(ActionSpec(L10n.reportAction(lang), ROUTE_REPORT)))
    }
}
