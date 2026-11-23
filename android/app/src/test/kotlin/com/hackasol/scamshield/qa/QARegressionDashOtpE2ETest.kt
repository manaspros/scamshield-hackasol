package com.hackasol.scamshield.qa

import com.hackasol.scamshield.core.*
import org.junit.Assert.*
import org.junit.Test

/** Dash-split OTP must not reach log/report/ZIP/notification (fixed in ea3f96e). */
class QARegressionDashOtpE2ETest {
    @Test fun `QA_otpE2E_digitsSplitByDashes`() {
        val r = RuleScorer.score("OTP 482-913 please bhejo")
        val f = Fusion.fuse(null, r, RuleScorer.scamType("OTP 482-913 please bhejo"))
        val ev = VerdictEvent(1, 10_000_000_000L, Source.SMS, Label.SCAM, 0.9, ScamType.OTP, f.triggers, f.engine)
        val json = ReportPack.build(listOf(ev), true, 10_000_001_000L).toJson()
        assertFalse("report JSON leaks dash-split OTP: $json", json.contains("482-913"))
        assertTrue("triggers ${f.triggers}", f.triggers.all { t -> t.count { Character.isDigit(it) } < 4 })
    }
}
