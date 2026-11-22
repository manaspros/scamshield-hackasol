package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FusionTest {
    private fun rules(score: Double, label: Label) = RuleResult(score, label, listOf("t"), "rule reason")
    private fun llm(label: Label, conf: Double, type: ScamType? = null, reason: String = "llm reason") =
        LlmResult(label, conf, reason, type)

    @Test fun T1_5_gemmaDecides() {
        // weak rules never override the model, in either direction
        assertEquals(Label.SAFE, Fusion.fuse(llm(Label.SAFE, 0.9), rules(0.1, Label.SAFE), null).label)
        assertEquals(Label.SCAM, Fusion.fuse(llm(Label.SCAM, 0.8, ScamType.OTP), rules(0.0, Label.SAFE), null).label)
        assertEquals(Label.SUSPICIOUS, Fusion.fuse(llm(Label.SUSPICIOUS, 0.7, ScamType.KYC), rules(0.8, Label.SCAM), null).label)
        // SLM type wins over rule type; rule type fills in when SLM has none
        assertEquals(ScamType.KYC, Fusion.fuse(llm(Label.SCAM, 0.8, ScamType.KYC), rules(0.6, Label.SUSPICIOUS), ScamType.OTP).scamType)
        assertEquals(ScamType.OTP, Fusion.fuse(llm(Label.SUSPICIOUS, 0.8), rules(0.6, Label.SUSPICIOUS), ScamType.OTP).scamType)
        assertEquals("gemma+rules", Fusion.fuse(llm(Label.SAFE, 0.9), rules(0.1, Label.SAFE), null).engine)
        assertEquals("llm reason", Fusion.fuse(llm(Label.SAFE, 0.9), rules(0.1, Label.SAFE), null).reason)
        assertEquals("rule reason", Fusion.fuse(llm(Label.SAFE, 0.9, reason = ""), rules(0.1, Label.SAFE), null).reason)
    }

    @Test fun T1_5_rulesOnlyRaise() {
        val a = Fusion.fuse(llm(Label.SAFE, 0.9), rules(0.5, Label.SUSPICIOUS), ScamType.OTP)
        assertEquals(Label.SUSPICIOUS, a.label)
        assertEquals(ScamType.OTP, a.scamType)                 // SLM said SAFE (no type): rule type used
        // 0.7*0.5 + 0.3*support(SUSPICIOUS, 0.5)
        assertEquals(0.7 * 0.5 + 0.3 * (1 - 0.05 / 0.55), a.confidence, 1e-9)
        assertEquals(Label.SCAM, Fusion.fuse(llm(Label.SAFE, 0.9), rules(0.9, Label.SCAM), null).label)
        assertEquals(Label.SCAM, Fusion.fuse(llm(Label.SUSPICIOUS, 0.6), rules(0.9, Label.SCAM), null).label)
        // strong-but-below-0.85 rules do not lift SUSPICIOUS to SCAM; nothing is ever lowered
        assertEquals(Label.SUSPICIOUS, Fusion.fuse(llm(Label.SUSPICIOUS, 0.6), rules(0.8, Label.SCAM), null).label)
        assertEquals(Label.SCAM, Fusion.fuse(llm(Label.SCAM, 0.9), rules(0.0, Label.SAFE), null).label)
        assertNull(Fusion.fuse(llm(Label.SAFE, 0.9), rules(0.1, Label.SAFE), null).scamType)
    }

    @Test fun T1_5_confidence70_30() {
        assertEquals(1.0, FusionWeights.GEMMA + FusionWeights.RULES, 1e-12)
        assertEquals(0.7 * 0.8 + 0.3 * 0.6, Fusion.fuse(llm(Label.SCAM, 0.8, ScamType.OTP), rules(0.6, Label.SUSPICIOUS), null).confidence, 1e-9)
        assertEquals(0.7 * 0.9 + 0.3 * 0.9, Fusion.fuse(llm(Label.SAFE, 0.9), rules(0.1, Label.SAFE), null).confidence, 1e-9)
        // raised label: model confidence is replaced by 0.5, rule support for SCAM = score
        assertEquals(0.7 * 0.5 + 0.3 * 0.9, Fusion.fuse(llm(Label.SAFE, 0.99), rules(0.9, Label.SCAM), null).confidence, 1e-9)
    }

    @Test fun T1_5_rulesOnlyMode() {
        val scam = Fusion.fuse(null, rules(0.8, Label.SCAM), ScamType.OTP)
        assertEquals(Label.SCAM, scam.label)
        assertEquals(RuleScorer.confidence(rules(0.8, Label.SCAM)), scam.confidence, 1e-9)
        assertEquals(ScamType.OTP, scam.scamType)
        assertEquals("rules-only", scam.engine)
        assertEquals(listOf("t"), scam.triggers)
        val safe = Fusion.fuse(null, rules(0.1, Label.SAFE), null)
        assertEquals(Label.SAFE, safe.label)
        assertEquals(0.9, safe.confidence, 1e-9)
        assertNull(safe.scamType)
    }
}
