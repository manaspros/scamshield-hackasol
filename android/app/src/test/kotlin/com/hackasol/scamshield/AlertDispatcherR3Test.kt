package com.hackasol.scamshield

import com.hackasol.scamshield.core.AlertNotificationMapper
import com.hackasol.scamshield.core.InCallSignals
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.NotificationFields
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.Verdict
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AlertDispatcherR3Test {
    private class FakeSink : BubbleSink {
        val calls = mutableListOf<Pair<Label, String?>>()
        override fun showVerdict(v: Verdict, shown: Label, callLevel: Label, callRisk: Double, signalKind: String?, titlePrefix: String) {
            calls += shown to signalKind
        }
    }

    private class FakeScheduler : Scheduler {
        val queue = mutableListOf<Pair<Long, Runnable>>()
        override fun postDelayed(delayMs: Long, r: Runnable) { queue += delayMs to r }
        fun runAll() { queue.toList().also { queue.clear() }.forEach { it.second.run() } }
    }

    private val posted = mutableListOf<NotificationFields>()
    private val sink = FakeSink()
    private val sched = FakeScheduler()
    private fun dispatcher(prefix: String = "", lang: String = "hi") =
        AlertDispatcher(sink, { posted += it }, prefix, sched, { lang })

    private fun v(label: Label, source: Source, prelim: Boolean = false) =
        Verdict("synthetic message", label, 0.9, "test", listOf("OTP bata dijiye"), "rules-only", 0, source, preliminary = prelim)

    @Test fun R3_ALERT_smsScamNotPostedBeforeSixSecondsThenPostedOnce() {
        val d = dispatcher()
        d.dispatch(v(Label.SCAM, Source.SMS), Label.SCAM, Label.SCAM, 0.9)
        assertTrue("nothing posted yet", posted.isEmpty())
        assertEquals(listOf(6000L), sched.queue.map { it.first })
        sched.runAll()
        assertEquals(1, posted.size)
        val f = posted.single()
        assertEquals(AlertNotificationMapper.CHANNEL_ID_ALERTS, f.channelId)
        assertTrue(f.priorityHigh); assertTrue(f.onlyAlertOnce)
        assertEquals(10 * 60_000L, f.timeoutMs)
        assertEquals(AlertNotificationMapper.GROUP_KEY, f.group)
        assertTrue("SMS never draws an overlay", sink.calls.isEmpty())
    }

    // Was ...PostOnlyTheNewest (asserted the first alert was dropped = the missed-SMS-alert bug). Now both are posted, newest last.
    @Test fun R3_ALERT_twoDelayedScamsWithinSixSecondsPostBoth() {
        val d = dispatcher()
        d.dispatch(v(Label.SCAM, Source.SMS).copy(triggers = listOf("first")), Label.SCAM, Label.SCAM, 0.9)
        d.dispatch(v(Label.SCAM, Source.WHATSAPP).copy(triggers = listOf("second")), Label.SCAM, Label.SCAM, 0.9)
        assertEquals("the older one posts as soon as a newer heads-up arrives", 1, posted.size)
        assertTrue(posted[0].text.contains("first"))
        sched.runAll()
        assertEquals(2, posted.size)
        assertTrue(posted[1].text.contains("second"))
    }

    // Was ...staleDelayedScamNeverOverwritesNewerImmediatePaste (the delayed SMS was dropped). Now it posts first, the paste stays on top.
    @Test fun R3_ALERT_delayedScamPostsBeforeNewerImmediatePasteAndNeverAfter() {
        val d = dispatcher()
        d.dispatch(v(Label.SCAM, Source.SMS).copy(triggers = listOf("sms")), Label.SCAM, Label.SCAM, 0.9)
        d.dispatch(v(Label.SCAM, Source.PASTE).copy(triggers = listOf("paste")), Label.SCAM, Label.SCAM, 0.9)
        assertEquals(2, posted.size)
        sched.runAll()
        assertEquals("the delayed SMS runnable must not double-post", 2, posted.size)
        assertTrue(posted[0].text.contains("sms")); assertTrue(posted[1].text.contains("paste"))
    }

    @Test fun flushPendingPostsNowAndScheduledRunnableDoesNotDoublePost() {
        val d = dispatcher()
        d.dispatch(v(Label.SCAM, Source.SMS), Label.SCAM, Label.SCAM, 0.9)
        assertTrue(posted.isEmpty())
        d.flushPending()
        assertEquals(1, posted.size)
        sched.runAll()
        assertEquals(1, posted.size)
        d.flushPending()
        assertEquals("nothing pending: no-op", 1, posted.size)
    }

    @Test fun idOffsetKeepsDemoIdsApartFromRealOnes() {
        val demo = AlertDispatcher(sink, { posted += it }, "[DEMO] ", sched, { "hi" }, 100)
        demo.dispatch(v(Label.SCAM, Source.PASTE), Label.SCAM, Label.SCAM, 0.9)
        demo.dispatch(v(Label.SUSPICIOUS, Source.SMS), Label.SUSPICIOUS, Label.SUSPICIOUS, 0.5)
        assertEquals(listOf(7101, 7103), posted.map { it.notificationId })
    }

    @Test fun R3_ALERT_cancelPendingDropsDelayedPost() {
        val d = dispatcher()
        d.dispatch(v(Label.SCAM, Source.SMS), Label.SCAM, Label.SCAM, 0.9)
        d.cancelPending()
        sched.runAll()
        assertTrue(posted.isEmpty())
    }

    @Test fun R3_ALERT_silentSuspiciousDoesNotCancelPendingScam() {
        val d = dispatcher()
        d.dispatch(v(Label.SCAM, Source.SMS), Label.SCAM, Label.SCAM, 0.9)
        d.dispatch(v(Label.SUSPICIOUS, Source.SMS), Label.SUSPICIOUS, Label.SUSPICIOUS, 0.5)
        sched.runAll()
        assertEquals(listOf(AlertNotificationMapper.CHANNEL_ID_SILENT, AlertNotificationMapper.CHANNEL_ID_ALERTS), posted.map { it.channelId })
    }

    @Test fun R3_ALERT_suspiciousDoesNotReplaceScamInShade() {
        val d = dispatcher()
        d.dispatch(v(Label.SCAM, Source.SMS), Label.SCAM, Label.SCAM, 0.9)
        sched.runAll()   // the 6000 ms heads-up fires
        d.dispatch(v(Label.SUSPICIOUS, Source.SMS), Label.SUSPICIOUS, Label.SUSPICIOUS, 0.5)
        assertEquals(2, posted.size)
        val (scam, susp) = posted
        assertNotEquals(scam.notificationId, susp.notificationId)
        assertEquals(7001, scam.notificationId)
        assertEquals(AlertNotificationMapper.CHANNEL_ID_SILENT, susp.channelId)
    }

    @Test fun R3_ALERT_pasteScamHeadsUpIsImmediate() {
        dispatcher().dispatch(v(Label.SCAM, Source.PASTE), Label.SCAM, Label.SCAM, 0.9)
        assertTrue(sched.queue.isEmpty())
        assertEquals(AlertNotificationMapper.CHANNEL_ID_ALERTS, posted.single().channelId)
    }

    @Test fun R3_ALERT_smsSuspiciousIsSilentAndImmediate() {
        dispatcher().dispatch(v(Label.SUSPICIOUS, Source.SMS), Label.SUSPICIOUS, Label.SUSPICIOUS, 0.5)
        assertTrue(sched.queue.isEmpty())
        val f = posted.single()
        assertEquals(AlertNotificationMapper.CHANNEL_ID_SILENT, f.channelId)
        assertFalse(f.priorityHigh); assertFalse(f.messageCategory); assertFalse(f.onlyAlertOnce)
        assertEquals(30 * 60_000L, f.timeoutMs)
    }

    @Test fun R3_ALERT_signalScamCardIsImmediateWithSilentRecord() {
        dispatcher().dispatch(v(Label.SCAM, Source.SIGNAL), Label.SCAM, Label.SCAM, 0.9, InCallSignals.KIND_REMOTE_APP)
        assertEquals(listOf(Label.SCAM to InCallSignals.KIND_REMOTE_APP), sink.calls)
        assertTrue(sched.queue.isEmpty())
        val f = posted.single()
        assertEquals("in-call record is never a heads-up", AlertNotificationMapper.CHANNEL_ID_SILENT, f.channelId)
        assertFalse(f.priorityHigh)
    }

    @Test fun R3_ALERT_captionSuspiciousIsChipOnly() {
        dispatcher().dispatch(v(Label.SUSPICIOUS, Source.CAPTION), Label.SUSPICIOUS, Label.SUSPICIOUS, 0.5)
        assertEquals(1, sink.calls.size); assertTrue(posted.isEmpty() && sched.queue.isEmpty())
    }

    @Test fun R3_ALERT_preliminaryNeverNotifiesAndNeverSchedules() {
        for (s in Source.values()) for (l in listOf(Label.SUSPICIOUS, Label.SCAM))
            dispatcher().dispatch(v(l, s, prelim = true), l, l, 0.9)
        sched.runAll()
        assertTrue(posted.isEmpty())
        assertTrue("only live sources get a chip", sink.calls.size == 4)
    }

    @Test fun R3_ALERT_paymentAppChipUnlessCallScam() {
        val d = dispatcher()
        d.dispatch(v(Label.SUSPICIOUS, Source.SIGNAL), Label.SUSPICIOUS, Label.SUSPICIOUS, 0.5, InCallSignals.KIND_PAYMENT_APP)
        assertEquals(1, sink.calls.size); assertTrue(posted.isEmpty())
        d.dispatch(v(Label.SUSPICIOUS, Source.SIGNAL), Label.SUSPICIOUS, Label.SCAM, 0.9, InCallSignals.KIND_PAYMENT_APP)
        assertEquals(2, sink.calls.size)
    }

    @Test fun R3_ALERT_safeDoesNothing() {
        for (s in Source.values()) dispatcher().dispatch(v(Label.SAFE, s), Label.SAFE, Label.SAFE, 0.1)
        assertTrue(sink.calls.isEmpty() && posted.isEmpty() && sched.queue.isEmpty())
    }

    @Test fun R3_ALERT_demoPrefixKeptOnNotificationTitle() {
        dispatcher("[DEMO] ").dispatch(v(Label.SUSPICIOUS, Source.SMS), Label.SUSPICIOUS, Label.SUSPICIOUS, 0.5)
        assertTrue(posted.single().title.startsWith("[DEMO] "))
    }

    // ---- no overlay to draw on: a live warning must still be seen ----

    @Test fun R3_ALERT_liveScamWithoutOverlayIsHeadsUp() {
        // Listener-only fallback (accessibility service off): no sink at all.
        val d = AlertDispatcher(null, { posted += it }, "", sched, { "en" })
        val otp = InCallSignals.toVerdict(InCallSignals.fromNotification("Your OTP is 482913")!!)
        d.dispatch(otp, Label.SCAM, Label.SCAM, 0.93, InCallSignals.KIND_OTP)
        val f = posted.single()
        assertEquals(AlertNotificationMapper.CHANNEL_ID_ALERTS, f.channelId)
        assertTrue(f.priorityHigh)
        assertTrue("asks, and names what happened", f.text.startsWith("Are you sure?") && f.title.contains("OTP"))
        assertFalse("never the code", f.title.contains("482913") || f.text.contains("482913"))
    }

    @Test fun R3_ALERT_overlaySwitchedOffFallsBackToNotification() {
        val d = AlertDispatcher(sink, { posted += it }, "", sched, { "en" }, overlayOn = { false })
        d.dispatch(v(Label.SCAM, Source.CAPTION), Label.SCAM, Label.SCAM, 0.9)
        assertEquals(AlertNotificationMapper.CHANNEL_ID_ALERTS, posted.single().channelId)
        d.dispatch(v(Label.SUSPICIOUS, Source.CAPTION), Label.SUSPICIOUS, Label.SUSPICIOUS, 0.5)
        assertEquals(AlertNotificationMapper.CHANNEL_ID_SILENT, posted.last().channelId)
        // Preliminary (rules-only, model pending) still never notifies.
        d.dispatch(v(Label.SCAM, Source.CAPTION, prelim = true), Label.SUSPICIOUS, Label.SUSPICIOUS, 0.5)
        assertEquals(2, posted.size)
    }
}

