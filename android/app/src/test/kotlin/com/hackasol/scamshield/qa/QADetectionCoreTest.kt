package com.hackasol.scamshield.qa

import com.hackasol.scamshield.core.*
import org.junit.Assert.*
import org.junit.Test

class QADetectionCoreTest {
    // ---------- Rules engine ----------
    @Test fun `QA_rules_emptyAndWhitespaceAreSafeWithZeroScore`() {
        for (s in listOf("", "   ", "\n\t  ")) {
            val r = RuleScorer.score(s)
            assertEquals(Label.SAFE, r.label); assertEquals(0.0, r.score, 0.0); assertTrue(r.triggers.isEmpty())
        }
    }

    @Test fun `QA_rules_garbageUnicodeDoesNotThrow`() {
        val garbage = "\u0000😀​�क्ष\n\r" + "x".repeat(50)
        assertEquals(Label.SAFE, RuleScorer.score(garbage).label)
    }

    @Test(timeout = 20_000) fun `QA_rules_veryLongInputFinishesAndStaysSafe`() {
        val big = "code ab cd ".repeat(40_000) + "namaste " .repeat(40_000)
        assertEquals(Label.SAFE, RuleScorer.score(big).label)
    }

    @Test fun `QA_rules_devanagariOtpShareIsScam`() {
        assertEquals(Label.SCAM, RuleScorer.score("अपना ओटीपी बताइए").label)
    }

    @Test fun `QA_rules_hinglishSecrecyPlusStayOnCallIsScam`() {
        assertEquals(Label.SCAM, RuleScorer.score("Kisi ko mat batana aur call mat kaato").label)
    }

    @Test fun `QA_rules_digitalArrestIsCaseInsensitiveAndScam`() {
        assertEquals(Label.SCAM, RuleScorer.score("YOU ARE UNDER DIGITAL ARREST").label)
        assertEquals(Label.SCAM, RuleScorer.score("आप डिजिटल अरेस्ट में हैं").label)
    }

    @Test fun `QA_rules_singlePinRuleHitsScamThresholdExactly`() {
        val r = RuleScorer.score("send your UPI PIN")
        assertEquals(0.75, r.score, 1e-9); assertEquals(Label.SCAM, r.label)
    }

    @Test fun `QA_rules_kycAloneIsAHintNotAVerdict`() {
        // A genuine "KYC due" reminder is common; KYC only counts next to a block / link / call signal.
        val r = RuleScorer.score("your KYC is pending")
        assertEquals(0.35, r.score, 1e-9); assertEquals(Label.SAFE, r.label)
        assertEquals(Label.SCAM, RuleScorer.score("Your account will be blocked today, update KYC at http://sbi-kyc.xyz").label)
    }

    @Test fun `QA_rules_urgencyAloneIsSafe`() {
        assertEquals(Label.SAFE, RuleScorer.score("please come immediately").label)
    }

    @Test fun `QA_rules_wordBoundaryHotpotIsNotOtp`() {
        assertEquals(Label.SAFE, RuleScorer.score("I love hotpot").label)
    }

    @Test fun `QA_rules_benignHindiAndHinglishAreSafe`() {
        assertEquals(Label.SAFE, RuleScorer.score("बेटा खाना खा लिया, कल मिलते हैं").label)
        assertEquals(Label.SAFE, RuleScorer.score("Beta khana kha liya, kal shaam ko milte hain").label)
    }

    @Test fun `QA_rules_addingEvidenceNeverLowersScore`() {
        val base = "Main SBI bank se bol raha hoon"
        val a = RuleScorer.score(base).score
        val b = RuleScorer.score("$base, aapka KYC pending hai").score
        val c = RuleScorer.score("$base, aapka KYC pending hai, turant AnyDesk install karo").score
        assertTrue(a < b && b < c)
        assertTrue(c <= 1.0)
    }

    @Test fun `QA_rules_apkLinkIsAppInstall`() {
        assertTrue(RuleScorer.score("download SBI_rewards.APK now").triggers.any { it.contains(".apk", true) })
        assertTrue(RuleScorer.score("see https://x.example/pack.apks").triggers.none { it.contains(".apk", true) })
    }

    @Test fun `QA_rules_triggersAreDistinctAndTrimmed`() {
        val r = RuleScorer.score("OTP OTP OTP")
        assertEquals(r.triggers.distinct(), r.triggers)
        assertTrue(r.triggers.all { it == it.trim() })
    }

