package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Round-3 coverage: new rule tags, new ScamType routing, and Fusion behaviour on top of them. */
class R3CovRulesTest {
    private class Row(val text: String, val label: Label, val type: ScamType?, val id: String)

    private fun parseCsv(s: String): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val f = StringBuilder()
        var inQ = false
        var i = 0
        fun endField() { row.add(f.toString()); f.setLength(0) }
        fun endRow() { endField(); if (!(row.size == 1 && row[0].isEmpty())) rows.add(row); row = mutableListOf() }
        while (i < s.length) {
            val c = s[i]
            when {
                inQ && c == '"' && i + 1 < s.length && s[i + 1] == '"' -> { f.append('"'); i++ }
                c == '"' -> inQ = !inQ
                !inQ && c == ',' -> endField()
                !inQ && c == '\r' -> {}
                !inQ && c == '\n' -> endRow()
                else -> f.append(c)
            }
            i++
        }
        if (f.isNotEmpty() || row.isNotEmpty()) endRow()
        return rows
    }

    private val r3Rows: List<Row> by lazy {
        parseCsv(File("../../data/golden/eval_smoke.csv").readText(Charsets.UTF_8)).drop(1)
            .filter { it[4].startsWith("r3_") }
            .map { Row(it[0], Label.valueOf(it[1]), ScamType.parse(it[3]), it[4]) }
    }

    private fun fuse(text: String, llm: LlmResult?): FusedResult =
        Fusion.fuse(llm, RuleScorer.score(text), RuleScorer.scamType(text))

    private val saferLowConf = LlmResult(Label.SAFE, 0.3, "looks fine", null)
    private val saferHighConf = LlmResult(Label.SAFE, 0.95, "looks fine", null)

    private fun positives(t: ScamType) {
        val rows = r3Rows.filter { it.id.startsWith("r3_${t.name.lowercase()}_pos") }
        assertTrue("no r3 positives for $t", rows.size >= 3)
        for (r in rows) {
            val rules = RuleScorer.score(r.text)
            assertTrue("rules-only ${rules.label} (${rules.score}) < SUSPICIOUS: ${r.id}", rules.label != Label.SAFE)
            if (r.label == Label.SCAM) assertEquals("expected SCAM from rules: ${r.id} score=${rules.score}", Label.SCAM, rules.label)
            assertEquals("type: ${r.id}", t, RuleScorer.scamType(r.text))
            // (a) rules-only
            val a = fuse(r.text, null)
            assertEquals(r.id, rules.label, a.label); assertEquals(r.id, t, a.scamType)
            // (b) Gemma says SAFE with low confidence: rules raise (never lower)
            val b = fuse(r.text, saferLowConf)
            assertTrue("fused ${b.label}: ${r.id}", b.label != Label.SAFE)
            assertEquals(r.id, t, b.scamType)
            // (c) documented Fusion behaviour: confidence of a SAFE Gemma does not gate the raise
            assertEquals(r.id, b.label, fuse(r.text, saferHighConf).label)
        }
    }

    private fun hardNegatives(t: ScamType) {
        val rows = r3Rows.filter { it.id.startsWith("r3_${t.name.lowercase()}_neg") }
        assertTrue("no r3 negatives for $t", rows.size >= 2)
        for (r in rows) {
            assertEquals("rules: ${r.id}", Label.SAFE, RuleScorer.score(r.text).label)
            assertEquals("fuse null: ${r.id}", Label.SAFE, fuse(r.text, null).label)
            assertEquals("fuse safe: ${r.id}", Label.SAFE, fuse(r.text, saferLowConf).label)
        }
    }

    @Test fun R3_COV_ELECTRICITY_BILL_positives() = positives(ScamType.ELECTRICITY_BILL)
    @Test fun R3_COV_ELECTRICITY_BILL_hardNegatives() = hardNegatives(ScamType.ELECTRICITY_BILL)
    @Test fun R3_COV_SIM_SWAP_positives() = positives(ScamType.SIM_SWAP)
    @Test fun R3_COV_SIM_SWAP_hardNegatives() = hardNegatives(ScamType.SIM_SWAP)
    @Test fun R3_COV_CUSTOMER_CARE_positives() = positives(ScamType.CUSTOMER_CARE)
    @Test fun R3_COV_CUSTOMER_CARE_hardNegatives() = hardNegatives(ScamType.CUSTOMER_CARE)
    @Test fun R3_COV_UPI_COLLECT_positives() = positives(ScamType.UPI_COLLECT)
    @Test fun R3_COV_UPI_COLLECT_hardNegatives() = hardNegatives(ScamType.UPI_COLLECT)
    @Test fun R3_COV_JOB_positives() = positives(ScamType.JOB)
    @Test fun R3_COV_JOB_hardNegatives() = hardNegatives(ScamType.JOB)
    @Test fun R3_COV_INVESTMENT_positives() = positives(ScamType.INVESTMENT)
    @Test fun R3_COV_INVESTMENT_hardNegatives() = hardNegatives(ScamType.INVESTMENT)
    @Test fun R3_COV_SEXTORTION_positives() = positives(ScamType.SEXTORTION)
    @Test fun R3_COV_SEXTORTION_hardNegatives() = hardNegatives(ScamType.SEXTORTION)
    @Test fun R3_COV_LOAN_APP_positives() = positives(ScamType.LOAN_APP)
    @Test fun R3_COV_LOAN_APP_hardNegatives() = hardNegatives(ScamType.LOAN_APP)
    @Test fun R3_COV_COURIER_CUSTOMS_positives() = positives(ScamType.COURIER_CUSTOMS)
    @Test fun R3_COV_COURIER_CUSTOMS_hardNegatives() = hardNegatives(ScamType.COURIER_CUSTOMS)
    @Test fun R3_COV_LOTTERY_positives() = positives(ScamType.LOTTERY)
    @Test fun R3_COV_LOTTERY_hardNegatives() = hardNegatives(ScamType.LOTTERY)
    @Test fun R3_COV_FAMILY_EMERGENCY_positives() = positives(ScamType.FAMILY_EMERGENCY)
    @Test fun R3_COV_FAMILY_EMERGENCY_hardNegatives() = hardNegatives(ScamType.FAMILY_EMERGENCY)
    @Test fun R3_COV_FAKE_QR_positives() = positives(ScamType.FAKE_QR)
    @Test fun R3_COV_FAKE_QR_hardNegatives() = hardNegatives(ScamType.FAKE_QR)
    @Test fun R3_COV_PHISHING_LINK_positives() = positives(ScamType.PHISHING_LINK)
    @Test fun R3_COV_PHISHING_LINK_hardNegatives() = hardNegatives(ScamType.PHISHING_LINK)

    @Test fun R3_COV_genuineBankOtpBillCourierStaySafe() {
        val genuine = listOf(
            "Your OTP is 123456. Do not share it with anyone",
            "Your electricity bill of Rs 1,240 is due on 05-12. Pay via the official app",
            "Your parcel AWB 12345 is out for delivery",
            "Your recharge of Rs 299 is successful",
            "Papa I reached the hostel, will call at night",
            "Rs 500 credited to your a/c via UPI",
            "Your interview for Software Engineer is scheduled on 10 Dec at 11 am",
            "Please see https://www.onlinesbi.sbi for your statement",
            "कस्टमर केयर: आपकी शिकायत दर्ज हो गई है। आधिकारिक ऐप में ट्रैक करें।",
            "à¤à¤¸à¥à¤à¤®à¤° à¤à¥à¤¯à¤°: à¤à¤ªà¤à¥ à¤¶à¤¿à¤à¤¾à¤¯à¤¤ à¤¦à¤°à¥à¤ à¤¹à¥ à¤à¤ à¤¹à¥à¥¤ à¤à¤§à¤¿à¤à¤¾à¤°à¤¿à¤ à¤à¤ª à¤®à¥à¤ à¤à¥à¤°à¥à¤ à¤à¤°à¥à¤à¥¤",
        )
        for (g in genuine) {
            assertEquals(g, Label.SAFE, RuleScorer.score(g).label)
            assertEquals(g, Label.SAFE, fuse(g, null).label)
            assertEquals(g, Label.SAFE, fuse(g, saferLowConf).label)
        }
    }

    @Test fun R3_COV_bareShortLinkIsAtMostSuspicious() {
        val l = RuleScorer.score("see https://bit.ly/3abcXY")
        assertEquals(Label.SUSPICIOUS, l.label)
        assertTrue(RuleScorer.score("see https://tinyurl.com/x1 now").score < RuleScorer.SCAM_AT)
    }

    @Test fun R3_COV_urlHeuristicsFlagPunycodeIpAndRiskyTld() {
        for (u in listOf("http://xn--sbi-kyc.example/login", "http://10.0.0.5/pay", "https://kyc-check.top/a", "https://example-refund-help.live/x"))
            assertEquals(u, ScamType.PHISHING_LINK, RuleScorer.scamType("Open $u"))
    }

    @Test fun R3_COV_csvRowsRulesOnlyLabelMatchesIntent() {
        val rows = r3Rows
        assertTrue(rows.size >= 60)
        for (r in rows) {
            val got = RuleScorer.score(r.text).label
            if (r.label == Label.SAFE) assertEquals("negative ${r.id}", Label.SAFE, got)
            else assertTrue("positive ${r.id} got $got", got != Label.SAFE)
        }
    }
}
