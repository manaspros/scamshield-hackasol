package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.graph.AlertRef
import com.hackasol.scamshield.core.graph.Brands
import com.hackasol.scamshield.core.graph.ClaimParsers
import com.hackasol.scamshield.core.graph.ContextFlag
import com.hackasol.scamshield.core.graph.ContextRules
import com.hackasol.scamshield.core.graph.EntityKind
import com.hackasol.scamshield.core.graph.EventType
import com.hackasol.scamshield.core.graph.FlagKind
import com.hackasol.scamshield.core.graph.GraphContext
import com.hackasol.scamshield.core.graph.GraphSnapshot
import com.hackasol.scamshield.core.graph.GraphStore
import com.hackasol.scamshield.core.graph.IngestDelta
import com.hackasol.scamshield.core.graph.KnowledgeGraph
import com.hackasol.scamshield.core.graph.TrustStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Round 3 knowledge-base behaviour: real RuleScorer, Fusion/Pipeline.decide, KnowledgeGraph; synthetic data only. */
class R3KbTest {
    private val now = 1_700_000_000_000L
    private val h = 3_600_000L
    private val day = 24 * h

    private class FakeStore : GraphStore {
        val deltas = mutableListOf<IngestDelta>()
        val refs = mutableMapOf<Long, AlertRef>()
        val marks = mutableListOf<Triple<EntityKind, String, TrustStatus>>()
        var clears = 0
        var prunedCutoff: Long? = null
        override fun load() = GraphSnapshot.EMPTY
        override fun apply(delta: IngestDelta) { deltas += delta }
        override fun prune(cutoffMs: Long) { prunedCutoff = cutoffMs }
        override fun clear(): Boolean { clears++; refs.clear(); deltas.clear(); marks.clear(); return true }
        override fun mark(kind: EntityKind, key: String, status: TrustStatus, tsMs: Long) { marks += Triple(kind, key, status) }
        override fun putAlertRef(r: AlertRef) { refs[r.tsMs] = r }
        override fun alertRef(tsMs: Long) = refs[tsMs]
    }

    private fun warm(store: GraphStore? = null) = KnowledgeGraph(store) { now }.also { it.ingest("hello there friend how are you", "", now - 1) }
    private fun flags(text: String, sender: String, g: KnowledgeGraph) = GraphContext.flagsFor(text, sender, g, now)
    private fun kinds(fl: List<ContextFlag>) = fl.map { it.kind }
    private fun decide(text: String, sender: String, g: KnowledgeGraph, llm: Label = Label.SAFE): FusedResult =
        Pipeline.decide(text, RuleScorer.score(text), LlmResult(llm, 0.9, "model"), flags(text, sender, g))

    // ---- poisoning ----

    @Test fun `R3_KB_poisoning_untrustedIngestCreatesNoEventAndSenderStaysUnknown`() {
        val g = warm()
        g.ingest("Your Amazon order has been placed. Rs 500 credited. bill due", "AX-AMAZON", now - 5, trusted = false)
        g.ingest("Rs 5000 credited, pay at scam@okaxis, call 9800000077", "9800000010", now - 4, trusted = false)
        for (t in EventType.values()) assertFalse(t.name, g.hasAnyEvent(t, 0L))
        assertFalse(g.knownSender("AX-AMAZON")); assertFalse(g.knownSender("9800000010"))
        assertFalse(g.knownUpi("scam@okaxis")); assertFalse(g.knownNumber("9800000077"))
        assertTrue(kinds(flags("Your Amazon order #123 is held, pay the fee", "9800000011", g)).contains(FlagKind.NO_MATCHING_EVENT))
    }

    @Test fun `R3_KB_poisoning_untrustedIngestWritesNothingNotEvenTheColdStartCounter`() {
        val store = FakeStore(); val g = KnowledgeGraph(store) { now }
        g.ingest("Rs 5000 credited", "AX-HDFCBK", now, trusted = false)
        assertTrue(g.isEmpty)
        assertTrue(store.deltas.isEmpty())
    }

