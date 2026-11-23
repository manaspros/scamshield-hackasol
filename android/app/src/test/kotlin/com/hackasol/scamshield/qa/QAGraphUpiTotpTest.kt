package com.hackasol.scamshield.qa

import com.hackasol.scamshield.core.*
import com.hackasol.scamshield.core.graph.*
import org.junit.Assert.*
import org.junit.Test

class QAGraphUpiTotpTest {
    private val now = 1_000_000_000_000L
    private val H = 3_600_000L

    // ---------- Claim parsers ----------
    @Test fun `QA_claims_dltHeaderShapeIsStrict`() {
        for (ok in listOf("AX-HDFCBK", "VM-ABC", "AX-ABC-P", " AX-HDFCBK ")) assertTrue(ok, ClaimVsContext.isDltHeader(ok))
        for (bad in listOf("ax-hdfcbk", "AX-AB", "AX-ABCDEFG", "AX-ABC-X", "AXHDFCBK", "+919876543210", "", "A-HDFCBK")) assertFalse(bad, ClaimVsContext.isDltHeader(bad))
    }

    @Test fun `QA_claims_hostExtractionTricks`() {
        assertEquals("evil.example", ClaimParsers.host("https://sbi.bank.in@evil.example/login"))
        assertEquals("a.bank.in", ClaimParsers.host("https://A.BANK.IN:8443/x?y#z"))
        assertEquals("a.bank.in", ClaimParsers.host("https://a.bank.in?x=1"))
        assertEquals("sbi.bank.in", ClaimParsers.host("https://sbi.bank.in./"))
    }

    @Test fun `QA_claims_allowlistRejectsLookalikes`() {
        assertTrue(ClaimVsContext.isAllowedHost("sbi.bank.in")); assertTrue(ClaimVsContext.isAllowedHost("incometax.gov.in"))
        for (h in listOf("evilbank.in", "sbi.bank.in.evil.com", "fakegov.in", "evil.com", "bank.in.evil.com", "")) assertFalse(h, ClaimVsContext.isAllowedHost(h))
    }

    @Test fun `QA_claims_amountFormats`() {
        assertEquals(150000.5, ClaimParsers.amountRupees("Rs 1,50,000.50 debited")!!, 1e-9)
        assertEquals(500.0, ClaimParsers.amountRupees("₹500 charged")!!, 1e-9)
        assertEquals(99.0, ClaimParsers.amountRupees("INR 99")!!, 1e-9)
        assertEquals(5000.0, ClaimParsers.amountRupees("5000 रुपये कटे")!!, 1e-9)
        assertNull(ClaimParsers.amountRupees("Rs. only")); assertNull(ClaimParsers.amountRupees(""))
    }

    @Test fun `QA_claims_emailIsNotLinkOrUpi`() {
        assertTrue(ClaimParsers.links("write to help@sbi.co.in please").isEmpty())
        assertTrue(ClaimParsers.upiIds("mail a@b.com").isEmpty())
        assertEquals(listOf("ramesh@oksbi"), ClaimParsers.upiIds("pay RAMESH@oksbi now"))
    }

    @Test fun `QA_claims_linksWithoutSchemeAndShorteners`() {
        assertEquals(listOf("sbi-kyc.xyz/login"), ClaimParsers.links("update at sbi-kyc.xyz/login."))
        assertTrue(ClaimParsers.links("click bit.ly/abc123 now").isNotEmpty())
        assertTrue(ClaimParsers.links("Dear customer.Your account").isEmpty())
    }

    @Test fun `QA_claims_phoneNumbers`() {
        assertEquals(listOf("9876543210"), ClaimParsers.numbers("call +91-9876543210 now"))
        assertTrue(ClaimParsers.numbers("1234567890").isEmpty()); assertTrue(ClaimParsers.numbers("98765432101").isEmpty())
    }

    @Test fun `QA_claims_brandFromHeaderWhenTextHasNone`() {
        assertEquals("hdfcbank", ClaimParsers.parse("Your bill is overdue", "AX-HDFCBK").brand)
        assertNull(ClaimParsers.parse("Your bill is overdue", "").brand)
        assertFalse(ClaimParsers.sameBrand("amazon", "ama")); assertFalse(ClaimParsers.sameBrand("amazon", "am")); assertFalse(ClaimParsers.sameBrand("amazon", "flipkart"))
    }

