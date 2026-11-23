package com.hackasol.scamshield.core.graph

/**
 * Graph facts for one incoming message, as short lines for the Gemma prompt (TextApi.classify `context`),
 * plus the rule flags that may raise the verdict. Pure. Call both BEFORE `graph.ingest(message)`, otherwise
 * the message is compared against itself. Lines contain extracted entities only, never raw message text.
 */
object GraphContext {
    /** Prompt label for these lines (GemmaPrompt renders `<label>: "a" | "b"`). */
    const val LABEL = "Known context"
    /** GemmaPrompt keeps only the last 2 context entries, so more would be silently dropped. */
    const val MAX_ITEMS = 2
    const val MAX_ITEM_CHARS = 150
    const val SENDER_FIRST_TEXT = "Sender history: first message from this sender"

    const val REPORTED_LINE = "User reported this sender/number/UPI as scam"
    const val TRUSTED_LINE = "Sender is marked trusted by the user"

    /** [trustKey] is the key for trust/report lookups when it differs from [sender] (WhatsApp: "wa:" + contact name). */
    fun forMessage(claims: Claims, graph: KnowledgeGraph, nowMs: Long, sender: String = "", trustKey: String = sender): List<String> {
        graph.coldStartNote?.let { return listOf(it) }
        val out = mutableListOf<String>()
        if (graph.reportedIn(trustKey, claims)) out += REPORTED_LINE
        else if (trustKey.isNotBlank() && graph.isTrusted(trustKey)) out += TRUSTED_LINE
        val brand = claims.brand
        val wanted = when {
            claims.claimsOrder -> EventType.ORDER
            claims.claimsBill -> EventType.BILL
            else -> null
        }
        if (brand != null && wanted != null) {
            val last = graph.eventsFor(brand).filter { it.type == wanted }.maxByOrNull { it.tsMs }
            out += if (last == null) "No ${wanted.name} event from $brand since install"
            else "Last ${wanted.name} event from $brand: ${ago(nowMs - last.tsMs)}"
        }
        if (sender.isNotBlank() && !graph.knownSender(sender)) out += SENDER_FIRST_TEXT
        return out.map { it.take(MAX_ITEM_CHARS) }.take(MAX_ITEMS)
    }

    /**
     * Claim-vs-context flags plus the mistaken-transfer rule. A "no matching event" flag is dropped when it
     * would be false certainty: an empty graph (Gemma sees the cold-start line instead), or the message is itself
     * an event report from a DLT header (it is the event, it cannot have a predecessor).
     */
    fun flagsFor(message: String, sender: String, graph: KnowledgeGraph, nowMs: Long, trustKey: String = sender): List<ContextFlag> {
        val s = sender.trim()
        val tk = trustKey.trim()
        var flags = ClaimVsContext.check(message, s, graph)
        if (graph.isEmpty || (ClaimVsContext.isDltHeader(s) && ClaimParsers.eventTypes(message).isNotEmpty())) {
            flags = flags.filter { it.kind != FlagKind.NO_MATCHING_EVENT }
        }
        // One weak "unknown link" flag at most: N unknown links must not stack past the SAFE -> SUSPICIOUS threshold.
        val firstLink = flags.firstOrNull { it.kind == FlagKind.LINK_NOT_ALLOWLISTED }
        flags = flags.filter { it.kind != FlagKind.LINK_NOT_ALLOWLISTED || it === firstLink }
        // Cold graph: weak signals (normal number, unknown link) are what every new user's first messages look like;
        // stacked, they would raise SAFE to SUSPICIOUS on no real evidence.
        if (graph.isEmpty) flags = flags.filter { it.kind != FlagKind.NON_DLT_SENDER && it.kind != FlagKind.LINK_NOT_ALLOWLISTED }
        // A sender the user marked safe: drop the weak "unknown" signals (raise-only layer, so not raising is allowed).
        // REPORTED_ENTITY, FAKE_CREDIT, LOOKALIKE_LINK and DEBIT_SCARE are never dropped.
        if (tk.isNotEmpty() && graph.isTrusted(tk)) {
            flags = flags.filter { it.kind !in TRUSTED_DROPS }
        }
        val claims = ClaimParsers.parse(message, s)
        val extra = buildList {
            if (graph.reportedIn(tk, claims)) add(ContextFlag(FlagKind.REPORTED_ENTITY, ContextRules.REPORTED_TEXT))
            addAll(ContextRules.newUpiPay(message, tk, graph))   // newUpiPay only uses its sender for the trust lookup
            addAll(ContextRules.debitScare(message, s, graph, nowMs))
        }
        // Mistaken-transfer first: when it raises, its reason leads the alert (the weak claim flags follow).
        return ContextRules.mistakenTransfer(message, graph, nowMs) + extra + flags
    }

    private val TRUSTED_DROPS = setOf(FlagKind.NO_MATCHING_EVENT, FlagKind.NON_DLT_SENDER, FlagKind.NEW_UPI_PAY, FlagKind.LINK_NOT_ALLOWLISTED)

    private fun ago(ms: Long): String = when {
        ms < 60_000L -> "just now"
        ms < 3_600_000L -> "${ms / 60_000L} min ago"
        ms < 48 * 3_600_000L -> "${ms / 3_600_000L} h ago"
        else -> "${ms / 86_400_000L} days ago"
    }
}