    @Test fun `R3_KB_prune_usesInjectedClockNotForgedMessageTimestamp`() {
        val store = FakeStore(); var t = now - day
        val g = KnowledgeGraph(store) { t }
        g.ingest("hello there friend how are you", "", now + 400 * day)   // forged far-future message time, clock says "day 0": no prune
        assertEquals(t - GraphStore.ENTITY_RETENTION_MS, store.prunedCutoff)   // only the startup prune ran
        t = now
        g.ingest("hello there friend how are you", "", now + 400 * day)
        assertEquals(now - GraphStore.ENTITY_RETENTION_MS, store.prunedCutoff)   // clock moved 24 h: pruned by clock time, not message time
    }

    @Test fun `R3_KB_events_headerOfOtherBrandCannotCreateEventButMatchingHeaderCan`() {
        val g = KnowledgeGraph { now }
        g.ingest("hello there friend how are you", "", now - 1)
        g.ingest("Rs 5000 credited to your HDFC a/c", "VK-PROMOX", now - 5)
        assertFalse(g.hasAnyEvent(EventType.CREDIT, 0L))
        g.ingest("Rs 5000 credited to your HDFC a/c", "AX-HDFCBK", now - 4)
        assertEquals(EventType.CREDIT, g.eventsFor("hdfcbank").single().type)
        g.ingest("Rs 700 credited to your a/c", "AX-ICICIB", now - 3)   // no brand in text: header brand
        assertEquals(EventType.CREDIT, g.eventsFor("icicibank").single().type)
    }

    // ---- lookalike / official links ----

    @Test fun `R3_KB_link_typosquatAmazonIsLookalikeAndRaisesVerdictEvenOnColdGraph`() {
        val text = "Amazon refund of Rs 499 is pending. Claim now: amaz0n-refund.xyz/claim"
        for (g in listOf(warm(), KnowledgeGraph())) {
            val k = kinds(flags(text, "9800000010", g))
            assertTrue(k.toString(), FlagKind.LOOKALIKE_LINK in k)
            assertFalse(FlagKind.LINK_NOT_ALLOWLISTED in k)
        }
        assertNotEquals(Label.SAFE, decide(text, "9800000010", KnowledgeGraph()).label)
        assertEquals("amazon", Brands.lookalikeOf("amaz0n-refund.xyz"))
    }

    @Test fun `R3_KB_link_genuineAmazonInIsNeitherLookalikeNorNotAllowlisted`() {
        val text = "Your Amazon order has shipped. Track: https://www.amazon.in/gp/your-account/order-details"
        val k = kinds(flags(text, "9800000010", warm()))
        assertFalse(k.toString(), FlagKind.LOOKALIKE_LINK in k)
        assertFalse(k.toString(), FlagKind.LINK_NOT_ALLOWLISTED in k)
        assertTrue(Brands.isOfficialHost("www.amazon.in")); assertNull(Brands.lookalikeOf("www.amazon.in"))
        assertNull(Brands.lookalikeOf("example.org"))
    }

    @Test fun `R3_KB_link_lookalikeTable`() {
        for (h in listOf("amazon.in", "www.amazon.in", "hdfcbank.com", "onlinesbi.sbi", "irctc.co.in", "example.org", "google.com", "sbit.edu"))
            assertNull(h, Brands.lookalikeOf(h))
        val want = mapOf(
            "amaz0n-refund.xyz" to "amazon", "hdfc-bank-kyc.top" to "hdfcbank", "sbi-yono.xyz" to "sbi",
            "flipkart-sale.shop" to "flipkart", "jio-recharge.online" to "jio",
        )
        for ((h, b) in want) assertEquals(h, b, Brands.lookalikeOf(h))
    }

    @Test fun `R3_KB_link_ordinaryHostsAndGenuineAmazonSitesAreNotLookalikes`() {
        for (h in listOf("canada.com", "kodak.com", "tomato.com", "amazonaws.com", "amazon.co.uk", "idea.com", "bob.github.io",
            "baroda.gov.in", "sbi.bank.in", "google.com", "youtube.com", "wikipedia.org"))
            assertNull(h, Brands.lookalikeOf(h))
        assertTrue(Brands.isOfficialHost("vodafone.com"))
    }

