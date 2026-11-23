package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AlertPolicyTest {
    private fun verdict(label: Label, source: Source, preliminary: Boolean = false) = Verdict(
        text = "synthetic message", label = label, confidence = 0.9, reason = "test",
        triggers = emptyList(), engine = "rules-only", latencyMs = 0, source = source, preliminary = preliminary,
    )

    private fun plan(label: Label, source: Source) = AlertPolicy.plan(verdict(label, source), source)

    private fun assertPlan(label: Label, source: Source, bubble: Boolean, notify: Boolean, surface: Surface = Surface.of(bubble, notify)) =
        assertEquals("$label/$source", AlertPlan(bubble, notify, bubble || notify, surface), plan(label, source))

    private val live = listOf(Source.CAPTION, Source.SIGNAL)
    private val nonLive = Source.values().filter { it !in live }
    private val messages = listOf(Source.SMS, Source.WHATSAPP, Source.NOTIFICATION)

    @Test fun T1_6_scamCaption() = assertPlan(Label.SCAM, Source.CAPTION, bubble = true, notify = true)

    @Test fun T1_6_scamSms() = assertPlan(Label.SCAM, Source.SMS, bubble = false, notify = true, surface = Surface.HEADS_UP)

    @Test fun T1_6_scamOtherSources() {
        for (s in nonLive) assertPlan(Label.SCAM, s, bubble = false, notify = true, surface = Surface.HEADS_UP)
    }

    @Test fun T1_6_suspiciousCaption() = assertPlan(Label.SUSPICIOUS, Source.CAPTION, bubble = true, notify = false)

    @Test fun T1_6_suspiciousRecording() = assertPlan(Label.SUSPICIOUS, Source.RECORDING, bubble = false, notify = true)

    @Test fun T1_6_suspiciousOtherSources() {
        for (s in nonLive) assertPlan(Label.SUSPICIOUS, s, bubble = false, notify = true)
    }

    @Test fun T1_6_safeAllSources() {
        for (s in Source.values()) assertPlan(Label.SAFE, s, bubble = false, notify = false)
    }

    @Test fun T1_6_planUsesVerdictSourceByDefault() =
        assertEquals(plan(Label.SCAM, Source.WHATSAPP), AlertPolicy.plan(verdict(Label.SCAM, Source.WHATSAPP)))

    // ---- R3 ladder: source x label x callLevel x signalKind x preliminary -> surface, delay, timeout ----

    private fun surface(label: Label, source: Source, callLevel: Label = Label.SAFE, kind: String? = null, prelim: Boolean = false) =
        AlertPolicy.decide(label, source, callLevel, kind, prelim).surface

    @Test fun R3_ALERT_safeIsAlwaysNone() {
        for (s in Source.values()) for (cl in Label.values()) for (k in listOf<String?>(null, InCallSignals.KIND_OTP, InCallSignals.KIND_PAYMENT_APP, InCallSignals.KIND_REMOTE_APP)) for (p in listOf(false, true))
            assertEquals("$s/$cl/$k/$p", Surface.NONE, surface(Label.SAFE, s, cl, k, p))
    }

    @Test fun R3_ALERT_smsLikeSuspiciousIsSilentNotifNeverHeadsUp() {
        for (s in messages) for (cl in Label.values()) {
            assertEquals(Surface.SILENT_NOTIF, surface(Label.SUSPICIOUS, s, cl))
            assertEquals(0L, AlertPolicy.headsUpDelayMs(Label.SUSPICIOUS, s))
        }
        for (s in nonLive) assertNotEquals(Surface.HEADS_UP, surface(Label.SUSPICIOUS, s))
    }

    @Test fun R3_ALERT_smsLikeScamIsDelayedHeadsUp() {
        for (s in messages) {
            val p = AlertPolicy.decide(Label.SCAM, s)
            assertEquals(Surface.HEADS_UP, p.surface)
            assertTrue(p.notify && !p.bubble && p.headsUp)
            assertEquals(6000L, AlertPolicy.headsUpDelayMs(Label.SCAM, s))
            assertEquals(10 * 60_000L, AlertPolicy.notificationTimeoutMs(p))
        }
    }

    @Test fun R3_ALERT_userInitiatedSourcesAreHeadsUpWithNoDelay() {
        for (s in listOf(Source.PASTE, Source.SHARE, Source.RECORDING)) {
            assertEquals(Surface.HEADS_UP, surface(Label.SCAM, s))
            assertEquals("$s", 0L, AlertPolicy.headsUpDelayMs(Label.SCAM, s))
        }
        for (s in Source.values()) if (s !in messages) assertEquals("$s", 0L, AlertPolicy.headsUpDelayMs(Label.SCAM, s))
    }

    @Test fun R3_ALERT_smsNeverChipOrCard() {
        for (s in nonLive) for (l in Label.values()) for (cl in Label.values()) for (p in listOf(false, true)) {
            val sf = surface(l, s, cl, null, p)
            assertTrue("$s/$l/$cl/$p -> $sf", sf != Surface.CHIP && sf != Surface.CARD)
        }
    }

    @Test fun R3_ALERT_inCallSuspiciousCaptionIsChipOnly() {
        for (cl in Label.values()) assertEquals(Surface.CHIP, surface(Label.SUSPICIOUS, Source.CAPTION, cl))
        val p = AlertPolicy.decide(Label.SUSPICIOUS, Source.CAPTION)
        assertTrue(p.bubble && !p.notify)
        assertEquals(0L, AlertPolicy.notificationTimeoutMs(p))
    }

    @Test fun R3_ALERT_inCallScamCaptionIsCardWithSilentRecordNeverHeadsUp() {
        val p = AlertPolicy.decide(Label.SCAM, Source.CAPTION, Label.SCAM)
        assertEquals(Surface.CARD, p.surface)
        assertTrue(p.bubble && p.notify && !p.headsUp)
        assertEquals(0L, AlertPolicy.headsUpDelayMs(Label.SCAM, Source.CAPTION))
        assertEquals(30 * 60_000L, AlertPolicy.notificationTimeoutMs(p))
    }

    @Test fun R3_ALERT_liveSignalsScamAreCardImmediately() {
        for (k in listOf(InCallSignals.KIND_REMOTE_APP, InCallSignals.KIND_SCREEN_SHARE, InCallSignals.KIND_OTP, InCallSignals.KIND_APP_INSTALLED)) {
            assertEquals(k, Surface.CARD, surface(Label.SCAM, Source.SIGNAL, Label.SAFE, k))
            assertEquals(k, Surface.CHIP, surface(Label.SUSPICIOUS, Source.SIGNAL, Label.SAFE, k))
        }
        assertEquals(0L, AlertPolicy.headsUpDelayMs(Label.SCAM, Source.SIGNAL))
    }

    @Test fun R3_ALERT_paymentAppIsSilentNotifUnlessCallAlreadyScam() {
        val k = InCallSignals.KIND_PAYMENT_APP
        for (cl in listOf(Label.SAFE, Label.SUSPICIOUS)) assertEquals(Surface.SILENT_NOTIF, surface(Label.SUSPICIOUS, Source.SIGNAL, cl, k))
        assertEquals(Surface.CARD, surface(Label.SUSPICIOUS, Source.SIGNAL, Label.SCAM, k))
    }

    @Test fun R3_ALERT_preliminaryIsChipAtMostNeverCardOrNotification() {
        for (s in Source.values()) for (l in Label.values()) for (cl in Label.values()) {
            val p = AlertPolicy.decide(l, s, cl, null, preliminary = true)
            assertFalse("$s/$l", p.notify)
            assertTrue(p.surface == Surface.NONE || p.surface == Surface.CHIP)
            if (l != Label.SAFE && s in live) assertEquals(Surface.CHIP, p.surface)
        }
    }

    @Test fun R3_ALERT_verdictPreliminaryFlagReachesThePlan() =
        assertEquals(Surface.CHIP, AlertPolicy.plan(verdict(Label.SCAM, Source.CAPTION, preliminary = true), null, Label.SCAM).surface)

    @Test fun R3_ALERT_timeoutsAndDelayConstants() {
        assertEquals(6000L, AlertPolicy.HEADS_UP_DELAY_MS)
        assertEquals(30 * 60_000L, AlertPolicy.notificationTimeoutMs(AlertPlan.of(Surface.SILENT_NOTIF)))
        assertEquals(0L, AlertPolicy.notificationTimeoutMs(AlertPlan.of(Surface.NONE)))
        assertEquals(10_000L, AlertPolicy.CARD_MS)
        assertEquals(60_000L, AlertPolicy.CHIP_IDLE_MS)
    }

    @Test fun R3_ALERT_booleansStayDerivableFromSurface() {
        for (s in Surface.values()) {
            val p = AlertPlan.of(s)
            assertEquals(s == Surface.CHIP || s == Surface.CARD, p.bubble)
            assertEquals(p.bubble || p.notify, p.reportAction)
        }
    }
}
