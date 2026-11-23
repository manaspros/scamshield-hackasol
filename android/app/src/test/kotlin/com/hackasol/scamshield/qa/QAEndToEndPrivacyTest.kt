package com.hackasol.scamshield.qa

import com.hackasol.scamshield.VerdictRowMapper
import com.hackasol.scamshield.core.*
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

/**
 * Pushes sensitive inputs through RuleScorer -> Fusion -> verdict log row mapping -> ReportPack/CaseCard
 * -> EvidenceZip -> trend export -> notification mapping, and asserts the secret appears in none of them.
 */
class QAEndToEndPrivacyTest {
    private val now = 10_000_000_000L

    /** Input text plus every literal form that must never be persisted or shown. */
    private class Case(val name: String, val text: String, val forbidden: List<String>)

    private val cases = listOf(
        Case("ascii", "OTP 482913 please bhejo", listOf("482913")),
        Case("sentence", "Your OTP is 482913, please bhejo it", listOf("482913")),
        Case("spaced", "OTP 4 8 2 9 1 3 please bhejo", listOf("4 8 2 9 1 3", "482913")),
        Case("devanagariDigits", "ओटीपी ४८२९१३ बताइए", listOf("४८२९१३", "482913")),
        Case("devanagariOtpAsciiDigits", "ओटीपी 482913 बताइए", listOf("482913")),
        Case("longDigitRun", "OTP " + "1234".repeat(9) + " bhejo", listOf("1234123412341234")),
        Case("straddlesCap", "otp " + "a".repeat(35) + "482913 bhejo", listOf("482913", "4829", "829", "a".repeat(36))),
        Case("pinAndUpi", "UPI PIN 123456 batao, pay ramesh.kumar@oksbi", listOf("123456", "ramesh.kumar@oksbi")),
        Case("upiOnly", "safe account transfer karo to ramesh@ybl, OTP bhejo", listOf("ramesh@ybl")),
        Case("upiUppercase", "send OTP code, pay RAMESH.KUMAR@OKSBI now, transfer karo", listOf("ramesh.kumar@oksbi")),
    )

    private fun digitsOnly(s: String) = s.filter { Character.isDigit(it) }

    private fun outputs(c: Case, llm: LlmResult?): Map<String, String> {
        val rules = RuleScorer.score(c.text)
        val f = Fusion.fuse(llm, rules, RuleScorer.scamType(c.text))
        // Force a notifiable label so the notification path is exercised for every case.
        val v = Verdict(c.text, Label.SCAM, 0.9, f.reason, f.triggers, f.engine, 0, Source.SMS, scamType = f.scamType ?: ScamType.OTP)
        val ev = VerdictEvent(1, now, Source.SMS, Label.SCAM, 0.9, v.scamType, f.triggers, f.engine)
        val card = CaseCard(GoldenHour(now - 10), ReportPack.build(listOf(ev), true, now + 1000))
        val zip = EvidenceZip.build(card, listOf(ev))
        val out = linkedMapOf(
            "fused.triggers" to f.triggers.joinToString("\u0001"),
            "row" to VerdictRowMapper.toRow(ev).values.joinToString("\u0001"),
            "channelMap" to VerdictRowMapper.toChannelMap(ev).values.joinToString("\u0001"),
            "reportPack" to card.pack.toJson(),
            "caseCard" to card.toJson(),
            "eventsJson" to EvidenceZip.eventsJson(listOf(ev)),
            "trend" to TrendExport.export(listOf(ev), "Raipur"),
        )
        ZipInputStream(ByteArrayInputStream(zip)).use { z ->
            while (true) { val e = z.nextEntry ?: break; out["zip:${e.name}"] = String(z.readBytes(), Charsets.UTF_8) }
        }
        val n = AlertNotificationMapper.fields(AlertPolicy.plan(v, Source.SMS), v, v.scamType)!!
        out["notification"] = n.title + "\u0001" + n.text + "\u0001" + n.actions.joinToString { it.label + it.route }
        return out
    }

