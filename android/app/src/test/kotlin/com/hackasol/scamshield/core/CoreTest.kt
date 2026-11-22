package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StatementSegmenterTest {
    @Test fun growingCaptionEmitsOnceWhenStable() {
        val s = StatementSegmenter()
        assertTrue(s.onSnapshot("Hello sir", 0).isEmpty())
        assertTrue(s.onSnapshot("Hello sir I am calling", 300).isEmpty())
        assertTrue(s.onSnapshot("Hello sir I am calling from SBI", 600).isEmpty())
        assertTrue(s.onTick(1000).isEmpty())
        assertEquals(listOf("Hello sir I am calling from SBI"), s.onTick(1900))
        assertTrue(s.onTick(4000).isEmpty())               // no duplicate
    }

    @Test fun terminatorSplitsImmediately() {
        val s = StatementSegmenter()
        val out = s.onSnapshot("Your KYC is pending. Please share the OTP", 0)
        assertEquals(listOf("Your KYC is pending."), out)
        assertEquals(listOf("Please share the OTP"), s.onTick(1300))
    }

    @Test fun scrollingCaptionOnlyEmitsNewWords() {
        val s = StatementSegmenter()
        s.onSnapshot("this is customs department", 0)
        assertEquals(listOf("this is customs department"), s.onTick(1300))
        // Old words still visible, new words appended
        s.onSnapshot("this is customs department your parcel has drugs", 1500)
        assertEquals(listOf("your parcel has drugs"), s.onTick(2800))
        // Old words scrolled off the top
        s.onSnapshot("parcel has drugs you will be arrested", 3000)
        assertEquals(listOf("you will be arrested"), s.onTick(4300))
    }

    @Test fun longRunIsChunked() {
        val s = StatementSegmenter(maxWords = 5)
        val out = s.onSnapshot("one two three four five six seven", 0)
        assertEquals(listOf("one two three four five"), out)
    }

    @Test fun hindiDandaTerminates() {
        val s = StatementSegmenter()
        val out = s.onSnapshot("मैं सीबीआई से बोल रहा हूं। आपका पार्सल", 0)
        assertEquals(listOf("मैं सीबीआई से बोल रहा हूं।"), out)
    }
}

class RuleScorerTest {
    @Test fun otpShareIsScam() {
        val r = RuleScorer.score("Sir aapke phone pe OTP aaya hoga, woh bata dijiye")
        assertEquals(Label.SCAM, r.label)
        assertTrue(r.triggers.isNotEmpty())
    }

    @Test fun digitalArrestHindiIsScam() {
        assertEquals(Label.SCAM, RuleScorer.score("आप डिजिटल अरेस्ट में हैं, किसी को मत बताना").label)
    }

    @Test fun anydeskIsScam() {
        assertEquals(Label.SCAM, RuleScorer.score("please install AnyDesk so I can help you").label)
    }

    @Test fun kycIsSuspicious() {
        assertEquals(Label.SUSPICIOUS, RuleScorer.score("Main bank se bol raha hoon, aapka KYC pending hai").label)
    }

    @Test fun normalTalkIsSafe() {
        assertEquals(Label.SAFE, RuleScorer.score("Beta khana kha liya? Kal shaam ko milte hain").label)
        assertEquals(Label.SAFE, RuleScorer.score("I edited the document yesterday").label)
    }
}

class LlmOutputParserTest {
    @Test fun cleanJson() {
        val r = LlmOutputParser.parse("""{"label":"SCAM","confidence":0.93,"reason":"Asks OTP"}""")!!
        assertEquals(Label.SCAM, r.label); assertEquals(0.93, r.confidence, 1e-9); assertEquals("Asks OTP", r.reason)
    }

    @Test fun fencedAndChatty() {
        val r = LlmOutputParser.parse("Sure!\n```json\n{ \"label\": \"suspicious\", \"confidence\": 70%, \"reason\": \"KYC claim\" }\n```")!!
        assertEquals(Label.SUSPICIOUS, r.label); assertEquals(0.70, r.confidence, 1e-9)
    }

    @Test fun bareLabelDefaultsConfidence() {
        val r = LlmOutputParser.parse("SAFE - normal chat")!!
        assertEquals(Label.SAFE, r.label); assertEquals(0.6, r.confidence, 1e-9)
    }

    @Test fun garbageIsNull() { assertNull(LlmOutputParser.parse("I cannot help with that")) }

    @Test fun confidenceClamped() {
        assertNotNull(LlmOutputParser.parse("""{"label":"SCAM","confidence":97}"""))
        assertEquals(0.97, LlmOutputParser.parse("""{"label":"SCAM","confidence":97}""")!!.confidence, 1e-9)
    }
}

class CallRiskTrackerTest {
    private fun v(l: Label, c: Double) = Verdict("x", l, c, "", emptyList(), "t", 0, Source.CAPTION)

    @Test fun singleModerateScamShownAsSuspicious() {
        val t = CallRiskTracker()
        assertEquals(Label.SUSPICIOUS, t.record(v(Label.SCAM, 0.8), 0))
        assertEquals(Label.SCAM, t.record(v(Label.SCAM, 0.8), 1000))
    }

    @Test fun highConfidenceScamGoesRedImmediately() {
        assertEquals(Label.SCAM, CallRiskTracker().record(v(Label.SCAM, 0.95), 0))
    }

    @Test fun riskExpires() {
        val t = CallRiskTracker(resetAfterMs = 1000)
        t.record(v(Label.SCAM, 0.95), 0)
        t.maybeExpire(5000)
        assertEquals(Label.SAFE, t.level())
    }
}

class InCallSignalsTest {
    @Test fun otpSmsDetected() {
        val s = InCallSignals.fromNotification("AX-HDFCBK 482913 is your OTP for txn of Rs 49,999. Do not share.")
        assertEquals(Label.SCAM, s!!.label)
    }
    @Test fun hindiOtpDetected() { assertNotNull(InCallSignals.fromNotification("आपका ओटीपी 5521 है")) }
    @Test fun normalMessageIgnored() { assertNull(InCallSignals.fromNotification("Mom: dinner at 8?")) }
    @Test fun anydeskIsScam() { assertEquals(Label.SCAM, InCallSignals.fromForegroundApp("com.anydesk.anydeskandroid")!!.label) }
    @Test fun upiIsSuspicious() { assertEquals(Label.SUSPICIOUS, InCallSignals.fromForegroundApp("com.phonepe.app")!!.label) }
    @Test fun otherAppIgnored() { assertNull(InCallSignals.fromForegroundApp("com.whatsapp")) }
}
