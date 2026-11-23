package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AlertMapperR3Test {
    private val deva = Regex("[\\u0900-\\u097F]")

    private fun v(label: Label, source: Source) = Verdict(
        text = "synthetic message", label = label, confidence = 0.87, reason = "test",
        triggers = listOf("OTP bata dijiye"), engine = "gemma-demo-engine", latencyMs = 0, source = source,
    )

    private fun fields(label: Label, source: Source, lang: String = "hi") =
        v(label, source).let { AlertNotificationMapper.fields(AlertPolicy.plan(it, it.source), it, ScamType.OTP, lang)!! }

    @Test fun R3_ALERT_scamMapsToHighChannelWithReportAndDetails() {
        val f = fields(Label.SCAM, Source.SMS)
        assertEquals("scam_alerts_v2", f.channelId)
        assertNotEquals("old channel id keeps user-owned importance", "scam_alerts", f.channelId)
        assertTrue(f.priorityHigh && f.onlyAlertOnce && f.messageCategory)
        assertEquals(listOf("report", "details"), f.actions.map { it.route })
        assertEquals(10 * 60_000L, f.timeoutMs)
    }

    @Test fun R3_ALERT_suspiciousMapsToLowChannelNeverAlarm() {
        val f = fields(Label.SUSPICIOUS, Source.SMS)
        assertEquals("scam_suspicious", f.channelId)
        assertFalse(f.priorityHigh); assertFalse(f.messageCategory); assertFalse(f.onlyAlertOnce)
        assertEquals(30 * 60_000L, f.timeoutMs)
        assertEquals(listOf("report"), f.actions.map { it.route })
    }

    @Test fun R3_ALERT_inCallScamRecordIsSilent() {
        val f = fields(Label.SCAM, Source.CAPTION)
        assertEquals("scam_suspicious", f.channelId); assertFalse(f.priorityHigh)
    }

    @Test fun R3_ALERT_hindiTitleForHiAndHneEnglishForEn() {
        for (lang in listOf("hi", "hne")) assertTrue(lang, deva.containsMatchIn(fields(Label.SCAM, Source.SMS, lang).title))
        assertEquals("Scam warning", fields(Label.SCAM, Source.SMS, "en").title)
    }

    @Test fun R3_ALERT_textHasNoEngineNameOrConfidencePercent() {
        for (lang in listOf("en", "hi", "hne")) for (l in listOf(Label.SCAM, Label.SUSPICIOUS)) {
            val f = fields(l, Source.SMS, lang)
            val all = f.title + " " + f.text + " " + f.actions.joinToString { it.label }
            assertFalse(all, all.contains("gemma-demo-engine") || all.contains("%") || all.contains("87"))
        }
    }

    @Test fun R3_ALERT_noNotificationWhenPlanDoesNotNotify() {
        val x = v(Label.SUSPICIOUS, Source.CAPTION)
        assertEquals(null, AlertNotificationMapper.fields(AlertPolicy.plan(x, x.source), x))
    }

    @Test fun R3_ALERT_overlayTitleIsLocalisedForHiAndHne() {
        for (lang in listOf("hi", "hne")) for (l in listOf(Label.SCAM, Label.SUSPICIOUS)) {
            val t = L10n.overlayTitle(l, 87, lang)
            assertTrue("$lang/$l: $t", deva.containsMatchIn(t) && !t.contains("This statement"))
        }
        assertEquals("This statement is SCAM · 87%", L10n.overlayTitle(Label.SCAM, 87, "en"))
    }

    @Test fun R3_ALERT_cardStringsLocalisedAndFree_ofEngineAndPercent() {
        for (lang in listOf("en", "hi", "hne")) for (l in listOf(Label.SCAM, Label.SUSPICIOUS)) {
            val all = listOf(L10n.chipText(l, lang), L10n.chipDescription(l, lang), L10n.cardTitle(l, lang), L10n.cardWhy(l, lang),
                L10n.ttsLine(null, lang), L10n.detailsAction(lang)).joinToString(" ")
            assertFalse(all, all.contains("%") || all.contains("Engine", true))
            assertEquals(lang == "en", !deva.containsMatchIn(all))
        }
        assertEquals("⛔ ठगी", L10n.chipText(Label.SCAM, "hi")); assertEquals("⚠ सावधान", L10n.chipText(Label.SUSPICIOUS, "hi"))
        assertEquals("⛔ Scam", L10n.chipText(Label.SCAM, "en")); assertEquals("⚠ Careful", L10n.chipText(Label.SUSPICIOUS, "en"))
        assertEquals("hi-IN", L10n.ttsLanguageTag("hne")); assertEquals("en-IN", L10n.ttsLanguageTag("en"))
        assertEquals(L10n.signalAdvice(InCallSignals.KIND_OTP, "hi"), L10n.ttsLine(InCallSignals.KIND_OTP, "hi"))
    }
}