    @Test fun `R3_KB_link_stillLookalikeWhenThreeCharBrandIsInRegistrableLabel`() {
        assertEquals("sbi", Brands.lookalikeOf("sbi-yono.xyz"))
        assertEquals("sbi", Brands.lookalikeOf("login.sbi-yono.co.in"))   // two-part suffix: registrable label is sbi-yono
        assertNull(Brands.lookalikeOf("sbi.example.co.in"))              // sbi is a subdomain here, not the registrable label
    }

    @Test fun `R3_KB_link_manyUnknownLinksStackAtMostOneWeakFlagAndStaySafe`() {
        val text = "Check these notes https://example.org/a and https://example.net/b"
        val g = warm()
        val fl = flags(text, "9800000010", g)
        assertEquals(1, fl.count { it.kind == FlagKind.LINK_NOT_ALLOWLISTED })
        assertTrue(FlagKind.NON_DLT_SENDER in kinds(fl))
        assertEquals(Label.SAFE, decide(text, "9800000010", g).label)
    }

    // ---- DLT header normalisation / brand ----

    @Test fun `R3_KB_brand_dltHeaderBillEventMatchesLaterHdfcBankClaim`() {
        val g = warm()
        g.ingest("Your credit card bill of Rs 1,234 is due on 5th. HDFC Bank", "AX-HDFCBK", now - h)
        assertEquals("hdfcbank", ClaimParsers.senderBrand("AX-HDFCBK"))
        assertEquals(EventType.BILL, g.eventsFor("hdfcbank").single().type)
        assertFalse(kinds(flags("HDFC Bank bill overdue, pay now", "9800000010", g)).contains(FlagKind.NO_MATCHING_EVENT))
    }

    @Test fun `R3_KB_brand_shortUnknownPrefixDoesNotMatchKnownBrand`() {
        assertFalse(ClaimParsers.sameBrand("ama", "amazon"))
        assertTrue(ClaimParsers.sameBrand("hdfcbk", "hdfc bank"))
        assertTrue(ClaimParsers.sameBrand("examplecourier", "examplec"))
    }

    // ---- amounts ----

    @Test fun `R3_KB_amount_hindiHinglishLakhHazaarDevanagariDigits`() {
        fun a(s: String) = ClaimParsers.amountRupees(s)
        assertEquals(5000.0, a("pay ₹5,000 now")!!, 1e-9)
        assertEquals(5000.0, a("send Rs 5k please")!!, 1e-9)
        assertEquals(150000.0, a("loan of 1.5 lakh approved")!!, 1e-9)
        assertEquals(2000.0, a("रु 2000 भेजो")!!, 1e-9)
        assertEquals(2000.0, a("2 hazaar bhej do")!!, 1e-9)
        assertEquals(5000.0, a("५००० रुपये भेजें")!!, 1e-9)
        assertEquals(50000.0, a("50 हजार रुपये")!!, 1e-9)
        assertEquals(25_000_000.0, a("Rs 2.5 crore")!!, 1e-3)
        assertNull(a("Rs. only"))
    }

    // ---- Hinglish events and claims ----

    @Test fun `R3_KB_events_hinglishJamaKatGayeOrderConfirm`() {
        assertTrue(EventType.CREDIT in ClaimParsers.eventTypes("Aapke account mein Rs 500 jama ho gaye"))
        assertTrue(EventType.DEBIT in ClaimParsers.eventTypes("Aapke account se Rs 300 kat gaye"))
        assertTrue(EventType.ORDER in ClaimParsers.eventTypes("Aapka order confirm ho gaya"))
        assertTrue(EventType.REFUND in ClaimParsers.eventTypes("Refund of Rs 100 initiated"))
        assertTrue(EventType.OUT_FOR_DELIVERY in ClaimParsers.eventTypes("Aaj delivery hogi"))
    }

