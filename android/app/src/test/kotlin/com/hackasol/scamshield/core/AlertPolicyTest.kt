package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Test

class AlertPolicyTest {
    private fun verdict(label: Label, source: Source) = Verdict(
        text = "synthetic message", label = label, confidence = 0.9, reason = "test",
        triggers = emptyList(), engine = "rules-only", latencyMs = 0, source = source,
    )

    private fun plan(label: Label, source: Source) = AlertPolicy.plan(verdict(label, source), source)

    private fun assertPlan(label: Label, source: Source, bubble: Boolean, notify: Boolean) =
        assertEquals("$label/$source", AlertPlan(bubble, notify, bubble || notify), plan(label, source))

    @Test fun T1_6_scamCaption() = assertPlan(Label.SCAM, Source.CAPTION, bubble = true, notify = true)

    @Test fun T1_6_scamSms() = assertPlan(Label.SCAM, Source.SMS, bubble = false, notify = true)

    @Test fun T1_6_scamOtherSources() {
        for (s in Source.values().filter { it != Source.CAPTION && it != Source.SIGNAL })
            assertPlan(Label.SCAM, s, bubble = false, notify = true)
    }

    @Test fun T1_6_suspiciousCaption() = assertPlan(Label.SUSPICIOUS, Source.CAPTION, bubble = true, notify = false)

    @Test fun T1_6_suspiciousRecording() = assertPlan(Label.SUSPICIOUS, Source.RECORDING, bubble = false, notify = true)

    @Test fun T1_6_suspiciousOtherSources() {
        for (s in Source.values().filter { it != Source.CAPTION && it != Source.SIGNAL })
            assertPlan(Label.SUSPICIOUS, s, bubble = false, notify = true)
    }

    @Test fun T1_6_safeAllSources() {
        for (s in Source.values()) assertPlan(Label.SAFE, s, bubble = false, notify = false)
    }

    @Test fun T1_6_planUsesVerdictSourceByDefault() =
        assertEquals(plan(Label.SCAM, Source.WHATSAPP), AlertPolicy.plan(verdict(Label.SCAM, Source.WHATSAPP)))
}
