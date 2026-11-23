package com.hackasol.scamshield

import com.hackasol.scamshield.core.AlertNotificationMapper
import com.hackasol.scamshield.core.InCallSignals
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.NotificationFields
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.Verdict
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    @Test fun R3_ALERT_twoDelayedScamsWithinSixSecondsPostOnlyTheNewest() {
        val d = dispatcher()
        d.dispatch(v(Label.SCAM, Source.SMS).copy(triggers = listOf("first")), Label.SCAM, Label.SCAM, 0.9)
        d.dispatch(v(Label.SCAM, Source.WHATSAPP).copy(triggers = listOf("second")), Label.SCAM, Label.SCAM, 0.9)
        sched.runAll()
        assertEquals(1, posted.size)
        assertTrue(posted.single().text.contains("second"))
    }

    @Test fun R3_ALERT_staleDelayedScamNeverOverwritesNewerImmediatePaste() {
        val d = dispatcher()
        d.dispatch(v(Label.SCAM, Source.SMS), Label.SCAM, Label.SCAM, 0.9)
        d.dispatch(v(Label.SCAM, Source.PASTE).copy(triggers = listOf("paste")), Label.SCAM, Label.SCAM, 0.9)
        assertEquals(1, posted.size)
        sched.runAll()
        assertEquals("the delayed SMS post must not fire after the paste post", 1, posted.size)
        assertTrue(posted.single().text.contains("paste"))
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

    @Test fun R3_ALERT_paymentAppSilentUnlessCallScam() {
        val d = dispatcher()
        d.dispatch(v(Label.SUSPICIOUS, Source.SIGNAL), Label.SUSPICIOUS, Label.SUSPICIOUS, 0.5, InCallSignals.KIND_PAYMENT_APP)
        assertTrue(sink.calls.isEmpty()); assertEquals(AlertNotificationMapper.CHANNEL_ID_SILENT, posted.single().channelId)
        d.dispatch(v(Label.SUSPICIOUS, Source.SIGNAL), Label.SUSPICIOUS, Label.SCAM, 0.9, InCallSignals.KIND_PAYMENT_APP)
        assertEquals(1, sink.calls.size)
    }

    @Test fun R3_ALERT_safeDoesNothing() {
        for (s in Source.values()) dispatcher().dispatch(v(Label.SAFE, s), Label.SAFE, Label.SAFE, 0.1)
        assertTrue(sink.calls.isEmpty() && posted.isEmpty() && sched.queue.isEmpty())
    }

    @Test fun R3_ALERT_demoPrefixKeptOnNotificationTitle() {
        dispatcher("[DEMO] ").dispatch(v(Label.SUSPICIOUS, Source.SMS), Label.SUSPICIOUS, Label.SUSPICIOUS, 0.5)
        assertTrue(posted.single().title.startsWith("[DEMO] "))
    }
}