    @Test fun `R3_KB_claims_inOrderToIsNotAnOrder`() {
        assertFalse(ClaimParsers.parse("in order to verify your account, share details").claimsOrder)
        assertFalse(ClaimParsers.parse("the order of items is fixed").claimsOrder)
        assertFalse(EventType.ORDER in ClaimParsers.eventTypes("in order to keep it placed and confirmed"))
        assertTrue(ClaimParsers.parse("Your order is held").claimsOrder)
    }

    // ---- false positives for friends / cold graph ----

    @Test fun `R3_KB_friendWhatsappPaymentDoneAndOrderPlacedStaySafe`() {
        val g = warm()
        for (t in listOf("payment done bhai", "order placed, will reach by evening")) {
            assertFalse(t, kinds(flags(t, "", g)).contains(FlagKind.NO_MATCHING_EVENT))
            assertEquals(t, Label.SAFE, decide(t, "", g).label)
        }
    }

    @Test fun `R3_KB_deliveryCallOnColdGraphHasNoFlag`() {
        val call = "Hello, parcel aapke gate par hai"
        val cold = ContextRules.delivery(call, KnowledgeGraph(), now)
        assertTrue(cold.flags.isEmpty()); assertFalse(cold.suppress)
        assertEquals(FlagKind.UNVERIFIED_DELIVERY, ContextRules.delivery(call, warm(), now).flags.single().kind)
    }

    // ---- DEBIT_SCARE ----

    private val scare = "Your a/c debited Rs 9,999. If not you, call 98XXXXXX10 to cancel"

    @Test fun `R3_KB_debitScare_noDebitAlertOnRecordIsFlaggedWarmAndCold`() {
        val warmFlag = flags(scare, "9800000020", warm()).single { it.kind == FlagKind.DEBIT_SCARE }
        assertEquals(ContextRules.DEBIT_SCARE_WARM_TEXT, warmFlag.reason)
        val coldFlag = flags(scare, "9800000020", KnowledgeGraph()).single { it.kind == FlagKind.DEBIT_SCARE }
        assertEquals(ContextRules.DEBIT_SCARE_COLD_TEXT, coldFlag.reason)
    }

    @Test fun `R3_KB_debitScare_dltBankDebitEventWithin24hClearsIt`() {
        val g = warm()
        g.ingest("Rs 9,999 debited from A/c XX1234 at HDFC Bank. Avl bal Rs 100", "AX-HDFCBK", now - 2 * h)
        assertEquals(9999.0, g.recentEvents(EventType.DEBIT, 0L).single().amountRupees!!, 1e-9)
        assertFalse(kinds(flags(scare, "9800000020", g)).contains(FlagKind.DEBIT_SCARE))
        // the DLT message that is itself the debit report is the alert, not a scare
        assertFalse(kinds(flags("Rs 9,999 debited. Not you? call 1800000000 to block", "AX-HDFCBK", warm())).contains(FlagKind.DEBIT_SCARE))
    }

    // ---- amount-aware mistaken transfer ----

    private fun withCredit500() = KnowledgeGraph().also { it.ingest("Rs 500 credited to A/c XX1 at HDFC Bank", "AX-HDFCBK", now - 60_000L) }

    @Test fun `R3_KB_mistaken_creditOfDifferentAmountIsFakeCreditAndScam`() {
        val text = "Sorry I sent ₹5000 by mistake, please return it"
        val f = flags(text, "9800000010", withCredit500())
        val fake = f.single { it.kind == FlagKind.FAKE_CREDIT }
        assertTrue(fake.reason, fake.reason.startsWith(ContextRules.MISTAKEN_A_AMOUNT_TEXT + "5000"))
        assertFalse(FlagKind.RETURN_VIA_BANK_ONLY in kinds(f))
        assertEquals(Label.SCAM, decide(text, "9800000010", withCredit500()).label)
    }

