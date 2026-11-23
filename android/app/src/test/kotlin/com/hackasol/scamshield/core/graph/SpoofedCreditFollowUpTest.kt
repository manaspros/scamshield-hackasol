package com.hackasol.scamshield.core.graph

import com.hackasol.scamshield.core.FusedResult
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.LlmResult
import com.hackasol.scamshield.core.Pipeline
import com.hackasol.scamshield.core.RuleScorer
import com.hackasol.scamshield.core.ScamType
import com.hackasol.scamshield.core.Source
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Field test: a friend sent a bank-style "Rs 1000 credited ... Axis Bank" SMS from his own mobile number, then on
 * WhatsApp: "Hey, I have sent you the 1K. Can you send it back?". The SMS must be called out as not from a bank, and the
 * WhatsApp follow-up (no "by mistake" in it) must be flagged as a scam that points back at the fake SMS.
 * [post] follows ListenerWiring.onPosted: check against the graph, decide, then ingest (trusted only when SAFE).
 */
class SpoofedCreditFollowUpTest {
    private val now = 10_000_000_000L
    private val fakeSms = "Rs.1000.00 credited to your A/c XX4821 on 23-11-26 by UPI ref 633412. Avl Bal Rs 12,410.00 - Axis Bank"
    private val ask = "Hey, I have sent you the 1K. Can you send it back?"

    private fun warm() = KnowledgeGraph().also {
        it.ingest("Your OTP for login is 482913. Do not share it.", "AX-HDFCBK", now - 3_600_000L)
    }

    /** SMS: the title is the sender; WhatsApp: no sender header, trust key "wa:<name>". Model says SAFE (worst case). */
    private fun post(g: KnowledgeGraph, source: Source, title: String, text: String, ts: Long): FusedResult {
        val sender = if (source == Source.SMS) title else ""
        val key = if (source == Source.SMS) title else "wa:$title"
        val flags = GraphContext.flagsFor(text, sender, g, ts, key)
        val f = Pipeline.decide(text, RuleScorer.score(text), LlmResult(Label.SAFE, 0.9, "Normal"), flags)
        g.ingest(text, sender, ts, trusted = f.label == Label.SAFE)
        return f
    }

    @Test fun fakeBankSmsThenWhatsAppAskIsScam() {
        val g = warm()
        val sms = post(g, Source.SMS, "+91 98765 43210", fakeSms, now)
        assertEquals(Label.SUSPICIOUS, sms.label)
        assertEquals(ContextRules.SPOOFED_BANK_SMS_TEXT, sms.reason)
        // The fake credit never becomes a real CREDIT event, but it is remembered as a fake.
        assertTrue(g.recentEvents(EventType.CREDIT, 0L).isEmpty())
        assertEquals(1000.0, g.recentSpoofedCredits(0L).single().amountRupees)

        val wa = post(g, Source.WHATSAPP, "Friend", ask, now + 10 * 60_000L)
        assertEquals(Label.SCAM, wa.label)
        assertEquals(ScamType.MISTAKEN_TRANSFER, wa.scamType)
        assertEquals(ContextRules.SPOOFED_CREDIT_RETURN_TEXT, wa.reason)
    }

    @Test fun coldGraphStillCatchesIt() {
        val g = KnowledgeGraph()
        assertEquals(Label.SUSPICIOUS, post(g, Source.SMS, "9876543210", fakeSms, now).label)
        assertEquals(Label.SCAM, post(g, Source.WHATSAPP, "Friend", ask, now + 60_000L).label)
        // Past the window the fake is no longer tied to a new ask.
        assertTrue(ContextRules.mistakenTransfer(ask, g, now + ContextRules.CREDIT_WINDOW_MS + 1).isEmpty())
    }

    @Test fun sameAskOnACallIsFlaggedToo() {
        val g = warm()
        post(g, Source.SMS, "9876543210", fakeSms, now)
        val flags = Pipeline.callContext("Bhai maine aapko 1000 bhej diye, wapas kar do", "9876543210", Source.CAPTION, g, now + 60_000L).flags
        assertEquals(listOf(FlagKind.FAKE_CREDIT), flags.map { it.kind })
        assertEquals(ContextRules.SPOOFED_CREDIT_RETURN_TEXT, flags.single().reason)
    }

    @Test fun realDltCreditIsNotSpoofedAndPlainAskStaysQuiet() {
        val g = KnowledgeGraph()
        g.ingest("Rs.1000.00 credited to your A/c XX4821 by UPI ref 633412 - Axis Bank", "AX-AXISBK", now)
        assertTrue(g.recentSpoofedCredits(0L).isEmpty())
        assertTrue(ContextRules.spoofedBankSms(fakeSms, "AX-AXISBK").isEmpty())
        // A real credit of that amount: a plain "send it back" (no "by mistake") gets no fake-credit flag.
        assertTrue(ContextRules.mistakenTransfer(ask, g, now + 60_000L).isEmpty())
        // No fake SMS on record: a friend asking for money back is left to the model.
        assertTrue(ContextRules.mistakenTransfer(ask, KnowledgeGraph(), now).isEmpty())
    }

    @Test fun bankAlertShape() {
        assertEquals(setOf(FlagKind.SPOOFED_BANK_SMS), ContextRules.spoofedBankSms(fakeSms, "9876543210").map { it.kind }.toSet())
        assertEquals(setOf(FlagKind.SPOOFED_BANK_SMS), ContextRules.spoofedBankSms("आपके खाते में ₹5,000 जमा हुए।", "9800000010").map { it.kind }.toSet())
        // Friendly chat, no amount / no account: not a bank alert.
        assertTrue(ContextRules.spoofedBankSms("Salary credited finally, party tonight!", "9876543210").isEmpty())
        assertTrue(ContextRules.spoofedBankSms("Did the 500 get credited?", "9876543210").isEmpty())
        // Pasted text has no sender: no verdict from this rule.
        assertTrue(ContextRules.spoofedBankSms(fakeSms, "").isEmpty())
        assertEquals(1000.0, ClaimParsers.amountRupees("I have sent you the 1K"))
        assertFalse(ClaimParsers.amountRupees("5km away") == 5000.0)
    }
}
