package com.hackasol.scamshield.qa

import com.hackasol.scamshield.VerdictRowMapper
import com.hackasol.scamshield.core.*
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

/**
 * RuleScorer -> Fusion -> verdict-log row mapping -> ReportPack/CaseCard JSON -> EvidenceZip entries ->
 * AlertNotificationMapper text. No 4+ digit run from the input (ASCII or Devanagari form) and no UPI id may appear.
 */
class QAOtpPrivacyE2ETest {
    private val ts = 10_000_000_000L
    private val upiRe = Regex("[\\w.-]+@[a-z]+", RegexOption.IGNORE_CASE)

    /** ASCII digits of [s] with Devanagari digits normalised. */
    private fun ascii(s: String) = s.map { c -> if (Character.isDigit(c)) Character.digit(c, 10).toString() else "$c" }.joinToString("")

    /** Every secret that must be absent: digit runs (>=4) in raw and ASCII form, split-digit joins, UPI ids. */
    private fun secrets(text: String): List<String> {
        val out = mutableSetOf<String>()
        Regex("\\p{Nd}[\\p{Nd} -]{2,}\\p{Nd}").findAll(text).forEach { m ->
            val joined = ascii(m.value).filter { it.isDigit() }
            if (joined.length >= 4) { out += m.value.trim(); out += joined; out += m.value.filter { Character.isDigit(it) } }
        }
        upiRe.findAll(text).forEach { out += it.value.lowercase() }
        return out.filter { it.length >= 4 }
    }

    private fun pipeline(text: String, llm: LlmResult?): Map<String, String> {
        val rules = RuleScorer.score(text)
        val f = Fusion.fuse(llm, rules, RuleScorer.scamType(text))
        val type = f.scamType ?: ScamType.OTP
        val ev = VerdictEvent(1, ts, Source.SMS, Label.SCAM, 0.9, type, f.triggers, f.engine)
        val v = Verdict(text, Label.SCAM, 0.9, f.reason, f.triggers, f.engine, 0, Source.SMS, scamType = type)
        val card = CaseCard(GoldenHour(ts - 10), ReportPack.build(listOf(ev), true, ts + 1000))
        val out = linkedMapOf(
            "fused.triggers" to f.triggers.joinToString("\u0001"),
            "log.row" to VerdictRowMapper.toRow(ev).values.joinToString("\u0001"),
            "log.channel" to VerdictRowMapper.toChannelMap(ev).values.joinToString("\u0001"),
            "reportPack.json" to card.pack.toJson(),
            "caseCard.json" to card.toJson(),
        )
        ZipInputStream(ByteArrayInputStream(EvidenceZip.build(card, listOf(ev)))).use { z ->
            while (true) { val e = z.nextEntry ?: break; val body = String(z.readBytes(), Charsets.UTF_8); if (e.name != "manifest.json") out["zip:${e.name}"] = body }
        }
        val n = AlertNotificationMapper.fields(AlertPolicy.plan(v, Source.SMS), v, type)!!
        out["notification"] = n.title + "\u0001" + n.text
        return out
    }

    private val llms = listOf<LlmResult?>(null, LlmResult(Label.SAFE, 0.9, "ok"), LlmResult(Label.SCAM, 0.9, "scam", ScamType.OTP))

    private fun assertClean(text: String) {
        val bad = secrets(text)
        assertTrue("test setup: no secrets derived from '$text'", bad.isNotEmpty())
        for (llm in llms) for ((where, s) in pipeline(text, llm)) {
            for (b in bad) assertFalse("'$b' leaked in $where (llm=${llm?.label}): $s", s.lowercase().contains(b.lowercase()))
        }
        for (t in RuleScorer.score(text).triggers) assertTrue("trigger '$t' keeps ${t.count { Character.isDigit(it) }} digits", t.count { Character.isDigit(it) } < 4)
    }

    @Test fun `QA_otpE2E_plainOtp`() = assertClean("OTP 482913 please bhejo")
    @Test fun `QA_otpE2E_upiIdAsk`() = assertClean("send to ramesh123@okaxis")
    @Test fun `QA_otpE2E_upiIdWithOtpAsk`() = assertClean("OTP bhejo to ramesh123@okaxis, transfer karo")
    @Test fun `QA_otpE2E_digitsSplitBySpaces`() = assertClean("OTP 4 8 2 9 1 3 please bhejo")
    @Test fun `QA_otpE2E_devanagariDigits`() = assertClean("ओटीपी ४८२९१३ बताओ")
    @Test fun `QA_otpE2E_straddlesCapAtChar39`() = assertClean("otp " + "a".repeat(35) + "482913 bhejo")
    @Test fun `QA_otpE2E_straddlesCapAtChar38`() = assertClean("otp " + "a".repeat(34) + "482913 bhejo")
    @Test fun `QA_otpE2E_straddlesCapAtChar36`() = assertClean("otp " + "a".repeat(32) + "482913 bhejo")

    @Test fun `QA_otpE2E_scamStillDetectedAndTriggerKept`() {
        for (t in listOf("OTP 482913 please bhejo", "ओटीपी ४८२९१३ बताओ", "OTP 4 8 2 9 1 3 please bhejo")) {
            val r = RuleScorer.score(t)
            assertNotEquals(t, Label.SAFE, r.label); assertTrue(t, r.triggers.isNotEmpty() && r.triggers.all { it.length <= 40 })
        }
    }

    @Test fun `QA_otpE2E_secretsHelperActuallyFindsTheSecrets`() {
        assertTrue(secrets("OTP 482-913 x").contains("482913")); assertTrue(secrets("ओटीपी ४८२९१३").contains("482913"))
        assertTrue(secrets("send to ramesh123@okaxis").contains("ramesh123@okaxis"))
    }
}
