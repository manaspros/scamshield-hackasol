package com.hackasol.scamshield.core

data class ActionSpec(val label: String, val route: String)

/** Pure notification spec; AlertDispatcher turns it into an Android Notification. */
data class NotificationFields(
    val channelId: String,
    val title: String,
    val text: String,
    val priorityHigh: Boolean,
    val actions: List<ActionSpec>,
    val timeoutMs: Long = 0L,
    val onlyAlertOnce: Boolean = false,
    val group: String? = null,
    /** CATEGORY_MESSAGE (true) vs CATEGORY_STATUS. Never ALARM: an alarm category would punch through Do Not Disturb. */
    val messageCategory: Boolean = false,
    /** Fixed per tier so a silent post can never replace a SCAM alert still in the shade. */
    val notificationId: Int = AlertNotificationMapper.ID_ALERTS,
)

/** Pure plan -> notification mapping (no Android types). */
object AlertNotificationMapper {
    /** Heads-up channel for SCAM. A NEW id: the old `scam_alerts` keeps whatever importance the user/OS gave it. */
    const val CHANNEL_ID_ALERTS = "scam_alerts_v2"
    /** Silent shade-only channel (IMPORTANCE_LOW): suspicious messages and the in-call SCAM record. */
    const val CHANNEL_ID_SILENT = "scam_suspicious"
    const val ID_ALERTS = 7001
    /** Not 7002: ApkGuard and PaymentGuardNotifier already use it. */
    const val ID_SILENT = 7003
    const val GROUP_KEY = "scamshield_alerts"
    const val ROUTE_REPORT = "report"
    /** No screen of its own: Flutter ignores unknown routes, so this simply opens the app. */
    const val ROUTE_DETAILS = "details"
    private const val MAX_TRIGGER = 40

    /** Null when the plan does not notify (SAFE, or a live SUSPICIOUS that gets a chip only). */
    fun fields(plan: AlertPlan, v: Verdict, scamType: ScamType? = null, lang: String = "hi"): NotificationFields? {
        if (!plan.notify) return null
        val title = L10n.notifTitle(v.label, lang) ?: return null
        val advice = L10n.advice(v.label, lang)
        val trigger = v.triggers.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }?.take(MAX_TRIGGER)?.let { "\"$it\"" }
        val text = listOfNotNull(L10n.scamType(scamType, lang), trigger, advice).joinToString(" · ")
        val report = ActionSpec(L10n.reportAction(lang), ROUTE_REPORT)
        // Report action is unconditional whenever we notify (T1.7 requirement). Only the heads-up adds Details.
        return if (plan.headsUp) NotificationFields(CHANNEL_ID_ALERTS, title, text, priorityHigh = true,
            actions = listOf(report, ActionSpec(L10n.detailsAction(lang), ROUTE_DETAILS)),
            timeoutMs = AlertPolicy.notificationTimeoutMs(plan), onlyAlertOnce = true, group = GROUP_KEY, messageCategory = true)
        else NotificationFields(CHANNEL_ID_SILENT, title, text, priorityHigh = false, actions = listOf(report),
            timeoutMs = AlertPolicy.notificationTimeoutMs(plan), notificationId = ID_SILENT)
    }
}
