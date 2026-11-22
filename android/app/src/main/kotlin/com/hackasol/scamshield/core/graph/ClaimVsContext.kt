package com.hackasol.scamshield.core.graph

enum class FlagKind {
    NO_MATCHING_EVENT, NON_DLT_SENDER, LINK_NOT_ALLOWLISTED,
    FAKE_CREDIT, RETURN_VIA_BANK_ONLY, NON_1600_BANK_CALL, UNVERIFIED_DELIVERY,
}

/** A reason to raise suspicion. Flags only ever raise a verdict; T5.3 wires that. */
data class ContextFlag(val kind: FlagKind, val reason: String)

object ClaimVsContext {
    // [VERIFY] TRAI DLT header: 2-letter circle prefix, 3-6 char brand, optional -P/-S/-T/-G suffix.
    // Plain Regex on purpose: ASCII-only and case-sensitive (real headers are uppercase), so no Unicode flag is needed.
    val DLT_HEADER = Regex("^[A-Z]{2}-[A-Z0-9]{3,6}(-[PSTG])?$")

    // [VERIFY] link hosts treated as official; anything else is flagged.
    val ALLOWED_LINK_SUFFIXES = listOf(".bank.in", ".gov.in")

    fun isDltHeader(sender: String): Boolean = DLT_HEADER.matches(sender.trim())

    fun isAllowedHost(host: String): Boolean = ALLOWED_LINK_SUFFIXES.any { host.endsWith(it) }

    fun check(message: String, sender: String, graph: KnowledgeGraph): List<ContextFlag> {
        val c = ClaimParsers.parse(message, sender)
        val flags = mutableListOf<ContextFlag>()

        if (c.claimsAnyEvent) {
            val brand = c.brand
            val matched = brand != null &&
                (graph.hasEvent(brand, EventType.BILL, 0L) || graph.hasEvent(brand, EventType.ORDER, 0L))
            if (!matched) {
                val reason = graph.coldStartNote?.let { "$it: cannot confirm this bill, order or payment." }
                    ?: "No bill or order from ${brand ?: "this sender"} on record, but this message claims one."
                flags += ContextFlag(FlagKind.NO_MATCHING_EVENT, reason)
            }
        }

        // Blank sender = pasted text with no header to judge.
        if (sender.isNotBlank() && !isDltHeader(sender)) {
            flags += ContextFlag(FlagKind.NON_DLT_SENDER, "Sent from a normal number, not a registered sender header.")
        }

        c.links.map { ClaimParsers.host(it) }.distinct().filter { !isAllowedHost(it) }.forEach {
            flags += ContextFlag(FlagKind.LINK_NOT_ALLOWLISTED, "Link goes to $it, not a .bank.in or .gov.in site.")
        }
        return flags
    }
}
