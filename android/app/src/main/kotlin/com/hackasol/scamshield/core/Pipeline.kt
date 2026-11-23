package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.graph.ClaimParsers
import com.hackasol.scamshield.core.graph.ContextFlag
import com.hackasol.scamshield.core.graph.ContextOutcome
import com.hackasol.scamshield.core.graph.ContextRules
import com.hackasol.scamshield.core.graph.GraphContext
import com.hackasol.scamshield.core.graph.KnowledgeGraph

/** A QR/UPI check hit: label + confidence + triggers, ready to log. Null from [Pipeline.upiRisk] means clean. */
data class UpiRisk(val label: Label, val confidence: Double, val triggers: List<String>)

/**
 * The decision steps shared by TextApi and the Demo Lab, so the lab cannot drift from the real pipeline.
 * Pure; the callers do the I/O (classify, log, alert).
 */
object Pipeline {
    /** SLM label + rules (rules only raise), then claim-vs-context / context rules raise one step. */
    fun decide(text: String, rules: RuleResult, llm: LlmResult?, flags: List<ContextFlag>): FusedResult =
        Fusion.raiseForContext(Fusion.fuse(llm, rules, RuleScorer.scamType(text)), flags)

    /** Call sources: live captions and recorded calls. Only these get the call-side context rules. */
    fun isCall(source: Source): Boolean = source == Source.CAPTION || source == Source.RECORDING

    /**
     * Call-side context rules: mistaken-transfer, bank caller not on 1600 (blank/unknown [caller] = no verdict),
     * delivery call vs out-for-delivery event. Not claim-vs-context: ordinary calls mention bills and payments.
     */
    fun callContext(text: String, caller: String?, source: Source, graph: KnowledgeGraph, nowMs: Long): ContextOutcome {
        if (!isCall(source)) return ContextOutcome(emptyList())
        val delivery = ContextRules.delivery(text, graph, nowMs)
        return ContextOutcome(
            ContextRules.mistakenTransfer(text, graph, nowMs) + ContextRules.bankCall(caller.orEmpty(), text) + delivery.flags,
            delivery.suppress,
        )
    }

    /**
     * Adds [callContext] flags to a call request, and graph lines when the graph is warm and the request has no
     * "Earlier in this call" context of its own. Other sources are returned untouched.
     */
    fun withCallContext(req: ClassifyRequest, graph: KnowledgeGraph, nowMs: Long, caller: String? = null): ClassifyRequest {
        if (!isCall(req.source)) return req
        val flags = req.contextFlags + callContext(req.text, caller, req.source, graph, nowMs).flags
        val lines = if (req.context.isEmpty() && !graph.isEmpty) GraphContext.forMessage(ClaimParsers.parse(req.text), graph, nowMs) else emptyList()
        return if (lines.isEmpty()) req.copy(contextFlags = flags)
        else req.copy(context = lines, contextLabel = GraphContext.LABEL, contextFlags = flags)
    }

    /** Name mismatch -> SCAM 0.9; collect request alone -> SUSPICIOUS 0.7; neither -> null. */
    fun upiRisk(qr: UpiQr, expectedName: String?): UpiRisk? {
        val mismatch = qr.nameMismatch(expectedName)
        val triggers = buildList {
            if (mismatch) add("upi name mismatch")
            if (qr.isCollectRequest) add("upi collect request")
        }
        if (triggers.isEmpty()) return null
        return UpiRisk(if (mismatch) Label.SCAM else Label.SUSPICIOUS, if (mismatch) 0.9 else 0.7, triggers)
    }
}
