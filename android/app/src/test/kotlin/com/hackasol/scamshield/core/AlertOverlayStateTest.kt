package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AlertOverlayStateTest {
    private val S = Label.SCAM
    private val U = Label.SUSPICIOUS

    @Test fun R3_OVERLAY_suspiciousShowsChipOnly() {
        val st = AlertOverlayState()
        val r = st.show(Surface.CHIP, U, preliminary = false)
        assertEquals(OverlayMode.CHIP, r.mode); assertTrue(r.render); assertTrue(r.armChipTimer); assertFalse(r.armCardTimer); assertFalse(r.speak)
    }

    @Test fun R3_OVERLAY_scamAutoExpandsOnceThenCollapsesToChip() {
        val st = AlertOverlayState()
        val a = st.show(Surface.CARD, S, false)
        assertEquals(OverlayMode.CARD, a.mode); assertTrue(a.armCardTimer); assertTrue(a.speak)
        val b = st.timerCardExpired()
        assertEquals(OverlayMode.CHIP, b.mode); assertTrue(b.armChipTimer)
        // Same SCAM level again in the same call: no re-expand (principle 8), chip only, no redraw flash.
        val c = st.show(Surface.CARD, S, false)
        assertEquals(OverlayMode.CHIP, c.mode); assertFalse(c.render); assertFalse(c.speak); assertFalse(c.armCardTimer)
        assertFalse("same-level repeat must not extend the 60 s hide timer", c.armChipTimer)
    }

    @Test fun R3_OVERLAY_steadySuspiciousDoesNotKeepChipAliveButARiseOrNewEventDoes() {
        val st = AlertOverlayState()
        assertTrue(st.show(Surface.CHIP, U, false).armChipTimer)           // first appearance arms
        repeat(5) { assertFalse(st.show(Surface.CHIP, U, false).armChipTimer) }
        assertTrue("a rise re-arms", st.show(Surface.CHIP, S, false).armChipTimer)
        assertFalse(st.show(Surface.CHIP, S, false).armChipTimer)
        assertTrue("a new signal key re-arms", st.show(Surface.CHIP, S, false, "app").armChipTimer)
        assertEquals(OverlayMode.HIDDEN, st.timerChipExpired().mode)
    }

    @Test fun R3_OVERLAY_closingThePromptKeepsDismissedWarningHistory() {
        val st = AlertOverlayState()
        st.show(Surface.CARD, S, false)
        st.dismiss()
        assertEquals(OverlayMode.CARD, st.showPrompt().mode)
        val closed = st.closePrompt()
        assertEquals(OverlayMode.HIDDEN, closed.mode); assertTrue(closed.render)
        val again = st.show(Surface.CARD, S, false)
        assertEquals("dismissed SCAM stays dismissed", OverlayMode.HIDDEN, again.mode); assertFalse(again.speak)
    }

    @Test fun R3_OVERLAY_promptNeverReplacesAWarningAndAVerdictReplacesThePrompt() {
        val st = AlertOverlayState()
        st.show(Surface.CHIP, U, false)
        assertFalse(st.showPrompt().render)
        assertEquals(OverlayMode.CHIP, st.mode)
        val st2 = AlertOverlayState()
        st2.showPrompt()
        val r = st2.show(Surface.CARD, S, false)
        assertEquals(OverlayMode.CARD, r.mode); assertTrue(r.render); assertTrue(r.speak)
        assertEquals("prompt closed by the verdict", OverlayMode.CHIP, st2.timerCardExpired().mode)
    }

    @Test fun R3_OVERLAY_promptCardDoesNotCollapseToChipOnTimerOrTap() {
        val st = AlertOverlayState()
        st.showPrompt()
        assertEquals(OverlayMode.CARD, st.timerCardExpired().mode)
        assertEquals(OverlayMode.CARD, st.tap().mode)
        assertEquals(OverlayMode.HIDDEN, st.dismiss().mode)
    }

    @Test fun R3_OVERLAY_repeatedScamWhileCardOpenDoesNotRestartTheCard() {
        val st = AlertOverlayState()
        st.show(Surface.CARD, S, false)
        val r = st.show(Surface.CARD, S, false)
        assertEquals(OverlayMode.CARD, r.mode); assertFalse(r.armCardTimer); assertFalse(r.speak); assertFalse(r.render)
    }

    @Test fun R3_OVERLAY_escalationFromChipOpensCardOnce() {
        val st = AlertOverlayState()
        st.show(Surface.CHIP, U, false)
        val r = st.show(Surface.CARD, S, false)
        assertEquals(OverlayMode.CARD, r.mode); assertTrue(r.render); assertTrue(r.speak)
    }

    @Test fun R3_OVERLAY_eachDistinctSignalKindGetsItsOwnCard() {
        val st = AlertOverlayState()
        assertTrue(st.show(Surface.CARD, S, false, "otp").speak)
        st.timerCardExpired()
        val second = st.show(Surface.CARD, S, false, "remote")
        assertEquals(OverlayMode.CARD, second.mode); assertTrue(second.speak)
        st.timerCardExpired()
        assertFalse("same kind again does not re-expand", st.show(Surface.CARD, S, false, "remote").speak)
    }

    @Test fun R3_OVERLAY_chipHidesAfterIdleTimer() {
        val st = AlertOverlayState()
        st.show(Surface.CHIP, U, false)
        val r = st.timerChipExpired()
        assertEquals(OverlayMode.HIDDEN, r.mode); assertTrue(r.render)
        assertEquals(OverlayMode.HIDDEN, st.mode)
    }

    @Test fun R3_OVERLAY_staleChipTimerDoesNotHideAnOpenCard() {
        val st = AlertOverlayState()
        st.show(Surface.CHIP, U, false)
        st.show(Surface.CARD, S, false)
        assertEquals(OverlayMode.CARD, st.timerChipExpired().mode)
    }

    @Test fun R3_OVERLAY_callEndedHidesFromAnyModeAndResetsHistory() {
        val st = AlertOverlayState()
        st.show(Surface.CARD, S, false)
        val r = st.callEnded()
        assertEquals(OverlayMode.HIDDEN, r.mode); assertTrue(r.render)
        assertFalse("hidden already: nothing to remove", st.callEnded().render)
        assertTrue("new call, new card", st.show(Surface.CARD, S, false).speak)
    }

    @Test fun R3_OVERLAY_preliminaryNeverCardNeverRedraws() {
        val st = AlertOverlayState()
        val a = st.show(Surface.CARD, S, preliminary = true)
        assertEquals(OverlayMode.CHIP, a.mode); assertFalse(a.speak); assertFalse(a.armCardTimer)
        val again = st.show(Surface.CHIP, S, preliminary = true)
        assertFalse("no re-inflate at the same level", again.render)
        val lower = st.show(Surface.CHIP, U, preliminary = true)
        assertFalse(lower.render); assertEquals(Label.SCAM, st.level)
        // The final verdict still gets its card.
        assertEquals(OverlayMode.CARD, st.show(Surface.CARD, S, false).mode)
    }

    @Test fun R3_OVERLAY_preliminaryDoesNotCollapseOrReplaceAnOpenCard() {
        val st = AlertOverlayState()
        st.show(Surface.CARD, S, false)
        val r = st.show(Surface.CHIP, U, preliminary = true)
        assertEquals(OverlayMode.CARD, r.mode); assertFalse(r.render)
    }

    @Test fun R3_OVERLAY_tapExpandsChipAndCollapsesCard() {
        val st = AlertOverlayState()
        st.show(Surface.CHIP, U, false)
        val open = st.tap()
        assertEquals(OverlayMode.CARD, open.mode); assertTrue(open.armCardTimer); assertFalse("user-opened card is not read aloud", open.speak)
        assertEquals(OverlayMode.CHIP, st.tap().mode)
        assertEquals(OverlayMode.HIDDEN, AlertOverlayState().tap().mode)
    }

    @Test fun R3_OVERLAY_dismissHidesAndStaysQuietUntilRiskRises() {
        val st = AlertOverlayState()
        st.show(Surface.CARD, S, false)
        assertEquals(OverlayMode.HIDDEN, st.dismiss().mode)
        assertEquals("same level after dismiss stays hidden", OverlayMode.HIDDEN, st.show(Surface.CARD, S, false).mode)
        assertEquals("a new signal still shows", OverlayMode.CARD, st.show(Surface.CARD, S, false, "remote").mode)
    }

    @Test fun R3_OVERLAY_lowerRiskNeverReplacesHigher() {
        val st = AlertOverlayState()
        st.show(Surface.CHIP, S, false)
        val r = st.show(Surface.CHIP, U, false)
        assertFalse(r.render); assertEquals(Label.SCAM, st.level)
    }

    @Test fun R3_OVERLAY_surfacesWithoutOverlayAreIgnored() {
        val st = AlertOverlayState()
        for (s in listOf(Surface.NONE, Surface.SILENT_NOTIF, Surface.HEADS_UP)) assertEquals(OverlayMode.HIDDEN, st.show(s, S, false).mode)
    }
}
