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
import com.hackasol.scamshield.core.CallContext
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.Trust
import com.hackasol.scamshield.core.graph.AlertRef
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
    /** Notification.category (call notifications are `ongoing` and would be dropped by the mapper). */
    val category: String? = null,
    /** When the newest message was sent (MessagingStyle "time"); the post time when unknown. */
    val messageTsMs: Long = postTime,
)

/** Picks what to read from a MessagingStyle notification: only the newest message, never the whole thread. */
object NewestMessage {
    /**
     * [bundles] = (text, time) per EXTRA_MESSAGES entry, oldest first. Only the LAST one counts: if its text is blank
     * (photo, voice note, sticker) there is nothing new to classify, so null (an older text must not be judged again).
     * Time <= 0 falls back to [postTime].
     */
    fun pick(bundles: List<Pair<String?, Long>>, postTime: Long): Pair<String, Long>? =
        bundles.lastOrNull()?.takeIf { !it.first.isNullOrBlank() }?.let { it.first!! to (if (it.second > 0) it.second else postTime) }
}

/**
 * mapper -> classify -> dispatch. Pure; the service injects TextApi and AlertDispatcher.
 * With [graph] and [classifyLogged] (or [classifyRequest]) set, every mapped notification is checked against the
 * graph, then classified, and only then ingested (checking after would compare a message with itself). The ingest
 * is `trusted` only for a SAFE verdict, so a scam message cannot make its sender, UPI id or "order confirmed"
 * look known. Non-SAFE verdicts remember their entities (AlertRef) so "This was a scam / safe" can act on them.
 * Without a graph it is the plain T2.3 path.
 * [classifyLogged] returns the verdict and the timestamp it was logged under (the key of the AlertRef).
 */
class ListenerWiring(
    private val mapper: NotificationMapper,
    private val classify: suspend (String, Source) -> Verdict,
    private val dispatch: (Verdict, Source) -> Unit,
    private val graph: KnowledgeGraph? = null,
    private val classifyRequest: (suspend (ClassifyRequest) -> Verdict)? = null,
    private val classifyLogged: (suspend (ClassifyRequest) -> Pair<Verdict, Long>)? = null,
) {
    suspend fun onPosted(n: NotificationInfo) {
        val m = mapper.map(n.pkg, n.text, n.ongoing, n.groupSummary, n.postTime) ?: return
        val g = graph
        if (g == null || (classifyRequest == null && classifyLogged == null)) { dispatch(classify(m.text, m.source), m.source); return }
        val ts = n.messageTsMs
        // Only an SMS title is a sender header; a WhatsApp title is a contact name and must not be judged as one.
        val sender = if (m.source == Source.SMS) n.title.trim() else ""
        val key = senderKey(m.source, n.title)
        val trusted = key.isNotEmpty() && g.isTrusted(key)
        val claims = ClaimParsers.parse(m.text, sender)
        val flags = GraphContext.flagsFor(m.text, sender, g, ts, key)
        val lines = GraphContext.forMessage(claims, g, ts, sender, key)
        val req = ClassifyRequest(
            m.text, lines, m.source,
            if (lines.isEmpty()) GemmaPrompt.CALL_CONTEXT_LABEL else GraphContext.LABEL, flags,
        )
        // If classify throws nothing is ingested (an unclassified message must not become "known").
        val (v, loggedTs) = classifyLogged?.invoke(req) ?: (classifyRequest!!(req) to ts)
        g.ingest(m.text, sender, ts, trusted = v.label == Label.SAFE)
        if (v.label != Label.SAFE) g.rememberAlert(AlertRef(loggedTs, key, claims.numbers, claims.upiIds))
        if (trusted && Trust.quietAlert(v.label, true, Trust.hardSignal(m.text, flags))) return   // still logged by TextApi
        dispatch(v, m.source)
    }

    /** Key for trust / report / alert lookups: SMS title as is; WhatsApp "wa:" + contact name (never used as an SMS sender header). */
    private fun senderKey(source: Source, title: String): String = when (source) {
        Source.SMS -> title.trim()
        Source.WHATSAPP -> if (title.isBlank()) "" else "wa:" + title.trim()
        else -> ""
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
            classifyLogged = TextApi::classifyLogged,
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
        val s = sbn ?: return@safe
        val info = toInfo(s) ?: return@safe
        // A call notification is `ongoing` (the mapper would drop it): read the caller number from it first.
        if (CallContext.isCallNotification(info.category)) {
            CallContext.onCallNotification(info.title, info.text, System.currentTimeMillis(), s.key)
            return@safe
        }
        if (info.pkg != packageName && !info.ongoing) ApkRisk.apkNameIn(info.title, info.text)?.let { name ->
            scope.launch { safe("apkGuard") { ApkGuard.warnChatApk(this@ScamNotificationListener, name) } }
        }
        if (info.pkg != packageName && !info.ongoing) scope.launch {
            safe("payGuard") { ForegroundHook.onNotification(this@ScamNotificationListener, info.pkg, info.title, info.text, System.currentTimeMillis()) }
        }
        scope.launch { safe("classify") { wiring.onPosted(info) } }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) = safe("removed") {
        val n = sbn ?: return@safe
        if (CallContext.isCallNotification(n.notification?.category)) CallContext.onRemoved(n.key)
    }

    private fun toInfo(sbn: StatusBarNotification): NotificationInfo? {
        val n = sbn.notification ?: return null
        val e = n.extras ?: return null
        // MessagingStyle (WhatsApp, Messages) carries the real text in EXTRA_MESSAGES bundles. Read only the newest
        // message: the older ones were already judged, and re-judging the thread would re-ingest them.
        val bundles = e.getParcelableArray(Notification.EXTRA_MESSAGES)?.filterIsInstance<Bundle>().orEmpty()
        val newest = NewestMessage.pick(bundles.map { it.getCharSequence("text")?.toString() to it.getLong("time", 0L) }, sbn.postTime)
        // A thread whose newest entry is blank (photo, voice) yields "" (the mapper drops it), not the BIG_TEXT of the whole thread.
        val text = newest?.first
            ?: if (bundles.isNotEmpty()) "" else (e.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: e.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        return NotificationInfo(
            sbn.packageName,
            e.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty(),
            text,
            ongoing = n.flags and Notification.FLAG_ONGOING_EVENT != 0,
            groupSummary = n.flags and Notification.FLAG_GROUP_SUMMARY != 0,
            postTime = sbn.postTime,
            category = n.category,
            messageTsMs = newest?.second ?: sbn.postTime,
        )
    }

    private companion object { const val TAG = "ScamShield/NotifListener" }
}
