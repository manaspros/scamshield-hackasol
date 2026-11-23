package com.hackasol.scamshield

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.text.SpannableString
import android.text.Spanned
import android.text.style.LocaleSpan
import java.util.Locale
import com.hackasol.scamshield.core.AlertNotificationMapper
import com.hackasol.scamshield.core.AlertPlan
import com.hackasol.scamshield.core.AlertPolicy
import com.hackasol.scamshield.core.Surface
import com.hackasol.scamshield.core.L10n
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.NotificationFields
import com.hackasol.scamshield.core.Verdict

/** Diagnostics for the alert path. Never pass message text. Swallows the JVM-unit-test "Log not mocked" error. */
internal object AlertPath {
    fun d(msg: String) { try { android.util.Log.d("ScamShield/AlertPath", msg) } catch (_: RuntimeException) {} }
}

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

/** [s] with a hi-IN LocaleSpan when it contains Devanagari; plain otherwise. */
internal fun localeTagged(s: String): CharSequence =
    if (s.none { it in '\u0900'..'\u097F' }) s
    else SpannableString(s).apply { setSpan(LocaleSpan(Locale.forLanguageTag("hi-IN")), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE) }

/** Builds the real Notification from a spec. Main thread only. */
class AndroidNotificationPoster(private val ctx: Context) : NotificationPoster {
    private val nm = ctx.getSystemService(NotificationManager::class.java)
    private val channels = HashSet<String>()

    override fun post(spec: NotificationFields) {
        if (channels.add(spec.channelId)) nm.createNotificationChannel(NotificationChannel(spec.channelId,
            L10n.channelName(spec.priorityHigh, AppSettings.lang),
            if (spec.priorityHigh) NotificationManager.IMPORTANCE_HIGH else NotificationManager.IMPORTANCE_LOW))
        // Tag Hindi text as Hindi: TalkBack then reads it with a Hindi voice instead of spelling Devanagari with an English one.
        val title = localeTagged(spec.title)
        val text = localeTagged(spec.text)
        val b = Notification.Builder(ctx, spec.channelId)
            .setSmallIcon(R.drawable.ic_stat_shield)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
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
        if (spec.onlyAlertOnce) nm.cancel(spec.notificationId)
        // Without POST_NOTIFICATIONS (Android 13+) notify() is a silent no-op; nothing to catch.
        AlertPath.d("post id=${spec.notificationId} channel=${spec.channelId} enabled=${nm.areNotificationsEnabled()} importance=${nm.getNotificationChannel(spec.channelId)?.importance}")
        nm.notify(spec.notificationId, b.build())   // fixed id per tier: a newer alert replaces the older one of the same tier only
    }
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
    /** Added to every notification id; Demo Lab uses it so a demo alert never replaces a real one. */
    private val idOffset: Int = 0,
    /** False when the user switched the in-call overlay off: the bubble is then not drawn. */
    private val overlayOn: () -> Boolean = { true },
) {
    constructor(ctx: Context, overlay: BubbleSink?, titlePrefix: String = "", idOffset: Int = 0) :
        this(overlay, AndroidNotificationPoster(ctx), titlePrefix, idOffset = idOffset, overlayOn = { AppSettings.overlayEnabled })

    /** [signalKind]: set for in-call signals (InCallSignals.KIND_*); a payment-app signal only draws a card in a high-risk call. */
    fun dispatch(v: Verdict, shown: Label, callLevel: Label, callRisk: Double, signalKind: String? = null) {
        val sv = v.copy(label = shown)
        // Preliminary (rules-only, LLM pending) verdicts get a chip at most: the plan never notifies them, a final verdict follows.
        val planned = AlertPolicy.plan(sv, signalKind, callLevel)
        // No overlay to draw on (accessibility service off, or overlay switched off): a live SCAM must still reach the user,
        // so it becomes a heads-up notification instead of the card's silent record; a live SUSPICIOUS a silent one.
        val noOverlay = overlay == null || !overlayOn()
        val plan = if (planned.bubble && noOverlay && !sv.preliminary)
            AlertPlan.of(if (shown == Label.SCAM) Surface.HEADS_UP else Surface.SILENT_NOTIF) else planned
        AlertPath.d("dispatch label=$shown source=${v.source} bubble=${plan.bubble} notify=${plan.notify} headsUp=${plan.headsUp} generation=$generation")
        if (plan.bubble) overlay?.showVerdict(v, shown, callLevel, callRisk, signalKind, titlePrefix)
        if (!plan.notify) return
        val f = AlertNotificationMapper.fields(plan, sv, v.scamType, lang(), signalKind)?.let { it.copy(title = titlePrefix + it.title, notificationId = it.notificationId + idOffset) } ?: return
        if (!plan.headsUp) { poster.post(f); return }
        // A newer heads-up posts the pending older one first (never drops it), so the newest ends up on top in the shade.
        flushPending()
        val delay = AlertPolicy.headsUpDelayMs(shown, sv.source)
        AlertPath.d("schedule delayMs=$delay")
        if (delay > 0) {
            val g = ++generation
            pending = f
            scheduler.postDelayed(delay) {
                AlertPath.d("fire g=$g current=$generation ${if (g == generation) "fired" else "stale (already flushed)"}")
                if (g == generation) flushPending()
            }
        } else poster.post(f)
    }

    /** Posts the delayed heads-up now, if any; its scheduled runnable then no-ops (callers: a newer heads-up, owner shutdown). */
    fun flushPending() {
        val p = pending ?: return
        pending = null
        generation++
        AlertPath.d("flushPending posting")
        poster.post(p)
    }

    /** Drops any delayed heads-up that has not fired yet. */
    fun cancelPending() { pending = null; generation++ }

    private var generation = 0
    private var pending: NotificationFields? = null

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