    // ---------- Knowledge graph ----------
    @Test fun `QA_graph_coldStartThenWarm`() {
        val g = KnowledgeGraph(); assertTrue(g.isEmpty); assertNotNull(g.coldStartNote)
        g.ingest("hello", "", now); assertFalse(g.isEmpty); assertNull(g.coldStartNote)
    }

    @Test fun `QA_graph_onlyDltSendersCreateEvents`() {
        val g = KnowledgeGraph()
        g.ingest("Your Amazon order has been placed", "+919876543210", now)
        g.ingest("Your Amazon order has been placed", "ax-amazon", now)
        assertTrue(g.eventsFor("amazon").isEmpty())
        g.ingest("Your Amazon order has been placed", "AX-AMAZON", now)
        assertEquals(listOf(EventType.ORDER), g.eventsFor("amazon").map { it.type })
    }

    @Test fun `QA_graph_scammerCreditTextFromNormalNumberIsNotACreditEvent`() {
        val g = KnowledgeGraph(); g.ingest("Rs 5000 credited to your account", "+919876543210", now)
        assertFalse(g.hasAnyEvent(EventType.CREDIT, 0))
    }

    @Test fun `QA_graph_storesNoRawTextButKnowsEntities`() {
        val g = KnowledgeGraph(); g.ingest("pay ramesh@oksbi or call 9876543210 http://x.xyz", "AX-ABC", now)
        assertTrue(g.knownUpi("RAMESH@oksbi")); assertTrue(g.knownNumber("+91 9876543210")); assertTrue(g.knownSender(" AX-ABC "))
        assertFalse(g.knownUpi("other@upi"))
    }

    // ---------- Claim vs context ----------
    @Test fun `QA_ctx_billClaimWithoutEventIsFlaggedWithColdNote`() {
        val f = ClaimVsContext.check("Your electricity bill is overdue", "AX-MSEDCL", KnowledgeGraph())
        assertTrue(f.any { it.kind == FlagKind.NO_MATCHING_EVENT && it.reason.contains(KnowledgeGraph.COLD_START_TEXT) })
    }

    @Test fun `QA_ctx_billClaimMatchedByRecordedEventIsNotFlagged`() {
        val g = KnowledgeGraph(); g.ingest("Your Zomato order placed", "AX-ZOMATO", now)
        assertTrue(ClaimVsContext.check("Zomato: payment for your order received", "AX-ZOMATO", g).none { it.kind == FlagKind.NO_MATCHING_EVENT })
        assertTrue(ClaimVsContext.check("Swiggy: payment for your order received", "AX-SWIGGY", g).any { it.kind == FlagKind.NO_MATCHING_EVENT })
    }

    @Test fun `QA_ctx_blankSenderPasteIsNotNonDltFlagged`() {
        assertTrue(ClaimVsContext.check("hello", "", KnowledgeGraph()).none { it.kind == FlagKind.NON_DLT_SENDER })
        assertTrue(ClaimVsContext.check("hello", "   ", KnowledgeGraph()).none { it.kind == FlagKind.NON_DLT_SENDER })
        assertTrue(ClaimVsContext.check("hello", "+919876543210", KnowledgeGraph()).any { it.kind == FlagKind.NON_DLT_SENDER })
    }

    @Test fun `QA_ctx_userinfoTrickLinkIsFlaggedByRealHost`() {
        val f = ClaimVsContext.check("Verify at https://sbi.bank.in@evil.example/login", "AX-SBIBNK", KnowledgeGraph())
        assertTrue(f.any { it.kind == FlagKind.LINK_NOT_ALLOWLISTED && it.reason.contains("evil.example") })
    }