    @Test fun `R3_KB_mistaken_matchingAmountIsReturnViaBankOnly`() {
        val f = flags("Sorry I sent ₹500 by mistake, please return it", "9800000010", withCredit500())
        assertTrue(FlagKind.RETURN_VIA_BANK_ONLY in kinds(f)); assertFalse(FlagKind.FAKE_CREDIT in kinds(f))
    }

    // ---- NEW_UPI_PAY ----

    @Test fun `R3_KB_newUpiPay_unknownUpiWithPayAskOnWarmGraphFlagsKnownUpiDoesNot`() {
        val ask = "Please pay 500 to rohit.k@okaxis now"
        val g = warm()
        assertTrue(FlagKind.NEW_UPI_PAY in kinds(flags(ask, "9800000010", g)))
        assertFalse("cold graph", FlagKind.NEW_UPI_PAY in kinds(flags(ask, "9800000010", KnowledgeGraph())))
        g.ingest("my upi is rohit.k@okaxis", "9800000010", now - 10)
        assertFalse(FlagKind.NEW_UPI_PAY in kinds(flags(ask, "9800000010", g)))
        assertFalse("no pay ask", FlagKind.NEW_UPI_PAY in kinds(flags("my new id is fresh.id@okaxis", "9800000010", warm())))
    }

    // ---- reported / trusted ----

    @Test fun `R3_KB_reported_feedbackScamMarksSenderNumberAndUpiEvenOnColdGraph`() {
        val g = KnowledgeGraph()
        g.rememberAlert(AlertRef(111L, "9800000010", listOf("9800000012"), listOf("scam@okaxis")))
        assertTrue(g.feedback(111L, true, now)); assertFalse(g.feedback(999L, true, now))
        assertTrue(g.isReported(EntityKind.SENDER, "9800000010"))
        assertTrue(FlagKind.REPORTED_ENTITY in kinds(flags("hello", "9800000010", g)))
        assertTrue(FlagKind.REPORTED_ENTITY in kinds(flags("call me on 9800000012", "9800000099", g)))
        assertTrue(FlagKind.REPORTED_ENTITY in kinds(flags("pay scam@okaxis", "9800000099", g)))
        assertFalse(FlagKind.REPORTED_ENTITY in kinds(flags("hello", "9800000055", g)))
        assertNotEquals(Label.SAFE, decide("hello", "9800000010", g).label)
        assertEquals(GraphContext.REPORTED_LINE, GraphContext.forMessage(ClaimParsers.parse("hello", "9800000010"), warm().also { w ->
            w.rememberAlert(AlertRef(1L, "9800000010", emptyList(), emptyList())); w.feedback(1L, true, now) }, now, "9800000010").first())
    }

    @Test fun `R3_KB_trusted_feedbackSafeDropsWeakFlagsButOtpShareIsStillScamAndLoud`() {
        val g = warm()
        g.rememberAlert(AlertRef(222L, "9800000010", emptyList(), emptyList()))
        assertTrue(g.feedback(222L, false, now))
        assertTrue(g.isTrusted("9800000010")); assertFalse(g.isTrusted("9800000011"))
        val k = kinds(flags("Your Amazon order is held, see https://example.org/x", "9800000010", g))
        for (dropped in listOf(FlagKind.NO_MATCHING_EVENT, FlagKind.NON_DLT_SENDER, FlagKind.LINK_NOT_ALLOWLISTED)) assertFalse(dropped.name, dropped in k)
        assertTrue(FlagKind.NON_DLT_SENDER in kinds(flags("Your Amazon order is held", "9800000011", g)))

        val otp = "Share your OTP and UPI PIN with me immediately or your account will be blocked, do not tell anyone, send the OTP now"
        val fl = flags(otp, "9800000010", g)
        assertEquals(Label.SCAM, Pipeline.decide(otp, RuleScorer.score(otp), LlmResult(Label.SCAM, 0.9, "model"), fl).label)
        assertTrue(RuleScorer.score(otp).score.toString(), Trust.hardSignal(otp, fl))
        assertFalse(Trust.quietAlert(Label.SCAM, trusted = true, hard = Trust.hardSignal(otp, fl)))
    }

