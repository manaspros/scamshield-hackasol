package com.hackasol.scamshield

import android.content.Context
import android.os.SystemClock
import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.Fusion
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.RuleScorer
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

    fun init(ctx: Context) {
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
                        val rules = RuleScorer.score(req.text)
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

    suspend fun classify(req: ClassifyRequest): Verdict = classifyUnlogged(req).also { record(it) }

    /** Final results only; the preliminary rules-only caption warning is followed by a final result that is logged. */
    private suspend fun record(v: Verdict) {
        val log = verdictLog ?: return
        try {
            // scamType is null until T1.15 adds Verdict.scamType.
            val e = VerdictEvent(0, System.currentTimeMillis(), v.source, v.label, v.confidence, null, v.triggers, v.engine)
            withContext(Dispatchers.IO) { log.append(e) }
        } catch (t: Throwable) {
            Log.e("ScamShield/TextApi", "verdict log append failed", t)
        }
    }

    private suspend fun classifyUnlogged(req: ClassifyRequest): Verdict {
        val t0 = SystemClock.elapsedRealtime()
        val rules = RuleScorer.score(req.text)
        val llm = if (AppSettings.useLlm) GemmaClassifier.classify(req.text, req.context) else null
        val elapsed = SystemClock.elapsedRealtime() - t0
        val f = Fusion.fuse(llm, rules, RuleScorer.scamType(req.text))
        return Verdict(req.text, f.label, f.confidence, f.reason, f.triggers, f.engine, elapsed, req.source)
    }

    private fun rulesVerdict(req: ClassifyRequest, rules: com.hackasol.scamshield.core.RuleResult, ms: Long, preliminary: Boolean = false): Verdict {
        val f = Fusion.fuse(null, rules, null)   // type not needed until T1.15 adds Verdict.scamType
        return Verdict(req.text, f.label, f.confidence, f.reason, f.triggers, f.engine, ms, req.source, preliminary)
    }

    fun requestFromMap(m: Map<*, *>) = ClassifyRequest(
        text = (m["text"] as? String).orEmpty(),
        context = (m["context"] as? List<*>)?.filterIsInstance<String>().orEmpty(),
        source = Source.parse(m["source"] as? String),
    )
}