    @Test fun `QA_ctx_officialLinkNotFlaggedDuplicatesCollapsed`() {
        assertTrue(ClaimVsContext.check("see https://sbi.bank.in/x", "AX-SBIBNK", KnowledgeGraph()).none { it.kind == FlagKind.LINK_NOT_ALLOWLISTED })
        val f = ClaimVsContext.check("a http://e.xyz/1 b http://e.xyz/2", "AX-SBIBNK", KnowledgeGraph())
        assertEquals(1, f.count { it.kind == FlagKind.LINK_NOT_ALLOWLISTED })
    }

    // ---------- Context rules ----------
    private fun withCredit(ts: Long): KnowledgeGraph { val g = KnowledgeGraph(); g.ingest("Rs 500 credited to A/c", "AX-HDFCBK", ts); return g }

    @Test fun `QA_rules_mistakenTransferHinglishNoCreditIsFakeCredit`() {
        val g = KnowledgeGraph(); g.ingest("hi", "", now)
        val f = ContextRules.mistakenTransfer("Galti se aapke account mein paise aa gaye, wapas kar do", g, now)
        assertEquals(listOf(FlagKind.FAKE_CREDIT), f.map { it.kind })
        assertEquals(ContextRules.MISTAKEN_A_TEXT, f[0].reason)
    }

    @Test fun `QA_rules_mistakenTransferDevanagari`() {
        assertEquals(1, ContextRules.mistakenTransfer("गलती से पैसे आ गए, वापस कर दो", KnowledgeGraph(), now).size)
    }

    @Test fun `QA_rules_mistakenTransferColdStartUsesColdText`() {
        assertEquals(ContextRules.MISTAKEN_A_COLD_TEXT, ContextRules.mistakenTransfer("sent by mistake, please return it", KnowledgeGraph(), now)[0].reason)
    }

    @Test fun `QA_rules_mistakenTransferCreditWindowEdge`() {
        val txt = "I sent money to wrong number, send back please"
        assertEquals(FlagKind.RETURN_VIA_BANK_ONLY, ContextRules.mistakenTransfer(txt, withCredit(now - ContextRules.CREDIT_WINDOW_MS), now)[0].kind)
        assertEquals(FlagKind.FAKE_CREDIT, ContextRules.mistakenTransfer(txt, withCredit(now - ContextRules.CREDIT_WINDOW_MS - 1), now)[0].kind)
    }

    @Test fun `QA_rules_mistakenTransferNeedsBothMistakeAndReturnWords`() {
        val g = KnowledgeGraph()
        assertTrue(ContextRules.mistakenTransfer("sent by mistake", g, now).isEmpty())
        assertTrue(ContextRules.mistakenTransfer("please return the book", g, now).isEmpty())
        assertTrue(ContextRules.mistakenTransfer("", g, now).isEmpty())
    }

    @Test fun `QA_rules_bankCallNumberNormalisation`() {
        val t = "main bank se bol raha hoon"
        assertTrue(ContextRules.bankCall("+91 1600123456", t).isEmpty())
        assertTrue(ContextRules.bankCall("01600123456", t).isEmpty())
        assertTrue(ContextRules.bankCall("1600-123-456", t).isEmpty())
        assertEquals(FlagKind.NON_1600_BANK_CALL, ContextRules.bankCall("+91 9876543210", t)[0].kind)
        assertEquals(FlagKind.NON_1600_BANK_CALL, ContextRules.bankCall("9816001234", t)[0].kind)
    }

    @Test fun `QA_rules_bankCallHiddenNumberOrNonBankTalkGivesNoFlag`() {
        assertTrue(ContextRules.bankCall("", "bank se bol raha hoon").isEmpty())
        assertTrue(ContextRules.bankCall("Private number", "bank se bol raha hoon").isEmpty())
        assertTrue(ContextRules.bankCall("9876543210", "hello beta kaise ho").isEmpty())
    }

    @Test fun `QA_rules_deliveryColdStartHasNoFlag`() {
        val o = ContextRules.delivery("Your parcel is at the gate", KnowledgeGraph(), now)
        assertFalse(o.suppress); assertTrue(o.flags.isEmpty())
    }