    @Test fun `R3_KB_trust_quietAlertOnlyForTrustedSuspiciousWithoutHardSignal`() {
        assertTrue(Trust.quietAlert(Label.SUSPICIOUS, trusted = true, hard = false))
        assertFalse(Trust.quietAlert(Label.SUSPICIOUS, trusted = true, hard = true))
        assertFalse(Trust.quietAlert(Label.SUSPICIOUS, trusted = false, hard = false))
        assertFalse(Trust.quietAlert(Label.SCAM, trusted = true, hard = false))
        assertTrue(Trust.hardSignal("hi", listOf(ContextFlag(FlagKind.LOOKALIKE_LINK, "x"))))
        assertFalse(Trust.hardSignal("hi", listOf(ContextFlag(FlagKind.NON_DLT_SENDER, "x"))))
    }

    @Test fun `R3_KB_trust_debitScareIsHardSignalSoTrustedSenderStillAlerts`() {
        val flagsScare = listOf(ContextFlag(FlagKind.DEBIT_SCARE, "x"))
        assertTrue(Trust.hardSignal("hi", flagsScare))
        assertFalse(Trust.quietAlert(Label.SUSPICIOUS, trusted = true, hard = Trust.hardSignal("hi", flagsScare)))
    }

    @Test fun `R3_KB_trust_latestChoiceWinsBetweenReportedAndTrusted`() {
        val g = warm(); g.mark(EntityKind.SENDER, "9800000010", TrustStatus.REPORTED, now)
        g.mark(EntityKind.SENDER, "9800000010", TrustStatus.TRUSTED, now + 1)
        assertTrue(g.isTrusted("9800000010")); assertFalse(g.isReported(EntityKind.SENDER, "9800000010"))
    }

    // ---- dedupe / retention / clear ----

    @Test fun `R3_KB_events_sameEventIngestedTwiceIsOneEvent`() {
        val store = FakeStore(); val g = KnowledgeGraph(store)
        repeat(2) { g.ingest("Your Amazon order has been placed", "AX-AMAZON", now - h) }
        assertEquals(1, g.eventsFor("amazon").size)
        assertEquals(listOf(1, 0), store.deltas.map { it.events.size })
    }

    @Test fun `R3_KB_prune_removes91DayOldEventsNumbersUpiAndSendersKeepsRecent`() {
        val store = FakeStore(); val g = KnowledgeGraph(store)
        g.ingest("Your Amazon order has been placed, call 9800000031", "AX-AMAZON", now - h)
        g.ingest("Your HDFC Bank bill is due, call 9800000099, pay a@okaxis", "AX-HDFCBK", now - 91 * day)
        assertTrue(g.knownNumber("9800000099"))
        g.prune(now)
        assertTrue(g.eventsFor("hdfcbank").isEmpty()); assertFalse(g.knownNumber("9800000099"))
        assertFalse(g.knownUpi("a@okaxis")); assertFalse(g.knownSender("AX-HDFCBK"))
        assertEquals(1, g.eventsFor("amazon").size); assertTrue(g.knownNumber("9800000031")); assertTrue(g.knownSender("AX-AMAZON"))
        assertEquals(now - GraphStore.ENTITY_RETENTION_MS, store.prunedCutoff)
    }

    @Test fun `R3_KB_clear_emptiesMemoryAndCallsStoreClear`() {
        val store = FakeStore(); val g = warm(store)
        g.ingest("Your Amazon order has been placed, call 9800000031", "AX-AMAZON", now)
        g.rememberAlert(AlertRef(5L, "AX-AMAZON", emptyList(), emptyList())); g.feedback(5L, false, now)
        g.clear()
        assertTrue(g.isEmpty); assertTrue(g.eventsFor("amazon").isEmpty()); assertFalse(g.knownSender("AX-AMAZON"))
        assertNull(g.alertRef(5L)); assertFalse(g.isTrusted("AX-AMAZON"))
        assertEquals(1, store.clears)
        assertEquals(0, g.snapshot().ingested)
    }
}
