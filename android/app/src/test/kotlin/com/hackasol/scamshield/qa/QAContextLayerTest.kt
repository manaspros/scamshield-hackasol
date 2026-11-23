package com.hackasol.scamshield.qa

import com.hackasol.scamshield.ListenerWiring
import com.hackasol.scamshield.NotificationInfo
import com.hackasol.scamshield.core.*
import com.hackasol.scamshield.core.graph.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class QAContextLayerTest {
    private val now = 10_000_000_000L
    private val sms = "com.google.android.apps.messaging"

    private fun warm(): KnowledgeGraph = KnowledgeGraph().also { it.ingest("hello there friend how are you", "", now - 1) }
    private fun lines(text: String, g: KnowledgeGraph, sender: String = "", ts: Long = now) =
        GraphContext.forMessage(ClaimParsers.parse(text, sender), g, ts, sender)

    // ---------- graph context -> prompt ----------
    @Test fun `QA_ctxPrompt_emptyGraphGivesOnlyColdStartLineWhateverTheClaims`() {
        for (t in listOf("Your ExampleBank bill is overdue", "Your Amazon order is held", "hello", "", "आपका ऑर्डर रुका है")) {
            assertEquals(t, listOf(KnowledgeGraph.COLD_START_TEXT), lines(t, KnowledgeGraph(), "AX-AMAZON"))
        }
    }

    @Test fun `QA_ctxPrompt_noClaimNoBrandAndKnownSenderGivesNoLines`() {
        val g = warm(); g.ingest("hi", "AX-AMAZON", now - 5)
        assertTrue(lines("hello there", g, "AX-AMAZON").isEmpty())
        assertTrue(lines("hello there", g, "").isEmpty())
    }

    @Test fun `QA_ctxPrompt_eventLineComesBeforeSenderLineAndAtMostTwo`() {
        val l = lines("Your ExampleCourier parcel order is held", warm(), "9800000001")
        assertEquals(listOf("No ORDER event from examplecourier since install", GraphContext.SENDER_FIRST_TEXT), l)
        for (s in listOf("a", "Your ExampleBank bill order parcel invoice", "Your Amazon order")) assertTrue(lines(s, warm(), "x").size <= GraphContext.MAX_ITEMS)
    }

    @Test fun `QA_ctxPrompt_orderClaimWinsOverBillClaim`() {
        assertEquals("No ORDER event from amazon since install", lines("Amazon order bill overdue", warm())[0])
    }

    @Test fun `QA_ctxPrompt_blankSenderNeverGetsSenderHistoryLine`() {
        assertFalse(lines("Your Amazon order is held", warm(), "   ").contains(GraphContext.SENDER_FIRST_TEXT))
    }

    @Test fun `QA_ctxPrompt_hindiMessageWithDltHeaderGetsEventLine`() {
        val g = warm()
        assertEquals(listOf("No ORDER event from amazon since install", GraphContext.SENDER_FIRST_TEXT), lines("आपका ऑर्डर रोक दिया गया है", g, "AX-AMAZON"))
    }

    @Test fun `QA_ctxPrompt_lastEventIsTheNewestAndAgoBoundaries`() {
        fun line(ageMs: Long): String {
            val g = KnowledgeGraph(); g.ingest("Amazon order has been placed", "AX-AMAZON", now - 10 * 86_400_000L)
            g.ingest("Amazon order has been shipped", "AX-AMAZON", now - ageMs)
            return lines("Amazon order is held", g, "AX-AMAZON")[0]
        }
        assertEquals("Last ORDER event from amazon: just now", line(59_999))
        assertEquals("Last ORDER event from amazon: 1 min ago", line(60_000))
        assertEquals("Last ORDER event from amazon: 59 min ago", line(3_599_999))
        assertEquals("Last ORDER event from amazon: 1 h ago", line(3_600_000))
        assertEquals("Last ORDER event from amazon: 47 h ago", line(48 * 3_600_000L - 1))
        assertEquals("Last ORDER event from amazon: 2 days ago", line(48 * 3_600_000L))
    }

    @Test fun `QA_ctxPrompt_linesNeverContainRawMessageText`() {
        val text = "ZZUNIQUETOKEN ExampleBank bill is overdue, pay at example.com or call 9876543210"
        for (l in lines(text, warm(), "9800000001")) { assertFalse(l, l.contains("ZZUNIQUETOKEN")); assertFalse(l, l.contains("9876543210")); assertFalse(l, l.contains("example.com")) }
    }

    @Test fun `QA_ctxPrompt_everyLineWithinItemCap`() {
        val brand = "a".repeat(20) + "bank"
        for (l in lines("Your $brand bill is overdue", warm(), "x")) assertTrue(l.length <= GraphContext.MAX_ITEM_CHARS)
    }

    @Test fun `QA_ctxPrompt_labelAndEntriesRenderedAndOnlyLastTwoKept`() {
        val p = GemmaPrompt.build("q", listOf("one", "two", "three"), GraphContext.LABEL)
        assertTrue(p.contains("\nKnown context: \"two\" | \"three\"\nSTATEMENT: \"q\"\n")); assertFalse(p.contains("\"one\""))
        assertFalse(p.contains("\nEarlier in this call: "))
    }

    @Test fun `QA_ctxPrompt_emptyContextHasNoLabelLineWhateverTheLabel`() {
        assertEquals(GemmaPrompt.build("q", emptyList()), GemmaPrompt.build("q", emptyList(), GraphContext.LABEL))
        assertEquals(GemmaPrompt.build("q", emptyList()), GemmaPrompt.build("q", listOf("", "  "), GraphContext.LABEL))
    }

    @Test fun `QA_ctxPrompt_devanagariContextEntriesPassThroughAndCutAt150`() {
        val hi = "आपका खाता बंद है"
        assertTrue(GemmaPrompt.build("q", listOf(hi), GraphContext.LABEL).contains("Known context: \"$hi\"\n"))
        assertTrue(GemmaPrompt.build("q", listOf("क".repeat(200)), GraphContext.LABEL).contains("\"" + "क".repeat(150) + "\"\n"))
    }

    @Test fun `QA_ctxPrompt_noGraphRequestRendersTheSamePromptAsPlainBuild`() {
        val r = ClassifyRequest("hello there")
        assertEquals(GemmaPrompt.build("hello there", emptyList()), GemmaPrompt.build(r.text, r.context, r.contextLabel))
    }

    @Test fun `QA_ctxPrompt_defaultLabelOutputUnchangedByNewParameter`() {
        assertTrue(GemmaPrompt.build("x", listOf("a", "b")).endsWith("\nEarlier in this call: \"a\" | \"b\"\nSTATEMENT: \"x\"\n"))
    }

    // ---------- raiseForContext: raise only ----------
    private fun fused(l: Label, c: Double = 0.7, type: ScamType? = if (l == Label.SAFE) null else ScamType.KYC, trig: List<String> = listOf("t1")) =
        FusedResult(l, c, type, trig, "gemma+rules", "model reason")
    private val allKinds = FlagKind.values().toList()
    private fun flag(k: FlagKind) = ContextFlag(k, "reason-${k.name}")
    private val allSubsets: List<List<ContextFlag>> = (0 until (1 shl allKinds.size)).map { m -> allKinds.filterIndexed { i, _ -> m and (1 shl i) != 0 }.map(::flag) }

    @Test fun `QA_raise_neverLowersLabelConfidenceOrDropsTriggersOverGrid`() {
        for (l in Label.values()) for (c in listOf(0.0, 0.1, 0.5, 0.95, 1.0)) for (fl in allSubsets) {
            val f = fused(l, c); val r = Fusion.raiseForContext(f, fl)
            val tag = "$l c=$c flags=${fl.map { it.kind }}"
            assertTrue(tag, r.label.ordinal >= f.label.ordinal)
            assertTrue("$tag one step only", r.label.ordinal - f.label.ordinal <= 1)
            assertTrue("$tag confidence lowered", r.confidence >= f.confidence)
            assertTrue("$tag triggers dropped", r.triggers.containsAll(f.triggers))
            assertEquals(tag, f.engine, r.engine)
            if (r.label == f.label) { assertEquals(tag, f.confidence, r.confidence, 0.0); assertEquals(tag, f.reason, r.reason); assertEquals(tag, f.scamType, r.scamType) }
        }
    }

    @Test fun `QA_raise_scamIsNeverChangedExceptAppendedTriggers`() {
        for (fl in allSubsets) {
            val f = fused(Label.SCAM, 0.97); val r = Fusion.raiseForContext(f, fl)
            assertEquals(f.copy(triggers = r.triggers), r)
        }
    }

    @Test fun `QA_raise_emptyFlagsReturnsInputUnchanged`() {
        for (l in Label.values()) assertEquals(fused(l), Fusion.raiseForContext(fused(l), emptyList()))
    }

    @Test fun `QA_raise_safeNotRaisedIsReturnedExactlyUntouched`() {
        val f = fused(Label.SAFE, 0.9); val r = Fusion.raiseForContext(f, listOf(flag(FlagKind.NON_DLT_SENDER)))
        assertEquals(f, r)
    }

    @Test fun `QA_raise_contextScoreIsMonotoneNoisyOrInUnitInterval`() {
        assertEquals(0.0, Fusion.contextScore(emptyList()), 0.0)
        for (fl in allSubsets) {
            val s = Fusion.contextScore(fl); assertTrue(s in 0.0..1.0)
            for (k in allKinds) assertTrue(Fusion.contextScore(fl + flag(k)) >= s)
        }
        assertEquals(1 - 0.5 * 0.5, Fusion.contextScore(listOf(flag(FlagKind.NO_MATCHING_EVENT), flag(FlagKind.NON_1600_BANK_CALL))), 1e-12)
    }

    @Test fun `QA_raise_safeToSuspiciousBoundaryAtExactly0_40`() {
        assertEquals(Label.SUSPICIOUS, Fusion.raiseForContext(fused(Label.SAFE), listOf(flag(FlagKind.UNVERIFIED_DELIVERY))).label)   // 0.40
        assertEquals(Label.SAFE, Fusion.raiseForContext(fused(Label.SAFE), listOf(flag(FlagKind.NON_DLT_SENDER), flag(FlagKind.LINK_NOT_ALLOWLISTED))).label) // 0.32
        assertEquals(Label.SAFE, Fusion.raiseForContext(fused(Label.SAFE), listOf(flag(FlagKind.LINK_NOT_ALLOWLISTED))).label)
    }

    @Test fun `QA_raise_suspiciousToScamBoundaryAtExactly0_75`() {
        assertEquals(Label.SCAM, Fusion.raiseForContext(fused(Label.SUSPICIOUS), listOf(flag(FlagKind.NO_MATCHING_EVENT), flag(FlagKind.NON_1600_BANK_CALL))).label) // 0.75
        assertEquals(Label.SUSPICIOUS, Fusion.raiseForContext(fused(Label.SUSPICIOUS), listOf(flag(FlagKind.NO_MATCHING_EVENT), flag(FlagKind.UNVERIFIED_DELIVERY))).label) // 0.70
        assertEquals(Label.SCAM, Fusion.raiseForContext(fused(Label.SUSPICIOUS), listOf(flag(FlagKind.FAKE_CREDIT), flag(FlagKind.NO_MATCHING_EVENT))).label)
    }

    @Test fun `QA_raise_safeNeverJumpsToScamInOneCall`() {
        assertEquals(Label.SUSPICIOUS, Fusion.raiseForContext(fused(Label.SAFE), allKinds.map(::flag)).label)
    }

    @Test fun `QA_raise_raisedResultShape`() {
        val r = Fusion.raiseForContext(fused(Label.SAFE, 0.2, null, listOf("old")), listOf(flag(FlagKind.FAKE_CREDIT)))
        assertEquals(Label.SUSPICIOUS, r.label); assertEquals(FusionWeights.CONTEXT_RAISED_CONF, r.confidence, 0.0)
        assertEquals(ScamType.MISTAKEN_TRANSFER, r.scamType); assertEquals(listOf("reason-FAKE_CREDIT", "old"), r.triggers); assertEquals("reason-FAKE_CREDIT", r.reason)
        val o = Fusion.raiseForContext(fused(Label.SAFE, 0.2, null), listOf(flag(FlagKind.NO_MATCHING_EVENT)))
        assertEquals(ScamType.OTHER, o.scamType)
        assertEquals(ScamType.KYC, Fusion.raiseForContext(fused(Label.SUSPICIOUS, 0.5, ScamType.KYC), listOf(flag(FlagKind.FAKE_CREDIT), flag(FlagKind.NO_MATCHING_EVENT))).scamType)
    }

    @Test fun `QA_raise_higherModelConfidenceKeptWhenRaised`() {
        assertEquals(0.9, Fusion.raiseForContext(fused(Label.SUSPICIOUS, 0.9), listOf(flag(FlagKind.FAKE_CREDIT), flag(FlagKind.NO_MATCHING_EVENT))).confidence, 0.0)
    }

    @Test fun `QA_raise_reasonsDistinctAndCapped`() {
        val many = (1..6).map { ContextFlag(FlagKind.FAKE_CREDIT, "r${it % 4}") }
        val r = Fusion.raiseForContext(fused(Label.SUSPICIOUS, trig = emptyList()), many)
        assertEquals(FusionWeights.MAX_CONTEXT_REASONS, r.triggers.size); assertEquals(r.triggers.distinct(), r.triggers)
    }

    @Test fun `QA_raise_endToEndRulesScamSurvivesAnyContext`() {
        val text = "Kisi ko mat batana, digital arrest, OTP bata do"
        val base = Fusion.fuse(LlmResult(Label.SAFE, 0.99, "x"), RuleScorer.score(text), RuleScorer.scamType(text))
        assertEquals(Label.SCAM, base.label)
        for (fl in allSubsets) assertEquals(Label.SCAM, Fusion.raiseForContext(base, fl).label)
    }

    // ---------- cold start ----------
    private val corpus = listOf(
        "Your ExampleBank bill is overdue" to "VM-EXMPBK", "Your Amazon order is held" to "AX-AMAZON", "Your Amazon order is held" to "9800000001",
        "आपका ऑर्डर रोक दिया गया है" to "AX-AMAZON", "payment received for your order" to "AX-ZOMATO", "hello there" to "", "hello there" to "9800000001",
        "see https://example.xyz/a" to "AX-ABC", "Your Zomato order placed" to "AX-ZOMATO", "refund of Rs 500 processed" to "",
    )

    @Test fun `QA_cold_emptyGraphVerdictEqualsNoContextForSingleWeakOrEventClaimMessages`() {
        for ((text, sender) in corpus) for (l in Label.values()) {
            val base = fused(l)
            val flags = GraphContext.flagsFor(text, sender, KnowledgeGraph(), now)
            val r = Fusion.raiseForContext(base, flags)
            assertEquals("$text/$sender/$l flags=${flags.map { it.kind }}", base.label, r.label)
            assertEquals(base.confidence, r.confidence, 0.0); assertEquals(base.scamType, r.scamType)
        }
    }

    @Test fun `QA_cold_emptyGraphNeverProducesNoMatchingEventFlag`() {
        for ((text, sender) in corpus) assertTrue("$text/$sender", GraphContext.flagsFor(text, sender, KnowledgeGraph(), now).none { it.kind == FlagKind.NO_MATCHING_EVENT })
    }

    @Test fun `QA_cold_coldFlagsNeverClaimCertainty`() {
        val f = GraphContext.flagsFor("galti se paise bhej diye, wapas kar do", "", KnowledgeGraph(), now)
        assertTrue(f.isNotEmpty()); for (x in f) assertEquals(ContextRules.MISTAKEN_A_COLD_TEXT, x.reason)
        val warmFlags = GraphContext.flagsFor("galti se paise bhej diye, wapas kar do", "", warm(), now)
        assertEquals(ContextRules.MISTAKEN_A_TEXT, warmFlags[0].reason)
    }

    @Test fun `QA_cold_warmGraphDoesFlagTheSameBillClaim`() {
        val f = GraphContext.flagsFor("Your ExampleBank bill is overdue", "VM-EXMPBK", warm(), now)
        assertTrue(f.any { it.kind == FlagKind.NO_MATCHING_EVENT })
    }

    @Test fun `QA_cold_dltEventReportIsNeverFlaggedForMissingPredecessorEvenWarm`() {
        val f = GraphContext.flagsFor("Your ExampleBank bill is generated, due date 5th", "VM-EXMPBK", warm(), now)
        assertTrue(f.none { it.kind == FlagKind.NO_MATCHING_EVENT })
    }

    // ---------- wiring: no graph / empty graph / failure ----------
    private fun info(text: String, title: String, ts: Long) = NotificationInfo(sms, title, text, false, false, ts)

    @Test fun `QA_wiring_noGraphUsesPlainClassifyAndNeverBuildsRequest`() = runBlocking {
        var plain = 0; var req = 0
        val w = ListenerWiring(NotificationMapper(), { t, s -> plain++; qaVerdict(Label.SAFE, 0.9, t, s) }, { _, _ -> }, null, { r -> req++; qaVerdict(Label.SAFE, 0.9, r.text) })
        w.onPosted(info("Your account will be blocked today", "VM-EXMPBK", 0))
        assertEquals(1, plain); assertEquals(0, req)
    }

    @Test fun `QA_wiring_emptyGraphRequestCarriesColdLineAndNoEventFlag`() = runBlocking {
        val got = mutableListOf<ClassifyRequest>()
        val w = ListenerWiring(NotificationMapper(), { t, s -> qaVerdict(Label.SAFE, 0.9, t, s) }, { _, _ -> }, KnowledgeGraph(), { r -> got += r; qaVerdict(Label.SAFE, 0.9, r.text) })
        w.onPosted(info("Your Amazon order is held, pay the fee now", "AX-AMAZON", now))
        assertEquals(listOf(KnowledgeGraph.COLD_START_TEXT), got[0].context); assertEquals(GraphContext.LABEL, got[0].contextLabel)
        assertTrue(got[0].contextFlags.none { it.kind == FlagKind.NO_MATCHING_EVENT })
    }

    // R3 (B2): an unclassified message must not become "known", so a failed classify ingests nothing.
    @Test fun `QA_wiring_classifyFailureIngestsNothingSoNextMessageStillSeesColdGraph`() = runBlocking {
        val g = KnowledgeGraph(); val got = mutableListOf<ClassifyRequest>(); var first = true
        val w = ListenerWiring(NotificationMapper(), { t, s -> qaVerdict(Label.SAFE, 0.9, t, s) }, { _, _ -> }, g, { r -> got += r; if (first) { first = false; error("boom") }; qaVerdict(Label.SAFE, 0.9, r.text) })
        try { w.onPosted(info("Your Amazon order is held, pay the fee now", "AX-AMAZON", now)); fail() } catch (_: IllegalStateException) {}
        assertTrue(g.isEmpty)
        w.onPosted(info("Your Amazon order is held, pay the fee again", "AX-AMAZON", now + 1000))
        assertEquals(listOf(KnowledgeGraph.COLD_START_TEXT), got[1].context)
    }

    @Test fun `QA_wiring_smsTitleTrimmedIsTheSenderButWhatsappTitleIsNot`() = runBlocking {
        val got = mutableListOf<ClassifyRequest>()
        val w = ListenerWiring(NotificationMapper(), { t, s -> qaVerdict(Label.SAFE, 0.9, t, s) }, { _, _ -> }, warm(), { r -> got += r; qaVerdict(Label.SAFE, 0.9, r.text) })
        w.onPosted(info("Your Amazon order is held, pay the fee now", "  AX-AMAZON  ", now))
        assertTrue(got[0].context.contains(GraphContext.SENDER_FIRST_TEXT))
        w.onPosted(NotificationInfo("com.whatsapp", "AX-AMAZON", "Your Amazon order is held, pay the fee later", false, false, now + 1))
        assertFalse(got[1].context.contains(GraphContext.SENDER_FIRST_TEXT))
    }
}
