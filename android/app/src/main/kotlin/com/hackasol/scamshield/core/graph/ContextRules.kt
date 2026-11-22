package com.hackasol.scamshield.core.graph

import com.hackasol.scamshield.core.UnicodeRegex

/** `suppress` = delivery call matches a recent out-for-delivery event; it never lowers a verdict by itself. */
data class ContextOutcome(val flags: List<ContextFlag>, val suppress: Boolean = false)

object ContextRules {
    // [VERIFY] RBI/NPCI mistaken-transfer wording.
    const val MISTAKEN_A_TEXT = "No money arrived. This SMS is not from your bank."
    const val MISTAKEN_B_TEXT = "This money may be stolen. Returning it yourself can get your account frozen. " +
        "Ask them to request a reversal through their bank; contact your bank / 1930."
    const val MISTAKEN_A_COLD_TEXT = "No credit alert on record since ScamShield was installed. " +
        "Check your bank app before returning anything."
    // [VERIFY] a real credit SMS should be recent; 24 h is a heuristic.
    const val CREDIT_WINDOW_MS = 24L * 60 * 60 * 1000
    // [VERIFY] banks call from the 1600 series (1600xxxxxx).
    const val BANK_CALL_PREFIX = "1600"
    const val NON_1600_TEXT = "Banks call from 1600 numbers. This caller uses a normal mobile number."
    // [VERIFY] out-for-delivery event counts for ~2 h.
    const val DELIVERY_WINDOW_MS = 2L * 60 * 60 * 1000
    const val DELIVERY_UNVERIFIED_TEXT = "No out-for-delivery message from this courier on record, but the call is about a delivery."
    // [VERIFY] delivery-call phrasing.
    private val DELIVERY_CALL = UnicodeRegex.of("\\b(?:delivery|deliver|parcel|courier|package)\\b|डिलीवरी|पार्सल")
    private val MISTAKE = UnicodeRegex.of("by mistake|mistakenly|wrong(?:ly)?\\s+(?:number|account|upi|person)|galti se|गलती से")
    private val RETURN_ASK = UnicodeRegex.of("\\b(?:return|refund|send back|give back|transfer back|wapas)\\b|वापस|लौटा")

    /** "I sent money by mistake, return it": A = no recent CREDIT event (fake credit), B = real CREDIT event (warn). */
    fun mistakenTransfer(text: String, graph: KnowledgeGraph, nowMs: Long): List<ContextFlag> {
        if (!MISTAKE.containsMatchIn(text) || !RETURN_ASK.containsMatchIn(text)) return emptyList()
        return if (graph.hasAnyEvent(EventType.CREDIT, nowMs - CREDIT_WINDOW_MS)) {
            listOf(ContextFlag(FlagKind.RETURN_VIA_BANK_ONLY, MISTAKEN_B_TEXT))
        } else {
            listOf(ContextFlag(FlagKind.FAKE_CREDIT, if (graph.isEmpty) MISTAKEN_A_COLD_TEXT else MISTAKEN_A_TEXT))
        }
    }

    /** Bank/financial caller not on the 1600 series. Blank or hidden caller number: no verdict from this rule. */
    fun bankCall(callerNumber: String, callText: String): List<ContextFlag> {
        if (!ClaimParsers.mentionsBank(callText)) return emptyList()
        val d = callerNumber.filter { it.isDigit() }
        if (d.isEmpty()) return emptyList()
        val national = when {
            d.length == 12 && d.startsWith("91") -> d.drop(2)
            d.length == 11 && d.startsWith("0") -> d.drop(1)
            else -> d
        }
        return if (national.startsWith(BANK_CALL_PREFIX)) emptyList()
        else listOf(ContextFlag(FlagKind.NON_1600_BANK_CALL, NON_1600_TEXT))
    }

    /** Delivery call: out-for-delivery event for that courier within the window -> suppress; none -> flag. */
    fun delivery(callText: String, graph: KnowledgeGraph, nowMs: Long): ContextOutcome {
        if (!DELIVERY_CALL.containsMatchIn(callText)) return ContextOutcome(emptyList())
        val since = nowMs - DELIVERY_WINDOW_MS
        val courier = ClaimParsers.brandFromText(callText)
        val seen = if (courier != null) graph.hasEvent(courier, EventType.OUT_FOR_DELIVERY, since)
        else graph.hasAnyEvent(EventType.OUT_FOR_DELIVERY, since)
        if (seen) return ContextOutcome(emptyList(), suppress = true)
        val reason = graph.coldStartNote?.let { "$it: cannot confirm this delivery." } ?: DELIVERY_UNVERIFIED_TEXT
        return ContextOutcome(listOf(ContextFlag(FlagKind.UNVERIFIED_DELIVERY, reason)))
    }
}
