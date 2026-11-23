package com.hackasol.scamshield

import android.content.Context
import android.os.SystemClock
import com.hackasol.scamshield.core.CallContext
import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.DataReset
import com.hackasol.scamshield.core.Fusion
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.Pipeline
import com.hackasol.scamshield.core.graph.KnowledgeGraph
import com.hackasol.scamshield.core.graph.PersistentKnowledgeGraph
import com.hackasol.scamshield.core.RuleScorer
import com.hackasol.scamshield.core.ScamType
import com.hackasol.scamshield.core.UpiQr
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.Verdict
import com.hackasol.scamshield.core.VerdictEvent
import com.hackasol.scamshield.core.VerdictLog
import kotlinx.coroutines.withContext
import android.util.Log
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch

/**
 * The single "text API": text in -> Verdict (SAFE/SUSPICIOUS/SCAM + confidence + reason) out.
 * Used by live captions, the Flutter "Try API" screen and (later) SMS/WhatsApp sharing.
 */
object TextApi {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default +
        CoroutineExceptionHandler { _, t -> Log.e("ScamShield/TextApi", "uncaught", t) })

    // Live captions: CONFLATED = if Gemma is busy, only the newest pending statement is kept.
    private val captionQueue = Channel<Pair<ClassifyRequest, (Verdict) -> Unit>>(Channel.CONFLATED)
    @Volatile private var started = false

    /** Shared verdict log; created once in init() (MainActivity and the accessibility service both call it). */
    @Volatile var verdictLog: VerdictLog? = null
        private set

    @Volatile private var appContext: Context? = null
    @Volatile private var sharedGraph: KnowledgeGraph? = null
    // Own lock: the DB load in graph() must never block init() (which takes the TextApi monitor) on the main thread.
    private val graphLock = Any()

    /**
     * The one knowledge graph (graph.db), shared by the notification listener and the call-caption path.
     * Opened lazily, so call it off the main thread (PersistentKnowledgeGraph loads the DB in its constructor).
     */
    fun graph(ctx: Context): KnowledgeGraph = sharedGraph ?: synchronized(graphLock) {
        sharedGraph ?: PersistentKnowledgeGraph(SqliteKnowledgeGraph(ctx.applicationContext)).also { sharedGraph = it }
    }

    fun init(ctx: Context) {
        appContext = ctx.applicationContext
        AppSettings.init(ctx)
        if (verdictLog == null) synchronized(this) {
            if (verdictLog == null) verdictLog = SqliteVerdictLog(ctx.applicationContext)
        }
        if (AppSettings.useLlm) GemmaClassifier.ensureLoaded(ctx)
        ModelDownloader.watch(ctx)   // resume progress tracking of a download started earlier
        if (started) return
        synchronized(this) {
            if (started) return
            started = true
            scope.launch {
                for ((req, cb) in captionQueue) {
                    try {
                        val rules = RuleScorer.score(req.text, AppSettings.lang)
                        // Instant rules-only warning while the LLM thinks.
                        if (rules.label != Label.SAFE) cb(rulesVerdict(req, rules, 0, preliminary = true))
                        cb(classify(req))
                    } catch (t: Throwable) {
                        Log.e("ScamShield/TextApi", "caption classify failed", t)
                    }
                }
            }
        }
    }

    fun submitCaption(req: ClassifyRequest, onResult: (Verdict) -> Unit) {
        captionQueue.trySend(req to onResult)
    }

    suspend fun classify(req: ClassifyRequest): Verdict = classifyLogged(req).first

    /** Like [classify], plus the timestamp the verdict was logged under (the key "This was a scam / safe" feedback uses). */
    suspend fun classifyLogged(req: ClassifyRequest): Pair<Verdict, Long> {
        val v = classifyUnlogged(req)
        return v to record(v)
    }

    /** "Delete my data": the shared graph (memory and graph.db); with [alsoAlerts] also the real verdict log. False if any delete failed. Off the main thread. */
    fun deleteMyData(ctx: Context, alsoAlerts: Boolean) = DataReset.run(graph(ctx), verdictLog, alsoAlerts)

    /** "This was a scam" / "this is safe" on a past alert, by its log timestamp. False when nothing was recorded for that alert (calls and pasted text have no sender). */
    fun feedback(ctx: Context, tsMs: Long, scam: Boolean): Boolean = graph(ctx).feedback(tsMs, scam, System.currentTimeMillis())

    /** Final results only; the preliminary rules-only caption warning is followed by a final result that is logged. Returns the logged ts. */
    private suspend fun record(v: Verdict): Long {
        val ts = System.currentTimeMillis()
        append(VerdictEvent(0, ts, v.source, v.label, v.confidence, v.scamType, v.triggers, v.engine))
        return ts
    }

    private suspend fun append(e: VerdictEvent) {
        val log = verdictLog ?: return
        try {
            withContext(Dispatchers.IO) { log.append(e) }
        } catch (t: Throwable) {
            Log.e("ScamShield/TextApi", "verdict log append failed", t)
        }
    }

    /**
     * Fake-QR check (T4.2). Parsing, name mismatch and the English framing come from core UpiQr.
     * A mismatch (SCAM) or collect request (SUSPICIOUS) logs one FAKE_QR event; it holds no link, VPA or name.
     */
    suspend fun upiCheck(link: String, expectedName: String?): Map<String, Any?> {
        val qr = UpiQr.parse(link) ?: return mapOf("valid" to false)
        val mismatch = qr.nameMismatch(expectedName)
        Pipeline.upiRisk(qr, expectedName)?.let {
            append(VerdictEvent(0, System.currentTimeMillis(), Source.PASTE, it.label, it.confidence, ScamType.FAKE_QR, it.triggers, "upi-check"))
        }
        return mapOf(
            "valid" to true,
            "payeeName" to qr.payeeName,
            "payeeVpa" to qr.payeeAddress, // the counterparty's id, shown whole: masking it hides the warning sign
            "amount" to qr.amount,
            "amountDisplay" to qr.displayAmount(),
            "isCollect" to qr.isCollectRequest,
            "mismatch" to mismatch,
            "riskyPayee" to qr.hasRiskyPayee(),
            "framing" to qr.payFramingEn(),
            "framingHi" to qr.payFramingHi(),
        )
    }

    private suspend fun classifyUnlogged(req0: ClassifyRequest): Verdict {
        val t0 = SystemClock.elapsedRealtime()
        // Calls (captions, recordings) get the call-side context rules from the shared graph; the caller number comes
        // from the dialer notification (null for a saved contact or when none is showing).
        val req = if (Pipeline.isCall(req0.source)) {
            val g = withContext(Dispatchers.IO) { appContext?.let(::graph) }
            val now = System.currentTimeMillis()
            if (g == null) req0 else Pipeline.withCallContext(req0, g, now, CallContext.caller(now))
        } else req0
        val rules = RuleScorer.score(req.text, AppSettings.lang)
        val llm = if (AppSettings.useLlm) GemmaClassifier.classify(req.text, req.context, req.contextLabel) else null
        val elapsed = SystemClock.elapsedRealtime() - t0
        val f = Pipeline.decide(req.text, rules, llm, req.contextFlags, AppSettings.lang)
        return Verdict(req.text, f.label, f.confidence, f.reason, f.triggers, f.engine, elapsed, req.source, scamType = f.scamType)
    }

    private fun rulesVerdict(req: ClassifyRequest, rules: com.hackasol.scamshield.core.RuleResult, ms: Long, preliminary: Boolean = false): Verdict {
        val f = Fusion.fuse(null, rules, RuleScorer.scamType(req.text))
        return Verdict(req.text, f.label, f.confidence, f.reason, f.triggers, f.engine, ms, req.source, preliminary, f.scamType)
    }

    fun requestFromMap(m: Map<*, *>) = ClassifyRequest(
        text = (m["text"] as? String).orEmpty(),
        context = (m["context"] as? List<*>)?.filterIsInstance<String>().orEmpty(),
        source = Source.parse(m["source"] as? String),
    )
}
