package com.hackasol.scamshield.core.graph

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ContextRulesTest {
    private val bank = "VM-EXAMPL-S"
    private val now = 10_000_000_000L
    private val ask = "Sorry, I sent Rs.5,000 to you by mistake, please return it to example@upi"

    private fun kinds(flags: List<ContextFlag>) = flags.map { it.kind }.toSet()

    @Test fun T5_2_fakeCreditNoMoneyArrived() {
        val g = KnowledgeGraph()
        g.ingest("Your ExampleBank bill is due", bank, now - 1000L) // non-empty graph, no CREDIT event
        val flags = ContextRules.mistakenTransfer(ask, g, now)
        assertEquals(setOf(FlagKind.FAKE_CREDIT), kinds(flags))
        assertEquals(ContextRules.MISTAKEN_A_TEXT, flags.single().reason)
        // Cold start: still flagged, but never claims certainty.
        assertEquals(ContextRules.MISTAKEN_A_COLD_TEXT, ContextRules.mistakenTransfer(ask, KnowledgeGraph(), now).single().reason)
        assertTrue(ContextRules.mistakenTransfer("Please return my book", g, now).isEmpty())
    }

    @Test fun T5_2_realCreditReturnWarning() {
        val g = KnowledgeGraph()
        g.ingest("Rs.5,000 credited to your a/c at ExampleBank", bank, now - 60_000L)
        val flags = ContextRules.mistakenTransfer(ask, g, now)
        assertEquals(setOf(FlagKind.RETURN_VIA_BANK_ONLY), kinds(flags))
        assertEquals(ContextRules.MISTAKEN_B_TEXT, flags.single().reason)
        // A credit older than the window no longer counts.
        assertEquals(setOf(FlagKind.FAKE_CREDIT), kinds(ContextRules.mistakenTransfer(ask, g, now + ContextRules.CREDIT_WINDOW_MS + 1)))
    }

    @Test fun T5_2_non1600BankCall() {
        val talk = "This is ExampleBank calling, your KYC is pending"
        assertEquals(setOf(FlagKind.NON_1600_BANK_CALL), kinds(ContextRules.bankCall("9800000001", talk)))
        assertTrue(ContextRules.bankCall("1600123456", talk).isEmpty())
        assertTrue(ContextRules.bankCall("+91 1600123456", talk).isEmpty())
        assertTrue(ContextRules.bankCall("9800000001", "Hello, is this Ravi?").isEmpty())
        assertTrue(ContextRules.bankCall("", talk).isEmpty())
    }

    @Test fun T5_2_outForDeliverySuppresses() {
        val g = KnowledgeGraph()
        g.ingest("Your ExampleCourier parcel is out for delivery", "VM-EXAMPC-S", now)
        val call = "Hi, calling from ExampleCourier about your parcel delivery"
        val ok = ContextRules.delivery(call, g, now + 30 * 60_000L)
        assertTrue(ok.suppress)
        assertTrue(ok.flags.isEmpty())

        val stale = ContextRules.delivery(call, g, now + ContextRules.DELIVERY_WINDOW_MS + 1)
        assertFalse(stale.suppress)
        assertEquals(setOf(FlagKind.UNVERIFIED_DELIVERY), kinds(stale.flags))

        val cold = ContextRules.delivery(call, KnowledgeGraph(), now)
        assertFalse(cold.suppress)
        assertTrue(cold.flags.single().reason.contains(KnowledgeGraph.COLD_START_TEXT))
        assertTrue(ContextRules.delivery("Hello, is this Ravi?", g, now).flags.isEmpty())
    }
}