    // bug probes (kept here only if green; see QA_PendingDetectionCoreTest for the failing ones)

    // ---------- Scam type mapping ----------
    @Test fun `QA_scamType_safeTextIsNull`() { assertNull(RuleScorer.scamType("hello there")) }

    @Test fun `QA_scamType_hindiCourierWithCustomsAndDrugsIsCourier`() {
        assertEquals(ScamType.COURIER_CUSTOMS, RuleScorer.scamType("आपका पार्सल कस्टम में पकड़ा गया, उसमें ड्रग्स हैं"))
    }

    @Test fun `QA_scamType_parseAcceptsSeparatorsAndRejectsGarbage`() {
        assertEquals(ScamType.DIGITAL_ARREST, ScamType.parse(" digital-arrest "))
        assertEquals(ScamType.COURIER_CUSTOMS, ScamType.parse("courier customs"))
        assertNull(ScamType.parse("NONE")); assertNull(ScamType.parse("")); assertNull(ScamType.parse(null)); assertNull(ScamType.parse("OTP; DROP"))
    }

    @Test fun `QA_scamType_everyEnumNameRoundTrips`() {
        for (t in ScamType.values()) assertEquals(t, ScamType.parse(t.name.lowercase()))
    }

    @Test fun `QA_scamType_dashboardVocabularyMatchesEnum`() {
        val js = QAPaths.repoRoot.resolve("dashboard/agg.mjs").takeIf { it.exists() }?.readText() ?: return
        val block = js.substringAfter("SCAM_TYPES = Object.freeze([").substringBefore("])")
        val names = Regex("'([A-Z_]+)'").findAll(block).map { it.groupValues[1] }.toSet()
        assertEquals(ScamType.values().map { it.name }.toSet(), names)
    }

    // ---------- Gemma output parser ----------
    private fun p(s: String) = LlmOutputParser.parse(s)

    @Test fun `QA_parser_blankAndGarbageAreNull`() {
        for (s in listOf("", "   ", "lorem ipsum", "{\"foo\":1}", "label: MAYBE")) assertNull(s, p(s))
    }

    @Test fun `QA_parser_truncatedJsonStillYieldsLabelTypeAndDefaultConfidence`() {
        val r = p("{\"label\":\"SCAM\",\"scam_type\":\"OTP\",\"confid")!!
        assertEquals(Label.SCAM, r.label); assertEquals(ScamType.OTP, r.scamType); assertEquals(0.6, r.confidence, 1e-9)
    }

    @Test fun `QA_parser_percentAndWholeNumberConfidence`() {
        assertEquals(0.95, p("{\"label\":\"SCAM\",\"confidence\":\"95%\"}")!!.confidence, 1e-9)
        assertEquals(0.9, p("{\"label\":\"SCAM\",\"confidence\":90}")!!.confidence, 1e-9)
        assertEquals(1.0, p("{\"label\":\"SCAM\",\"confidence\":1}")!!.confidence, 1e-9)
        assertEquals(1.0, p("{\"label\":\"SCAM\",\"confidence\":500}")!!.confidence, 1e-9)
    }

    @Test fun `QA_parser_lowercaseLabelAndLegacyAliases`() {
        assertEquals(Label.SCAM, p("{\"label\":\"scam\"}")!!.label)
        assertEquals(Label.SAFE, p("{\"label\":\"genuine\"}")!!.label)
        assertEquals(Label.SCAM, p("label = FRAUD")!!.label)
    }

    @Test fun `QA_parser_labelKeyBeatsWordsInsideReason`() {
        assertEquals(Label.SCAM, p("{\"label\":\"SCAM\",\"reason\":\"this is not SAFE\"}")!!.label)
    }

    @Test fun `QA_parser_safeNeverCarriesScamType`() {
        assertNull(p("{\"label\":\"SAFE\",\"scam_type\":\"OTP\"}")!!.scamType)
    }

    @Test fun `QA_parser_scamWithNoneOrMissingTypeBecomesOther`() {
        assertEquals(ScamType.OTHER, p("{\"label\":\"SCAM\",\"scam_type\":\"NONE\"}")!!.scamType)
        assertEquals(ScamType.OTHER, p("{\"label\":\"SUSPICIOUS\"}")!!.scamType)
        assertEquals(ScamType.OTHER, p("{\"label\":\"SCAM\",\"scam_type\":\"BANANA\"}")!!.scamType)
    }