    @Test fun `QA_rules_deliverySuppressedByRecentEventWindowEdge`() {
        fun g(ts: Long) = KnowledgeGraph().also { it.ingest("Delhivery: out for delivery", "AX-DELHVY", ts) }
        val call = "Delhivery se bol raha hoon, parcel deliver karna hai"
        assertTrue(ContextRules.delivery(call, g(now - ContextRules.DELIVERY_WINDOW_MS), now).suppress)
        val late = ContextRules.delivery(call, g(now - ContextRules.DELIVERY_WINDOW_MS - 1), now)
        assertFalse(late.suppress); assertEquals(1, late.flags.size)
    }

    @Test fun `QA_rules_deliveryEventForDifferentCourierDoesNotSuppress`() {
        val g = KnowledgeGraph().also { it.ingest("Bluedart: out for delivery", "AX-BLUDRT", now) }
        assertFalse(ContextRules.delivery("Delhivery courier here for your parcel", g, now).suppress)
    }

    @Test fun `QA_rules_deliveryTextWithNoCourierUsesAnyCourierEvent`() {
        val g = KnowledgeGraph().also { it.ingest("Bluedart: out for delivery", "AX-BLUDRT", now) }
        assertTrue(ContextRules.delivery("आपका पार्सल दरवाजे पर है", g, now).suppress)
    }

    @Test fun `QA_rules_nonDeliveryCallProducesNothing`() {
        val o = ContextRules.delivery("Hello beta kal milte hain", KnowledgeGraph(), now); assertTrue(o.flags.isEmpty()); assertFalse(o.suppress)
    }

    @Test fun `QA_rules_suppressNeverComesWithFlags`() {
        val g = KnowledgeGraph().also { it.ingest("Delhivery: out for delivery", "AX-DELHVY", now) }
        val o = ContextRules.delivery("Delhivery parcel", g, now); assertTrue(o.suppress); assertTrue(o.flags.isEmpty())
    }

    // ---------- UPI QR ----------
    @Test fun `QA_upi_notUpiInputsAreNull`() {
        for (s in listOf(null, "", "   ", "http://x.example/pay?pa=a@b", "upi:pay?pa=a@b", "upi://pay", "upi://pay?", "upi://pay?am=10",
            "upi://collect?pa=a@b", "upi://pay?pa=a", "upi://pay?pa=a@b@c", "upi://pay?pa=a b@c", "upi://pay?pa=%zz@b")) assertNull("$s", UpiQr.parse(s))
    }

    @Test fun `QA_upi_schemeAndKeysCaseInsensitive`() {
        val q = UpiQr.parse("UPI://PAY?PA=shop@okaxis&PN=Shop&AM=10.50")!!
        assertEquals("shop@okaxis", q.payeeAddress); assertEquals("10.50", q.amount)
    }

    @Test fun `QA_upi_invalidAmountsRejected`() {
        for (a in listOf("abc", "-5", "1,000", "100.", "1e5", ".5", "10 20")) assertNull(a, UpiQr.parse("upi://pay?pa=a@b&am=$a"))
        assertNotNull(UpiQr.parse("upi://pay?pa=a@b&am=0.5")); assertNull(UpiQr.parse("upi://pay?pa=a@b&am=")?.amount)
    }

    @Test fun `QA_upi_percentAndPlusDecodingIncludingHindiName`() {
        assertEquals("राम", UpiQr.parse("upi://pay?pa=a@b&pn=%E0%A4%B0%E0%A4%BE%E0%A4%AE")!!.payeeName)
        assertEquals("Ram Kumar", UpiQr.parse("upi://pay?pa=a@b&pn=Ram+Kumar")!!.payeeName)
    }

    @Test fun `QA_upi_collectWordingDetected`() {
        assertTrue(UpiQr.parse("upi://pay?pa=a@b&tn=Please+receive+money")!!.isCollectRequest)
        assertFalse(UpiQr.parse("upi://pay?pa=a@b&tn=Rent")!!.isCollectRequest)
    }

    @Test fun `QA_upi_nameMismatchNormalisationAndBlanks`() {
        val q = UpiQr("a@b", payeeName = "Ram Kumar")
        assertFalse(q.nameMismatch("RAM-KUMAR")); assertFalse(q.nameMismatch(null)); assertFalse(q.nameMismatch("  "))
        assertTrue(q.nameMismatch("Shyam Kumar")); assertFalse(UpiQr("a@b").nameMismatch("Anyone"))
    }

