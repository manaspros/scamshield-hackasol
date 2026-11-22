package com.hackasol.scamshield

import android.content.Context
import android.os.SystemClock
import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.RuleScorer
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.Verdict
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

    fun init(ctx: Context) {
        AppSettings.init(ctx)
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

    suspend fun classify(req: ClassifyRequest): Verdict {
        val t0 = SystemClock.elapsedRealtime()
        val rules = RuleScorer.score(req.text)
        val llm = if (AppSettings.useLlm) GemmaClassifier.classify(req.text, req.context) else null
        val elapsed = SystemClock.elapsedRealtime() - t0
        if (llm == null) return rulesVerdict(req, rules, elapsed)

        // Fusion: the LLM decides; strong rule evidence can only raise the label.
        var label = llm.label
        var llmConf = llm.confidence
        if (rules.score >= 0.85 && label != Label.SCAM) { label = Label.SCAM; llmConf = 0.5 }
        else if (rules.score >= RuleScorer.SUSPICIOUS_AT && label == Label.SAFE) { label = Label.SUSPICIOUS; llmConf = 0.5 }
        val confidence = (0.7 * llmConf + 0.3 * RuleScorer.support(rules, label)).coerceIn(0.0, 1.0)
        val reason = llm.reason.ifBlank { rules.reason }
        return Verdict(req.text, label, confidence, reason, rules.triggers, "gemma+rules", elapsed, req.source)
    }

    private fun rulesVerdict(req: ClassifyRequest, rules: com.hackasol.scamshield.core.RuleResult, ms: Long, preliminary: Boolean = false) =
        Verdict(req.text, rules.label, RuleScorer.confidence(rules), rules.reason, rules.triggers,
            "rules-only", ms, req.source, preliminary)

    fun requestFromMap(m: Map<*, *>) = ClassifyRequest(
        text = (m["text"] as? String).orEmpty(),
        context = (m["context"] as? List<*>)?.filterIsInstance<String>().orEmpty(),
        source = Source.parse(m["source"] as? String),
    )
}
