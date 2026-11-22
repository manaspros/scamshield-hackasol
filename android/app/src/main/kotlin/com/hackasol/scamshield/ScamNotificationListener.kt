package com.hackasol.scamshield

import android.app.Notification
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.NotificationMapper
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.Verdict
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/** Plain data pulled out of a StatusBarNotification so the decision flow is pure Kotlin. */
data class NotificationInfo(
    val pkg: String,
    val title: String,
    val text: String,
    val ongoing: Boolean,
    val groupSummary: Boolean,
    val postTime: Long,
)

/** mapper -> classify -> dispatch. Pure; the service injects TextApi and AlertDispatcher. */
class ListenerWiring(
    private val mapper: NotificationMapper,
    private val classify: suspend (String, Source) -> Verdict,
    private val dispatch: (Verdict, Source) -> Unit,
) {
    suspend fun onPosted(n: NotificationInfo) {
        val m = mapper.map(n.pkg, n.text, n.ongoing, n.groupSummary, n.postTime) ?: return
        dispatch(classify(m.text, m.source), m.source)
    }
}

/**
 * SMS/WhatsApp arrive as notifications, so scanning them needs no READ_SMS. Everything stays on the
 * phone. Callbacks are wrapped: an uncaught exception here would kill the process.
 */
class ScamNotificationListener : NotificationListenerService() {
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default +
        CoroutineExceptionHandler { _, t -> Log.e(TAG, "uncaught", t) })
    // AlertDispatcher needs an OverlayController (accessibility-service only), but non-CAPTION
    // sources never bubble, so the dispatcher is built with overlay = null.
    private val dispatcher by lazy { AlertDispatcher(this, null) }
    private val wiring = ListenerWiring(
        NotificationMapper(),
        { text, src -> TextApi.classify(ClassifyRequest(text, source = src)) },
        { v, _ -> main.post { safe("dispatch") { dispatcher.dispatch(v, v.label, v.label, v.risk) } } },
    )

    private inline fun safe(where: String, block: () -> Unit) {
        try { block() } catch (t: Throwable) { Log.e(TAG, "error in $where", t) }
    }

    override fun onListenerConnected() = safe("connected") { TextApi.init(this) }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) = safe("posted") {
        val info = sbn?.let(::toInfo) ?: return@safe
        scope.launch { safe("classify") { wiring.onPosted(info) } }
    }

    private fun toInfo(sbn: StatusBarNotification): NotificationInfo? {
        val n = sbn.notification ?: return null
        val e = n.extras ?: return null
        // MessagingStyle (WhatsApp, Messages) carries the real text in EXTRA_MESSAGES bundles.
        val messages = e.getParcelableArray(Notification.EXTRA_MESSAGES)
            ?.filterIsInstance<Bundle>()?.mapNotNull { it.getCharSequence("text")?.toString() }.orEmpty()
        val text = if (messages.isNotEmpty()) messages.joinToString("\n")
            else (e.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: e.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        return NotificationInfo(
            sbn.packageName,
            e.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty(),
            text,
            ongoing = n.flags and Notification.FLAG_ONGOING_EVENT != 0,
            groupSummary = n.flags and Notification.FLAG_GROUP_SUMMARY != 0,
            postTime = sbn.postTime,
        )
    }

    private companion object { const val TAG = "ScamShield/NotifListener" }
}
