package com.hackasol.scamshield

import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.Verdict
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DemoBubbleTest {
    private class FakeSink : BubbleSink {
        val prefixes = mutableListOf<String>()
        override fun showVerdict(v: Verdict, shown: Label, callLevel: Label, callRisk: Double, signalKind: String?, titlePrefix: String) {
            prefixes += titlePrefix
        }
    }

    private fun v(source: Source) = Verdict("synthetic", Label.SCAM, 0.9, "test", listOf("OTP"), "rules-only", 0, source)

    private fun show(sink: BubbleSink?, source: Source, shown: Label = Label.SCAM) =
        AlertDispatcher.showBubble(sink, v(source), shown, shown, 0.9, "[DEMO] ")

    @Test fun DEMO_bubble_shownForLiveStepWhenServiceRunning() {
        val sink = FakeSink()
        assertTrue(show(sink, Source.CAPTION))
        assertTrue(show(sink, Source.SIGNAL))
        assertEquals(listOf("[DEMO] ", "[DEMO] "), sink.prefixes)
    }

    @Test fun DEMO_bubble_notificationOnlyWhenServiceMissing() {
        assertFalse(show(null, Source.CAPTION))
    }

    @Test fun DEMO_bubble_respectsAlertPolicy() {
        val sink = FakeSink()
        assertFalse(show(sink, Source.SMS))                    // not live: notification only
        assertFalse(show(sink, Source.CAPTION, Label.SAFE))    // safe: nothing
        assertTrue(sink.prefixes.isEmpty())
    }
}
