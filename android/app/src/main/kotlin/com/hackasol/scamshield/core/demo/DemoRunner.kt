package com.hackasol.scamshield.core.demo

import com.hackasol.scamshield.core.AlertNotificationMapper
import com.hackasol.scamshield.core.AlertPolicy
import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.Fusion
import com.hackasol.scamshield.core.GemmaPrompt
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.LlmResult
import com.hackasol.scamshield.core.Pipeline
import com.hackasol.scamshield.core.RecordingPipeline
import com.hackasol.scamshield.core.RuleScorer
import com.hackasol.scamshield.core.ScamType
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.SttSegment
import com.hackasol.scamshield.core.Totp
import com.hackasol.scamshield.core.UpiQr
import com.hackasol.scamshield.core.Verdict
import com.hackasol.scamshield.core.VerdictEvent
import com.hackasol.scamshield.core.VerdictLog
import com.hackasol.scamshield.core.graph.ClaimParsers
import com.hackasol.scamshield.core.graph.FlagKind
import com.hackasol.scamshield.core.graph.GraphContext
import com.hackasol.scamshield.core.graph.KnowledgeGraph
import kotlinx.coroutines.runBlocking

/** Same shape as GemmaClassifier.classify; null = no model answer (rules only for that step). */
typealias DemoClassify = suspend (text: String, source: Source, context: List<String>, contextLabel: String) -> LlmResult?

data class GemmaOut(val label: Label, val scamType: ScamType?, val reason: String)
data class FusedOut(val label: Label, val confidence: Double, val scamType: ScamType?, val raisedBy: List<String>, val reason: String)
data class AlertOut(val title: String, val text: String, val reportAction: Boolean)

data class DemoStepResult(
    val index: Int,
    val delayMs: Long,
    val source: Source,
    val sender: String,
    val text: String,
    val contextLines: List<String>,
    val ruleTriggers: List<String>,
    val gemma: GemmaOut?,
    val fused: FusedOut,
    val alert: AlertOut?,
    /** A live caption would show the overlay bubble (no notification, so [alert] is null). */
    val bubble: Boolean,
    val expectedLabel: Label,
    val expectedFlags: Set<FlagKind>,
    val actualFlags: List<FlagKind>,
    val notes: List<String>,
    val pass: Boolean,
    /** Not sent over the channel: the channel feeds it (with [shown]) to AlertDispatcher. */
    val verdict: Verdict,
    val shown: Label,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "index" to index, "delayMs" to delayMs, "source" to source.name.lowercase(), "sender" to sender, "text" to text,
        "contextLines" to contextLines, "ruleTriggers" to ruleTriggers,
        "gemma" to gemma?.let { mapOf("label" to it.label.name, "scamType" to it.scamType?.name, "reason" to it.reason) },
        "fused" to mapOf(
            "label" to fused.label.name, "confidence" to fused.confidence, "scamType" to fused.scamType?.name,
            "raisedBy" to fused.raisedBy, "reason" to fused.reason,
        ),
        "alert" to alert?.let { mapOf("title" to it.title, "text" to it.text, "reportAction" to it.reportAction) },
        "bubble" to bubble, "notes" to notes,
        "expectedLabel" to expectedLabel.name, "expectedFlags" to expectedFlags.map { it.name }.sorted(),
        "actualFlags" to actualFlags.map { it.name }, "pass" to pass,
    )
}

data class DemoRunResult(
    val scenarioId: String,
    val engineUsed: String,
    val note: String?,
    val steps: List<DemoStepResult>,
    val pass: Boolean,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "scenarioId" to scenarioId, "engineUsed" to engineUsed, "note" to note,
        "steps" to steps.map { it.toMap() }, "pass" to pass,
    )
}

/**
 * Drives scripted synthetic events through the real decision path: GraphContext.forMessage/flagsFor (+ ContextRules
 * bankCall/delivery for call sources) -> RuleScorer + [classify] -> Pipeline.decide (Fusion.fuse + raiseForContext)
 * -> [log] -> AlertPolicy/AlertNotificationMapper. Check-before-ingest, as in ListenerWiring. Call sources are not
 * ingested (live captions are not, in the app).
 *
 * Isolation: only [graph] and [log] (injected, the demo's own) are touched; pass a FRESH graph per run, because
 * scenarios must not see each other's events. [classify] null = rules mode.
 */
