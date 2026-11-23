package com.hackasol.scamshield

import android.app.Notification
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.hackasol.scamshield.core.ApkRisk
import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.GemmaPrompt
import com.hackasol.scamshield.core.graph.ClaimParsers
import com.hackasol.scamshield.core.graph.GraphContext
import com.hackasol.scamshield.core.graph.KnowledgeGraph
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

/**
 * mapper -> classify -> dispatch. Pure; the service injects TextApi and AlertDispatcher.
 * With [graph] and [classifyRequest] set, every mapped notification is checked against the graph and
 * only then ingested (checking after would compare a message with itself), and the graph lines and rule
 * flags travel in the ClassifyRequest. Without them it is the plain T2.3 path.
 */
class ListenerWiring(
    private val mapper: NotificationMapper,
    private val classify: suspend (String, Source) -> Verdict,
    private val dispatch: (Verdict, Source) -> Unit,
    private val graph: KnowledgeGraph? = null,
    private val classifyRequest: (suspend (ClassifyRequest) -> Verdict)? = null,
) {
    suspend fun onPosted(n: NotificationInfo) {
        val m = mapper.map(n.pkg, n.text, n.ongoing, n.groupSummary, n.postTime) ?: return
        val g = graph
        val classifyReq = classifyRequest
        if (g == null || classifyReq == null) { dispatch(classify(m.text, m.source), m.source); return }
        // Only an SMS title is a sender header; a WhatsApp title is a contact name and must not be judged as one.
        val sender = if (m.source == Source.SMS) n.title.trim() else ""
        val flags = GraphContext.flagsFor(m.text, sender, g, n.postTime)
        val lines = GraphContext.forMessage(ClaimParsers.parse(m.text, sender), g, n.postTime, sender)
        val req = ClassifyRequest(
            m.text, lines, m.source,
            if (lines.isEmpty()) GemmaPrompt.CALL_CONTEXT_LABEL else GraphContext.LABEL, flags,
        )
        val v = try { classifyReq(req) } finally { g.ingest(m.text, sender, n.postTime) }
        dispatch(v, m.source)
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
    // Lazy: first built inside the notification coroutine, so the graph DB load stays off the main thread.
    private val wiring by lazy {
        ListenerWiring(
            NotificationMapper(),
            { text, src -> TextApi.classify(ClassifyRequest(text, source = src)) },
            { v, _ -> main.post { safe("dispatch") { dispatcher.dispatch(v, v.label, v.label, v.risk) } } },
            TextApi.graph(this),   // the same instance the caption path reads
            TextApi::classify,
        )
    }

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
        if (info.pkg != packageName && !info.ongoing) ApkRisk.apkNameIn(info.title, info.text)?.let { name ->
            scope.launch { safe("apkGuard") { ApkGuard.warnChatApk(this@ScamNotificationListener, name) } }
        }
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
