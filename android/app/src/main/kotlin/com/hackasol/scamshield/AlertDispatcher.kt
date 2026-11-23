package com.hackasol.scamshield

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.RemoteViews
import com.hackasol.scamshield.core.AlertNotificationMapper
import com.hackasol.scamshield.core.AlertPolicy
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

/** Builds the real Notification from a spec. Main thread only. */
class AndroidNotificationPoster(private val ctx: Context) : NotificationPoster {
    private val nm = ctx.getSystemService(NotificationManager::class.java)
    private val channels = HashSet<String>()

    override fun post(spec: NotificationFields) {
        if (channels.add(spec.channelId)) nm.createNotificationChannel(NotificationChannel(spec.channelId,
            L10n.channelName(spec.priorityHigh, AppSettings.lang),
            if (spec.priorityHigh) NotificationManager.IMPORTANCE_HIGH else NotificationManager.IMPORTANCE_LOW))
        val b = Notification.Builder(ctx, spec.channelId)
            .setSmallIcon(R.drawable.ic_stat_shield)
            .setContentTitle(spec.title)
            .setContentText(spec.text)
            .setStyle(Notification.BigTextStyle().bigText(spec.text))
            .setCategory(if (spec.messageCategory) Notification.CATEGORY_MESSAGE else Notification.CATEGORY_STATUS)
            .setOnlyAlertOnce(spec.onlyAlertOnce)
            .setAutoCancel(true)
            .setColor(ctx.getColor(if (spec.priorityHigh) R.color.alert_scam else R.color.brand_blue))
        if (spec.priorityHigh) {
            // Scam heads-up: our own rounded body inside the system frame (header + action pills stay native,
            // so it matches the phone's style, e.g. OxygenOS). Plain text stays set for wearables / accessibility.
            val body = spec.kicker?.let { k -> spec.text.removePrefix("$k · ") } ?: spec.text
            val rv = RemoteViews(ctx.packageName, R.layout.notif_alert).apply {
                setTextViewText(R.id.notif_title, spec.title)
                setTextViewText(R.id.notif_text, body)
                if (spec.kicker.isNullOrBlank()) setViewVisibility(R.id.notif_kicker, View.GONE)
                else setTextViewText(R.id.notif_kicker, spec.kicker)
            }
            b.setStyle(Notification.DecoratedCustomViewStyle())
                .setCustomContentView(rv)
                .setCustomBigContentView(rv)
                .setCustomHeadsUpContentView(rv)
        }
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
) {
    constructor(ctx: Context, overlay: BubbleSink?, titlePrefix: String = "", idOffset: Int = 0) :
        this(overlay, AndroidNotificationPoster(ctx), titlePrefix, idOffset = idOffset)

    /** [signalKind]: set for in-call signals (InCallSignals.KIND_*); a payment-app signal only draws a card in a high-risk call. */
    fun dispatch(v: Verdict, shown: Label, callLevel: Label, callRisk: Double, signalKind: String? = null) {
        val sv = v.copy(label = shown)
        // Preliminary (rules-only, LLM pending) verdicts get a chip at most: the plan never notifies them, a final verdict follows.
        val plan = AlertPolicy.plan(sv, signalKind, callLevel)
        AlertPath.d("dispatch label=$shown source=${v.source} bubble=${plan.bubble} notify=${plan.notify} headsUp=${plan.headsUp} generation=$generation")
        if (plan.bubble) overlay?.showVerdict(v, shown, callLevel, callRisk, signalKind, titlePrefix)
        if (!plan.notify) return
        val f = AlertNotificationMapper.fields(plan, sv, v.scamType, lang())?.let { it.copy(title = titlePrefix + it.title, notificationId = it.notificationId + idOffset) } ?: return
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
