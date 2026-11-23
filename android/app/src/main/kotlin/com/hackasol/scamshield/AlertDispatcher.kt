package com.hackasol.scamshield

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.hackasol.scamshield.core.AlertNotificationMapper
import com.hackasol.scamshield.core.AlertPolicy
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.Verdict

/**
 * Executes AlertPolicy: bubble through the existing OverlayController, heads-up notification with a
 * Report action. Main thread only (OverlayController requirement). Policy runs on the SHOWN label
 * (call-level tracker may differ from the raw verdict).
 */
class AlertDispatcher(private val ctx: Context, private val overlay: OverlayController?, private val titlePrefix: String = "") {
    private val nm = ctx.getSystemService(NotificationManager::class.java)
    private var channelReady = false

    /** [signalKind]: set for in-call signals (InCallSignals.KIND_*); a payment-app signal only pops the bubble in a high-risk call. */
    fun dispatch(v: Verdict, shown: Label, callLevel: Label, callRisk: Double, signalKind: String? = null) {
        val sv = v.copy(label = shown)
        val plan = AlertPolicy.plan(sv, signalKind, callLevel)
        if (plan.bubble) overlay?.showVerdict(v, shown, callLevel, callRisk, signalKind)
        // Preliminary (rules-only, LLM pending) verdicts never notify: a final one follows.
        if (!plan.notify || v.preliminary) return
        val f = AlertNotificationMapper.fields(plan, sv, v.scamType, AppSettings.lang) ?: return
        ensureChannel(f.channelId)
        val b = Notification.Builder(ctx, f.channelId)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle(titlePrefix + f.title)
            .setContentText(f.text)
            .setStyle(Notification.BigTextStyle().bigText(f.text))
            .setCategory(Notification.CATEGORY_ALARM)
            .setAutoCancel(true)
        f.actions.forEach { a ->
            val pi = PendingIntent.getActivity(ctx, a.route.hashCode(),
                Intent(ctx, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra("route", a.route),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            b.addAction(Notification.Action.Builder(null, a.label, pi).build())
            b.setContentIntent(pi)   // tapping the body opens the same route
        }
        // Without POST_NOTIFICATIONS (Android 13+) notify() is a silent no-op; nothing to catch.
        nm.notify(NOTIFICATION_ID, b.build())
    }

    private fun ensureChannel(id: String) {
        if (channelReady) return
        nm.createNotificationChannel(NotificationChannel(id, "स्कैम अलर्ट / Scam alerts", NotificationManager.IMPORTANCE_HIGH))
        channelReady = true
    }

    private companion object { const val NOTIFICATION_ID = 7001 }   // fixed: a newer alert replaces the older one
}