    private val llms = listOf<LlmResult?>(null, LlmResult(Label.SAFE, 0.95, "ok"), LlmResult(Label.SCAM, 0.9, "scam", ScamType.OTP))

    @Test fun `QA_e2ePrivacy_secretsAppearInNoOutput`() {
        for (c in cases) for (llm in llms) for ((where, s) in outputs(c, llm)) {
            if (where == "zip:manifest.json") continue   // only hex hashes; checked separately
            for (bad in c.forbidden) assertFalse("${c.name} leaked '$bad' in $where (llm=${llm?.label}): $s", s.lowercase().contains(bad.lowercase()))
        }
    }

    @Test fun `QA_e2ePrivacy_noTriggerCarriesFourOrMoreDigitsEvenWhenSplit`() {
        for (c in cases) for (t in RuleScorer.score(c.text).triggers)
            assertTrue("${c.name}: trigger '$t' carries ${digitsOnly(t).length} digits", digitsOnly(t).length < 4)
    }

    @Test fun `QA_e2ePrivacy_noTriggerContainsAnUpiId`() {
        for (c in cases) for (t in RuleScorer.score(c.text).triggers)
            assertFalse("${c.name}: trigger '$t'", Regex("[\\w.-]+@[a-z]+", RegexOption.IGNORE_CASE).containsMatchIn(t))
    }

    @Test fun `QA_e2ePrivacy_triggersRespectThe40CharCap`() {
        for (c in cases) for (t in RuleScorer.score(c.text).triggers) assertTrue("${c.name}: '$t' is ${t.length} chars", t.length <= 40)
    }

    @Test fun `QA_e2ePrivacy_notificationShowsNoMoreThanCappedTriggerAndNoRawText`() {
        for (c in cases) {
            val f = Fusion.fuse(null, RuleScorer.score(c.text), null)
            val v = Verdict(c.text, Label.SCAM, 0.9, "r", f.triggers, "rules-only", 0, Source.SMS)
            val n = AlertNotificationMapper.fields(AlertPolicy.plan(v, Source.SMS), v)!!
            assertFalse(c.name, n.text.contains(c.text)); assertTrue(c.name, digitsOnly(n.text).length < 4)
        }
    }

    @Test fun `QA_e2ePrivacy_stillDetectsTheScamWhileMasking`() {
        for (c in cases.filter { it.name in setOf("ascii", "spaced", "dashed", "devanagariDigits", "pinAndUpi") }) {
            val r = RuleScorer.score(c.text)
            assertTrue("${c.name} score ${r.score}", r.label != Label.SAFE)
            assertTrue("${c.name} has no trigger left", r.triggers.isNotEmpty())
        }
    }

    @Test fun `QA_e2ePrivacy_manifestOnlyContainsHashesAndNames`() {
        val ev = qaEvent(1, now, triggers = RuleScorer.score("OTP 482913 please bhejo").triggers)
        val card = CaseCard(GoldenHour(now), ReportPack.build(listOf(ev), true, now + 1))
        val zip = EvidenceZip.build(card, listOf(ev)); var man = ""
        ZipInputStream(ByteArrayInputStream(zip)).use { z -> while (true) { val e = z.nextEntry ?: break; val b = z.readBytes(); if (e.name == "manifest.json") man = String(b) } }
        assertTrue(Regex("^\\{\"sha256\":\\{(\"[a-z]+\\.json\":\"[0-9a-f]{64}\",?){2}\\}\\}$").matches(man))
    }

    @Test fun `QA_e2ePrivacy_dashSplitPinIsMasked`() {
        for (t in RuleScorer.score("UPI PIN 12-34-56 batao").triggers) assertTrue(t, t.count { Character.isDigit(it) } < 4)
    }

    @Test fun `QA_e2ePrivacy_verdictEventStillHasNoTextField`() {
        assertFalse(VerdictEvent::class.java.declaredFields.any { it.name.contains("text", true) || it.name.contains("message", true) })
    }
}
