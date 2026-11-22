package com.hackasol.scamshield.core.graph

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GraphTest {
    private val bank = "VM-EXAMPL-S"
    private val billSms = "Dear customer, your ExampleBank electricity bill of Rs.1,200 is due. Pay via example@upi"

    private fun kinds(flags: List<ContextFlag>) = flags.map { it.kind }.toSet()

    @Test fun T5_1_ingestThenLookup() {
        val g = KnowledgeGraph()
        g.ingest(billSms, bank, 1000L)
        assertTrue(g.hasEvent("ExampleBank", EventType.BILL, 0L))
        assertFalse(g.hasEvent("ExampleBank", EventType.BILL, 2000L))
        assertFalse(g.hasEvent("ExampleBank", EventType.ORDER, 0L))
        assertEquals(1, g.eventsFor("ExampleBank").size)
        assertTrue(g.knownSender(bank))
        assertTrue(g.knownUpi("example@upi"))

        g.ingest("call me", "9800000001", 1100L)
        assertTrue(g.knownNumber("9800000001"))
        assertFalse(g.knownSender("9800000002"))

        // A normal number cannot create an event, even if the text says so.
        g.ingest("Your ExampleBank order is confirmed", "9800000001", 1200L)
        assertFalse(g.hasEvent("ExampleBank", EventType.ORDER, 0L))

        val c = ClaimParsers.parse(billSms, bank)
        assertEquals("examplebank", c.brand)
        assertEquals(1200.0, c.amountRupees!!, 0.001)
        assertEquals(listOf("example@upi"), c.upiIds)
        assertEquals(500.0, ClaimParsers.amountRupees("500 रुपये भेजें")!!, 0.001)
    }

    @Test fun T5_1_coldStartMessage() {
        val g = KnowledgeGraph()
        assertEquals("No record since ScamShield was installed", KnowledgeGraph.COLD_START_TEXT)
        assertTrue(g.isEmpty)
        assertEquals(KnowledgeGraph.COLD_START_TEXT, g.coldStartNote)
        assertFalse(g.hasEvent("ExampleBank", EventType.BILL, 0L))
        val flags = ClaimVsContext.check("ExampleBank bill pending, pay now", bank, g)
        assertTrue(flags.single { it.kind == FlagKind.NO_MATCHING_EVENT }.reason.contains(KnowledgeGraph.COLD_START_TEXT))
        g.ingest("hello", bank, 1L)
        assertFalse(g.isEmpty)
        assertNull(g.coldStartNote)
    }

    @Test fun T5_1_noBillEventFlags() {
        val g = KnowledgeGraph()
        g.ingest("Your ExampleCourier parcel is out for delivery", "VM-EXAMPC-S", 1000L)
        val scam = "ExampleBank electricity bill pending Rs.1,200, pay now"
        val flags = ClaimVsContext.check(scam, "9800000001", g)
        assertTrue(kinds(flags).containsAll(listOf(FlagKind.NO_MATCHING_EVENT, FlagKind.NON_DLT_SENDER)))

        g.ingest(billSms, bank, 2000L)
        val after = ClaimVsContext.check(scam, bank, g)
        assertFalse(FlagKind.NO_MATCHING_EVENT in kinds(after))
        assertFalse(FlagKind.NON_DLT_SENDER in kinds(after))
    }

    @Test fun T5_1_linkAllowlist() {
        val g = KnowledgeGraph()
        fun linkFlags(url: String) =
            ClaimVsContext.check("Visit $url", bank, g).filter { it.kind == FlagKind.LINK_NOT_ALLOWLISTED }
        assertTrue(linkFlags("https://pay.examplebank.bank.in/x").isEmpty())
        assertTrue(linkFlags("https://www.example.gov.in/refund").isEmpty())
        assertEquals(1, linkFlags("http://examplebank-kyc.xyz").size)
        assertEquals(1, linkFlags("https://examplebank.bank.in.evil.example.com/x").size)
        assertEquals(1, linkFlags("https://bank.in@evil.example.com/login").size)
        assertEquals(1, linkFlags("bit.ly/abc123").size)
        assertTrue(ClaimParsers.upiIds("pay example@upi now").isNotEmpty())
        assertTrue(ClaimParsers.links("mail a@b.com or pay example@upi").isEmpty())
    }
}