    @Test fun `QA_parser_reasonCappedAt120AndKeepsDevanagari`() {
        val long = "क".repeat(300)
        assertEquals(120, p("{\"label\":\"SCAM\",\"reason\":\"$long\"}")!!.reason.length)
        assertEquals("ओटीपी मांगा", p("{\"label\":\"SCAM\",\"reason\":\"ओटीपी मांगा\"}")!!.reason)
    }

    @Test fun `QA_parser_codeFenceAndProseWrapper`() {
        val r = p("Sure! ```json\n{\"label\":\"SUSPICIOUS\",\"scam_type\":\"KYC\",\"confidence\":0.7}\n``` hope it helps")!!
        assertEquals(Label.SUSPICIOUS, r.label); assertEquals(ScamType.KYC, r.scamType); assertEquals(0.7, r.confidence, 1e-9)
    }

    @Test fun `QA_parser_veryLongGarbageDoesNotHang`() {
        assertNull(p("a".repeat(500_000)))
    }

    // ---------- Gemma prompt builder ----------
    @Test fun `QA_prompt_emptyTextAndContext`() {
        val s = GemmaPrompt.build("", emptyList())
        assertTrue(s.endsWith("STATEMENT: \"\"\n")); assertFalse(s.contains("\nEarlier in this call: "))
    }

    // 8 few-shots (2 with Known context) + the query.
    @Test fun `QA_prompt_sevenStatementsSixShotsPlusQuery`() {
        assertEquals(9,Regex("STATEMENT: \"").findAll(GemmaPrompt.build("x", emptyList())).count())
    }

    @Test fun `QA_prompt_onlyLastTwoContextEntriesInOrder`() {
        val s = GemmaPrompt.build("q", listOf("one", "two", "three"))
        assertTrue(s.contains("Earlier in this call: \"two\" | \"three\"\n"))
        assertFalse(s.contains("\"one\""))
    }

    @Test fun `QA_prompt_textCutAt300AndQuotesSoftened`() {
        val s = GemmaPrompt.build("\"" + "a".repeat(400), emptyList())
        assertTrue(s.endsWith("STATEMENT: \"'" + "a".repeat(299) + "\"\n"))
    }

    @Test fun `QA_prompt_contextEntriesCutAt150KeepQuotes`() {
        val s = GemmaPrompt.build("q", listOf("b".repeat(200)))
        assertTrue(s.contains("\"" + "b".repeat(150) + "\"\n"))
    }

    @Test fun `QA_prompt_devanagariPassesThroughUnchanged`() {
        assertTrue(GemmaPrompt.build("ओटीपी बताइए", listOf("नमस्ते")).contains("STATEMENT: \"ओटीपी बताइए\""))
    }

    // ---------- Fusion ----------
    private fun llm(l: Label, c: Double, t: ScamType? = null, reason: String = "llm") = LlmResult(l, c, reason, t)
    private fun rr(score: Double) = RuleResult(score, when { score >= 0.75 -> Label.SCAM; score >= 0.4 -> Label.SUSPICIOUS; else -> Label.SAFE }, listOf("t"), "rule")

    @Test fun `QA_fusion_rulesNeverLowerAnyModelLabelOverFullGrid`() {
        val scores = (0..100).map { it / 100.0 }
        for (l in Label.values()) for (c in listOf(0.0, 0.3, 0.5, 0.9, 1.0)) for (s in scores) {
            val f = Fusion.fuse(llm(l, c), rr(s), null)
            assertTrue("$l c=$c s=$s -> ${f.label}", f.label.ordinal >= l.ordinal)
        }
    }

    @Test fun `QA_fusion_confidenceAlwaysWithinUnitInterval`() {
        for (l in Label.values()) for (c in listOf(0.0, 0.5, 1.0)) for (s in (0..20).map { it / 20.0 }) {
            val f = Fusion.fuse(llm(l, c), rr(s), null)
            assertTrue(f.confidence in 0.0..1.0)
        }
    }