    @Test fun `QA_upi_payFramingAlwaysSaysPayNeverReceive`() {
        assertEquals("You will PAY Rs 10 to Shop", UpiQr("a@b", "Shop", "10").payFraming())
        assertEquals("You will PAY money to a@b", UpiQr("a@b").payFraming())
        assertEquals("You will PAY money to a@b", UpiQr("a@b", "  ", "").payFraming())
    }

    @Test(timeout = 20_000) fun `QA_upi_veryLongInputsDoNotHang`() {
        assertNull(UpiQr.parse("upi://pay?pa=" + "a".repeat(200_000)))
        assertNotNull(UpiQr.parse("upi://pay?pa=a@b&tn=" + "x".repeat(200_000)))
    }

    // ---------- TOTP ----------
    private val secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    @Test fun `QA_totp_rfcVectorsWithLeadingZeroAndEightDigits`() {
        assertEquals("07081804", Totp.code(secret, 1_111_111_109_000L, 8)); assertEquals("081804", Totp.code(secret, 1_111_111_109_000L, 6))
        assertEquals("89005924", Totp.code(secret, 1_234_567_890_000L, 8)); assertEquals("69279037", Totp.code(secret, 2_000_000_000_000L, 8))
    }

    @Test fun `QA_totp_stepBoundaryAt30s`() {
        assertEquals(Totp.code(secret, 0), Totp.code(secret, 29_999)); assertNotEquals(Totp.code(secret, 29_999), Totp.code(secret, 30_000))
    }

    @Test fun `QA_totp_verifyWindowIsPlusMinusOneStep`() {
        val t = 1_000_000_000_000L; val c = { s: Long -> Totp.code(secret, t + s * 30_000) }
        assertTrue(Totp.verify(secret, c(0), t)); assertTrue(Totp.verify(secret, c(-1), t)); assertTrue(Totp.verify(secret, c(1), t))
        assertFalse(Totp.verify(secret, c(-2), t)); assertFalse(Totp.verify(secret, c(2), t))
    }

    @Test fun `QA_totp_verifyRejectsMalformedCandidates`() {
        val t = 59_000L; val ok = Totp.code(secret, t)
        for (bad in listOf("", ok + " ", " $ok", ok.dropLast(1), ok + "0", "12345a", "١٢٣٤٥٦", "-12345")) assertFalse("'$bad'", Totp.verify(secret, bad, t))
        assertFalse(Totp.verify(secret, ok, -1))
    }

    @Test fun `QA_totp_verifyNearEpochDoesNotUseNegativeSteps`() { assertTrue(Totp.verify(secret, Totp.code(secret, 0), 0)) }

    @Test fun `QA_totp_secretCaseAndPaddingTolerantInvalidRejected`() {
        assertEquals(Totp.code(secret, 5000), Totp.code(secret.lowercase() + "====", 5000))
        for (bad in listOf("", "   ", "AB!C", "A1")) try { Totp.code(bad, 0); fail("accepted '$bad'") } catch (_: IllegalArgumentException) {}
    }

    @Test fun `QA_totp_generatedSecretsAreValidDistinctAndUsable`() {
        val a = Totp.generateSecret(); val b = Totp.generateSecret()
        assertEquals(32, a.length); assertTrue(a.all { it in "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567" }); assertNotEquals(a, b)
        assertTrue(Totp.verify(a, Totp.code(a, 123_456), 123_456))
        try { Totp.generateSecret(0); fail() } catch (_: IllegalArgumentException) {}
    }

    @Test fun `QA_totp_digitsBounds`() {
        for (d in listOf(0, 11)) try { Totp.code(secret, 0, d); fail() } catch (_: IllegalArgumentException) {}
        assertEquals(10, Totp.code(secret, 0, 10).length)
    }

    @Test fun `QA_totp_allCodesFixedWidthOverManySteps`() {
        for (i in 0 until 500) assertEquals(6, Totp.code(secret, i * 30_000L).length)
    }
}
