package com.hackasol.scamshield

import com.hackasol.scamshield.core.AlertNotificationMapper
import com.hackasol.scamshield.core.AlertPolicy
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.ScamType
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.Verdict
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AlertDispatcherMappingTest {
    private fun v(label: Label, source: Source, triggers: List<String> = listOf("OTP bata dijiye")) = Verdict(
        text = "synthetic message", label = label, confidence = 0.9, reason = "test",
        triggers = triggers, engine = "rules-only", latencyMs = 0, source = source,
    )

    private fun fields(x: Verdict, type: ScamType? = null) =
        AlertNotificationMapper.fields(AlertPolicy.plan(x, x.source), x, type)

    @Test fun T1_7_scamHasReportAction() {
        val f = fields(v(Label.SCAM, Source.CAPTION), ScamType.OTP)!!
        // In-call SCAM shows a card; its notification is a silent record (never a heads-up over the call).
        assertEquals("scam_suspicious", f.channelId)
        assertFalse(f.priorityHigh)
        assertEquals(listOf("report"), f.actions.map { it.route })
        assertTrue(f.title.contains("SCAM"))
        assertTrue(f.text.contains("OTP ठगी"))
        assertTrue(f.text.contains("OTP bata dijiye"))
    }

    @Test fun T1_7_suspiciousSmsNotifiesWithReport() {
        val f = fields(v(Label.SUSPICIOUS, Source.SMS))
        assertNotNull(f)
        assertEquals("report", f!!.actions.single().route)
    }

    @Test fun T1_7_safeHasNoNotification() = assertNull(fields(v(Label.SAFE, Source.SMS)))

    @Test fun T1_7_suspiciousCaptionBubbleOnly() {
        val x = v(Label.SUSPICIOUS, Source.CAPTION)
        assertTrue(AlertPolicy.plan(x, x.source).bubble)
        assertNull(fields(x))
    }

    @Test fun T1_7_noTriggerNoTypeStillShort() {
        val f = fields(v(Label.SCAM, Source.PASTE, emptyList()))!!
        assertEquals("OTP/PIN/पैसे न दें", f.text)
    }

    @Test fun T1_7_longTriggerTruncated() {
        val f = fields(v(Label.SCAM, Source.SMS, listOf("x".repeat(200))))!!
        assertTrue(f.text.length < 80)
    }
}