class DemoRunner(
    private val graph: KnowledgeGraph,
    private val log: VerdictLog,
    private val classify: DemoClassify? = null,
    private val clock: () -> Long = System::currentTimeMillis,
    private val titlePrefix: String = "[DEMO] ",
) {
    private class Decision(
        val lines: List<String>, val flags: List<FlagKind>, val ruleTriggers: List<String>,
        val llm: LlmResult?, val fused: FusedOut, val verdict: Verdict, val notes: List<String>, val text: String,
    )

    suspend fun run(s: DemoScenario, coldStart: Boolean = s.coldStartDefault, note: String? = null): DemoRunResult {
        val base = clock()
        if (!coldStart) DemoScenarios.WARM_SEED.forEach { (sender, text) -> graph.ingest(text, sender, base - DemoScenarios.SEED_AGE_MS) }
        var t = base
        val times = s.steps.map { t += it.delayMs; t }
        val strict = coldStart == s.coldStartDefault
        val extra = mutableListOf<String>()
        val results: List<DemoStepResult> =
            if (s.steps.isNotEmpty() && s.steps.all { it.source == Source.RECORDING && it.kind == StepKind.TEXT }) {
                val r = runRecording(s, times, strict)
                if (r.size != s.steps.size) extra += "Recording segmentation produced ${r.size} statements, expected ${s.steps.size}"
                r
            } else {
                s.steps.mapIndexed { i, st ->
                    val d = decide(st, times[i])
                    toResult(i, st, d, d.fused.label, strict)
                }
            }
        val textSteps = results.filterIndexed { i, _ -> s.steps.getOrNull(i)?.kind == StepKind.TEXT }
        val misses = if (classify == null) 0 else textSteps.count { it.gemma == null }
        if (misses > 0) extra += "Model gave no answer for $misses step(s); rules used there"
        if (!strict) extra += "Graph mode differs from the scenario default: expectations relaxed"
        val engine = if (results.any { it.gemma != null }) "gemma" else "rules"
        val allNotes = listOfNotNull(note) + extra
        return DemoRunResult(s.id, engine, allNotes.joinToString("; ").ifEmpty { null }, results,
            results.all { it.pass } && extra.none { it.startsWith("Recording") })
    }

    private suspend fun decide(step: DemoStep, now: Long): Decision = when (step.kind) {
        StepKind.TEXT -> decideText(step, now)
        StepKind.QR -> decideQr(step, now)
        StepKind.FAMILY -> decideFamily(step, now)
    }

    private suspend fun decideText(step: DemoStep, now: Long): Decision {
        val isCall = Pipeline.isCall(step.source)
        val sender = if (step.source == Source.SMS) step.senderId else ""
        val notes = mutableListOf<String>()
        // Same composition as the app: SMS = ListenerWiring (graph lines + flags), calls = TextApi (Pipeline.withCallContext).
        val req = if (isCall) {
            if (Pipeline.callContext(step.text, step.senderId, step.source, graph, now).suppress)
                notes += "Delivery call matches a recent out-for-delivery message: not flagged"
            Pipeline.withCallContext(ClassifyRequest(step.text, source = step.source), graph, now, step.senderId)
        } else {
            val lines = GraphContext.forMessage(ClaimParsers.parse(step.text, sender), graph, now, sender)
            ClassifyRequest(step.text, lines, step.source,
                if (lines.isEmpty()) GemmaPrompt.CALL_CONTEXT_LABEL else GraphContext.LABEL,
                GraphContext.flagsFor(step.text, sender, graph, now))
        }
        val flags = req.contextFlags
        val lines = req.context
        val rules = RuleScorer.score(step.text)
        val llm = try {
            classify?.invoke(step.text, step.source, lines, req.contextLabel)
        } finally {
            if (!isCall) graph.ingest(step.text, sender, now)   // after the check, never before
        }
        val pre = Fusion.fuse(llm, rules, RuleScorer.scamType(step.text))
        val f = Pipeline.decide(step.text, rules, llm, flags)
        val raisedBy = buildList {
            if (llm != null && pre.label.ordinal > llm.label.ordinal) add("RULES")
            if (f.label != pre.label) addAll(flags.map { it.kind.name }.distinct())
        }
        log.append(VerdictEvent(0, now, step.source, f.label, f.confidence, f.scamType, f.triggers, f.engine))
        val v = Verdict(step.text, f.label, f.confidence, f.reason, f.triggers, f.engine, 0, step.source, scamType = f.scamType)
        return Decision(lines, flags.map { it.kind }.distinct(), rules.triggers, llm,
            FusedOut(f.label, f.confidence, f.scamType, raisedBy, f.reason), v, notes, step.text)
    }

    /** Same checks as TextApi.upiCheck (Pipeline.upiRisk); the SLM is not involved. */
    private fun decideQr(step: DemoStep, now: Long): Decision {
        val qr = UpiQr.parse(step.text)
        val risk = qr?.let { Pipeline.upiRisk(it, step.arg) }
        val lines = listOfNotNull(qr?.payFraming(), step.arg?.let { "Name you were told: $it" })
        if (risk != null) log.append(VerdictEvent(0, now, step.source, risk.label, risk.confidence, ScamType.FAKE_QR, risk.triggers, "upi-check"))
        val fused = if (risk != null) {
            FusedOut(risk.label, risk.confidence, ScamType.FAKE_QR, risk.triggers,
                if (risk.label == Label.SCAM) UpiQr.NAME_MISMATCH_WARNING else UpiQr.COLLECT_REQUEST_WARNING)
        } else FusedOut(Label.SAFE, 0.9, null, emptyList(), "UPI ID and name match what you were told")
        val v = Verdict(step.text, fused.label, fused.confidence, fused.reason, risk?.triggers.orEmpty(), "upi-check", 0, step.source, scamType = fused.scamType)
        return Decision(lines, emptyList(), risk?.triggers.orEmpty(), null, fused, v, emptyList(), step.text)
    }

    /** Family code via Totp. Demo-only verdict: not logged and not part of the real pipeline (the app asks "does it match?"). */
    private fun decideFamily(step: DemoStep, now: Long): Decision {
        val secret = DemoScenarios.FAMILY_DEMO_SECRET
        val real = Totp.code(secret, now)
        val claimed = if (step.arg == "match") real else ((real.toInt() + 1) % 1_000_000).toString().padStart(6, '0')
        val match = Totp.verify(secret, claimed, now)
        val text = step.text.replace("{code}", claimed)
        val lines = listOf(
            "Code on your paired phone: $real", "Code the caller read out: $claimed",
            if (match) "Codes match: this is your paired family member" else "Codes do NOT match: not your paired family member",
        )
        val fused = if (match) FusedOut(Label.SAFE, 0.95, null, emptyList(), "Family code matches")
        else FusedOut(Label.SUSPICIOUS, 0.85, ScamType.OTHER, listOf("FAMILY_CODE_MISMATCH"), "Family code does not match: do not send money")
        val v = Verdict(text, fused.label, fused.confidence, fused.reason, emptyList(), "totp", 0, step.source, scamType = fused.scamType)
        return Decision(lines, emptyList(), emptyList(), null, fused, v, emptyList(), text)
    }

    /**
     * Whole-script path through the real RecordingPipeline (segmenter + CallRiskTracker). Each scripted statement is one
     * sentence ending in a terminator, so statements map 1:1 to steps in order. Blocks the calling (background) thread
     * because RecordingPipeline's classify is not suspend. shortcut: assumes 1:1 statements, the caller flags a mismatch.
     */
    private fun runRecording(s: DemoScenario, times: List<Long>, strict: Boolean): List<DemoStepResult> {
        val captured = mutableListOf<Decision>()
        var now = times.first()
        val pipeline = RecordingPipeline({ text, _ ->
            val step = (s.steps.getOrNull(captured.size) ?: s.steps.last()).copy(text = text)
            val d = runBlocking { decide(step, now) }
            captured += d
            d.verdict
        })
        s.steps.forEachIndexed { i, st -> now = times[i]; pipeline.onSegment(SttSegment(st.text, times[i])) }
        val report = pipeline.finish()
        return captured.mapIndexed { i, d ->
            toResult(i, s.steps.getOrElse(i) { s.steps.last() }, d, report.perStatement.getOrNull(i)?.shown ?: d.fused.label, strict)
        }
    }

    private fun toResult(i: Int, step: DemoStep, d: Decision, shown: Label, strict: Boolean): DemoStepResult {
        val sv = d.verdict.copy(label = shown)
        val plan = AlertPolicy.plan(sv, sv.source)
        val fields = AlertNotificationMapper.fields(plan, sv, sv.scamType)
        val alert = fields?.let { AlertOut(titlePrefix + it.title, it.text, plan.reportAction) }
        val actual = d.fused.label
        val labelOk = if (step.expectedLabel == Label.SAFE) actual == Label.SAFE else actual.ordinal >= step.expectedLabel.ordinal
        val pass = if (strict) labelOk && step.expectedFlags == d.flags.toSet()
        else step.expectedLabel != Label.SAFE || actual == Label.SAFE   // cold/warm switched: only "SAFE stays SAFE" is enforced
        return DemoStepResult(
            i, step.delayMs, step.source, step.senderId, d.text, d.lines, d.ruleTriggers,
            d.llm?.let { GemmaOut(it.label, it.scamType, it.reason) }, d.fused, alert, plan.bubble,
            step.expectedLabel, step.expectedFlags, d.flags, d.notes, pass, d.verdict, shown,
        )
    }
}