    @Test fun `QA_fusion_raiseToScamBoundary0_85`() {
        assertEquals(Label.SCAM, Fusion.fuse(llm(Label.SUSPICIOUS, 0.9), rr(0.85), null).label)
        assertEquals(Label.SUSPICIOUS, Fusion.fuse(llm(Label.SUSPICIOUS, 0.9), rr(0.8499), null).label)
        assertEquals(Label.SCAM, Fusion.fuse(llm(Label.SAFE, 0.99), rr(0.85), null).label)
    }

    @Test fun `QA_fusion_safeRaisedToSuspiciousAtExactly0_40`() {
        assertEquals(Label.SUSPICIOUS, Fusion.fuse(llm(Label.SAFE, 0.9), rr(0.40), null).label)
        assertEquals(Label.SAFE, Fusion.fuse(llm(Label.SAFE, 0.9), rr(0.3999), null).label)
        assertEquals(Label.SAFE, Fusion.fuse(llm(Label.SAFE, 0.9), rr(0.30), null).label)
    }

    @Test fun `QA_fusion_modelScamSurvivesZeroRuleEvidence`() {
        val f = Fusion.fuse(llm(Label.SCAM, 0.95), rr(0.0), null)
        assertEquals(Label.SCAM, f.label); assertEquals(0.7 * 0.95, f.confidence, 1e-9)
    }

    @Test fun `QA_fusion_exact70_30Formula`() {
        assertEquals(0.7 * 0.9 + 0.3 * 0.5, Fusion.fuse(llm(Label.SCAM, 0.9), rr(0.5), null).confidence, 1e-9)
    }

    @Test fun `QA_fusion_raisedLabelIgnoresModelConfidence`() {
        val a = Fusion.fuse(llm(Label.SAFE, 0.99), rr(0.9), null)
        val b = Fusion.fuse(llm(Label.SAFE, 0.01), rr(0.9), null)
        assertEquals(a.confidence, b.confidence, 1e-12)
        assertEquals(0.7 * 0.5 + 0.3 * 0.9, a.confidence, 1e-9)
    }

    @Test fun `QA_fusion_safeVerdictHasNoScamTypeEvenIfRuleTypeGiven`() {
        assertNull(Fusion.fuse(llm(Label.SAFE, 0.9, ScamType.OTP), rr(0.1), ScamType.KYC).scamType)
    }

    @Test fun `QA_fusion_modelTypeBeatsRuleTypeAndFallbackWorks`() {
        assertEquals(ScamType.JOB, Fusion.fuse(llm(Label.SCAM, 0.9, ScamType.JOB), rr(0.5), ScamType.KYC).scamType)
        assertEquals(ScamType.KYC, Fusion.fuse(llm(Label.SCAM, 0.9, null), rr(0.5), ScamType.KYC).scamType)
    }

    @Test fun `QA_fusion_blankModelReasonFallsBackToRuleReason`() {
        assertEquals("rule", Fusion.fuse(llm(Label.SCAM, 0.9, reason = ""), rr(0.5), null).reason)
        assertEquals("llm", Fusion.fuse(llm(Label.SCAM, 0.9), rr(0.5), null).reason)
    }

    @Test fun `QA_fusion_rulesOnlyEngineAndConfidenceBoundaries`() {
        val sus = Fusion.fuse(null, rr(0.40), null); assertEquals("rules-only", sus.engine)
        assertEquals(0.5, sus.confidence, 1e-9)
        assertEquals(0.8, Fusion.fuse(null, rr(0.7499), null).confidence, 0.01)
        assertEquals(0.75, Fusion.fuse(null, rr(0.75), null).confidence, 1e-9)
        assertEquals(1.0, Fusion.fuse(null, rr(0.0), null).confidence, 1e-9)
        assertEquals(0.61, Fusion.fuse(null, rr(0.39), null).confidence, 1e-9)
        assertEquals("gemma+rules", Fusion.fuse(llm(Label.SAFE, 0.9), rr(0.0), null).engine)
    }

    @Test fun `QA_fusion_endToEndHinglishScamNotLoweredByConfidentlySafeModel`() {
        val text = "Main CBI se bol raha hoon, digital arrest, kisi ko mat batana, AnyDesk install karo"
        val rules = RuleScorer.score(text)
        val f = Fusion.fuse(llm(Label.SAFE, 0.99), rules, RuleScorer.scamType(text))
        assertEquals(Label.SCAM, f.label)
        assertEquals(ScamType.DIGITAL_ARREST, f.scamType)
    }
}
