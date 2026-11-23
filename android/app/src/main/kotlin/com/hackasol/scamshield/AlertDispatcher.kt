package com.hackasol.scamshield

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.hackasol.scamshield.core.AlertNotificationMapper
import com.hackasol.scamshield.core.AlertPolicy
import com.hackasol.scamshield.core.L10n
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.NotificationFields
import com.hackasol.scamshield.core.Verdict

/** The bubble the dispatcher draws; a seam so tests (and Demo Lab) need no AccessibilityService. */
interface BubbleSink {
    fun showVerdict(v: Verdict, shown: Label, callLevel: Label, callRisk: Double, signalKind: String? = null, titlePrefix: String = "")
}

/** Posts a finished notification spec; a seam so the dispatcher is testable without Android. */
fun interface NotificationPoster {
    fun post(spec: NotificationFields)
}

/** Runs [r] after [delayMs] on the main thread; a seam for the heads-up delay. */
fun interface Scheduler {
    fun postDelayed(delayMs: Long, r: Runnable)
}

object MainScheduler : Scheduler {
    private val handler by lazy { Handler(Looper.getMainLooper()) }
    override fun postDelayed(delayMs: Long, r: Runnable) { handler.postDelayed(r, delayMs) }
}

/** Builds the real Notification from a spec. Main thread only. */
class AndroidNotificationPoster(private val ctx: Context) : NotificationPoster {
    private val nm = ctx.getSystemService(NotificationManager::class.java)
    private val channels = HashSet<String>()

    override fun post(spec: NotificationFields) {
        if (channels.add(spec.channelId)) nm.createNotificationChannel(NotificationChannel(spec.channelId,
            L10n.channelName(spec.priorityHigh, AppSettings.lang),
            if (spec.priorityHigh) NotificationManager.IMPORTANCE_HIGH else NotificationManager.IMPORTANCE_LOW))
        val b = Notification.Builder(ctx, spec.channelId)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle(spec.title)
            .setContentText(spec.text)
            .setStyle(Notification.BigTextStyle().bigText(spec.text))
            .setCategory(if (spec.messageCategory) Notification.CATEGORY_MESSAGE else Notification.CATEGORY_STATUS)
            .setOnlyAlertOnce(spec.onlyAlertOnce)
            .setAutoCancel(true)
        if (spec.timeoutMs > 0) b.setTimeoutAfter(spec.timeoutMs)
        spec.group?.let(b::setGroup)
        spec.actions.forEach { a ->
            val pi = PendingIntent.getActivity(ctx, a.route.hashCode(),
                Intent(ctx, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra("route", a.route),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            b.addAction(Notification.Action.Builder(null, a.label, pi).build())
            b.setContentIntent(pi)   // tapping the body opens the last action's route
        }
        // onlyAlertOnce would mute a second, different scam while the first is still in the shade: cancel so it is a new post.
        if (spec.onlyAlertOnce) nm.cancel(NOTIFICATION_ID)
        // Without POST_NOTIFICATIONS (Android 13+) notify() is a silent no-op; nothing to catch.
        nm.notify(NOTIFICATION_ID, b.build())
    }

    private companion object { const val NOTIFICATION_ID = 7001 }   // fixed: a newer alert replaces the older one
}

/**
 * Executes AlertPolicy: chip/card through the overlay sink, notification through the poster (a non-live SCAM heads-up is
 * delayed so it does not land on the original message's peek). Main thread only. Policy runs on the SHOWN label
 * (call-level tracker may differ from the raw verdict).
 */
class AlertDispatcher(
    private val overlay: BubbleSink?,
    private val poster: NotificationPoster,
    private val titlePrefix: String = "",
    private val scheduler: Scheduler = MainScheduler,
    private val lang: () -> String = { AppSettings.lang },
) {
    constructor(ctx: Context, overlay: BubbleSink?, titlePrefix: String = "") :
        this(overlay, AndroidNotificationPoster(ctx), titlePrefix)

    /** [signalKind]: set for in-call signals (InCallSignals.KIND_*); a payment-app signal only draws a card in a high-risk call. */
    fun dispatch(v: Verdict, shown: Label, callLevel: Label, callRisk: Double, signalKind: String? = null) {
        val sv = v.copy(label = shown)
        // Preliminary (rules-only, LLM pending) verdicts get a chip at most: the plan never notifies them, a final verdict follows.
        val plan = AlertPolicy.plan(sv, signalKind, callLevel)
        if (plan.bubble) overlay?.showVerdict(v, shown, callLevel, callRisk, signalKind, titlePrefix)
        if (!plan.notify) return
        val f = AlertNotificationMapper.fields(plan, sv, v.scamType, lang())?.let { it.copy(title = titlePrefix + it.title) } ?: return
        if (!plan.headsUp) { poster.post(f); return }
        // Each heads-up supersedes any pending one: a stale delayed post must never fire later or overwrite a newer alert.
        val g = ++generation
        val delay = AlertPolicy.headsUpDelayMs(shown, sv.source)
        if (delay > 0) scheduler.postDelayed(delay) { if (g == generation) poster.post(f) } else poster.post(f)
    }

    /** Drops any delayed heads-up that has not fired yet (callers: owner shutdown). */
    fun cancelPending() { generation++ }

    private var generation = 0

    companion object {
        /**
         * Bubble half of [dispatch] on its own, for Demo Lab. Returns true only if AlertPolicy wants a chip/card AND a sink is
         * present.
         */
        fun showBubble(sink: BubbleSink?, v: Verdict, shown: Label, callLevel: Label, callRisk: Double, titlePrefix: String): Boolean {
            if (sink == null || !AlertPolicy.plan(v.copy(label = shown), null, callLevel).bubble) return false
            sink.showVerdict(v, shown, callLevel, callRisk, null, titlePrefix)
            return true
        }
    }
}
