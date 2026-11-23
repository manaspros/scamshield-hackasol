package com.hackasol.scamshield.qa

import com.hackasol.scamshield.core.*
import org.junit.Assert.*
import org.junit.Test

class QACallPipelineTest {
    // ---------- PcmResampler ----------
    private fun resample(inRate: Int, ch: Int, pcm: ShortArray, chunk: Int = 8000): List<ShortArray> {
        val out = mutableListOf<ShortArray>()
        val r = PcmResampler(inRate, ch, chunk) { out += it }
        r.push(pcm); r.flush(); return out
    }
    private fun flat(l: List<ShortArray>) = l.flatMap { it.toList() }

    @Test fun `QA_pcm_16kMonoIsExactPassthrough`() {
        val x = ShortArray(1000) { (it * 37 - 15000).toShort() }
        assertEquals(x.toList(), flat(resample(16000, 1, x)))
    }

    @Test fun `QA_pcm_constantSignalStaysConstantAt44k1Stereo`() {
        val x = ShortArray(44_100 * 2) { 1000 }
        val o = flat(resample(44_100, 2, x)); assertTrue(o.size in 15_999..16_001); assertTrue(o.all { it.toInt() == 1000 })
    }

    @Test fun `QA_pcm_oppositePhaseStereoDownmixesToSilence`() {
        val x = ShortArray(4000) { if (it % 2 == 0) 10000 else -10000 }
        assertTrue(flat(resample(16000, 2, x)).all { it.toInt() == 0 })
    }

    @Test fun `QA_pcm_upsample8kInterpolatesMidpoints`() {
        val o = flat(resample(8000, 1, shortArrayOf(0, 1000, 2000, 3000)))
        assertEquals(0, o[0].toInt()); assertEquals(500, o[1].toInt()); assertEquals(1000, o[2].toInt())
        assertTrue(o.size in 7..8)
    }

    @Test fun `QA_pcm_extremesNeverOverflow`() {
        val x = ShortArray(4000) { if (it % 2 == 0) Short.MAX_VALUE else Short.MIN_VALUE }
        val o = flat(resample(48_000, 1, x)); assertTrue(o.isNotEmpty())   // coerced; no exception
        assertTrue(o.all { it in Short.MIN_VALUE..Short.MAX_VALUE })
    }

    @Test fun `QA_pcm_chunkingSplitPushesEqualSinglePush`() {
        val x = ShortArray(48_000 * 2) { ((it * 7919) % 20000 - 10000).toShort() }
        val whole = flat(resample(48_000, 2, x, 1600))
        val parts = mutableListOf<ShortArray>(); val r = PcmResampler(48_000, 2, 1600) { parts += it }
        var i = 0; for (n in listOf(2, 1000, 6, 33_333 * 2, 2)) { val e = minOf(i + n, x.size); r.push(x.copyOfRange(i, e)); i = e }
        r.push(x.copyOfRange(i, x.size)); r.flush()
        assertEquals(whole, flat(parts))
    }

    @Test fun `QA_pcm_allChunksFullExceptLast`() {
        val c = resample(16000, 1, ShortArray(2500), 1000)
        assertEquals(listOf(1000, 1000, 500), c.map { it.size })
    }

    @Test fun `QA_pcm_emptyInputEmitsNothingAndTrailingPartialFrameIgnored`() {
        assertTrue(resample(16000, 1, ShortArray(0)).isEmpty())
        assertEquals(1, flat(resample(16000, 2, shortArrayOf(5, 5, 9))).size)
    }

    @Test fun `QA_pcm_invalidParametersRejected`() {
        for (f in listOf({ PcmResampler(0, 1) {} }, { PcmResampler(16000, 0) {} }, { PcmResampler(16000, 1, 0) {} })) {
            try { f(); fail("expected IllegalArgumentException") } catch (_: IllegalArgumentException) {}
        }
    }

    @Test fun `QA_pcm_flushTwiceDoesNotDuplicate`() {
        val out = mutableListOf<ShortArray>(); val r = PcmResampler(16000, 1, 100) { out += it }
        r.push(ShortArray(50)); r.flush(); r.flush(); assertEquals(1, out.size)
    }

    // ---------- StatementSegmenter ----------
    @Test fun `QA_segmenter_blankSnapshotsEmitNothing`() {
        val s = StatementSegmenter()
        assertTrue(s.onSnapshot("", 0).isEmpty()); assertTrue(s.onSnapshot("   \n ", 5000).isEmpty()); assertTrue(s.onTick(99_999).isEmpty())
    }

    @Test fun `QA_segmenter_stableTimeoutExactlyAt1200`() {
        val s = StatementSegmenter()
        assertTrue(s.onSnapshot("aapka khata band ho jayega", 0).isEmpty())
        assertTrue(s.onTick(1199).isEmpty())
        assertEquals(listOf("aapka khata band ho jayega"), s.onTick(1200))
    }

    @Test fun `QA_segmenter_terminatedTimeoutExactlyAt500`() {
        val s = StatementSegmenter()
        s.onSnapshot("aapka khata band ho jayega.", 0)
        assertTrue(s.onTick(499).isEmpty()); assertEquals(1, s.onTick(500).size)
    }

    @Test fun `QA_segmenter_dandaAndDoubleDandaTerminate`() {
        val s = StatementSegmenter()
        val out = s.onSnapshot("आपका खाता बंद हो जाएगा। ओटीपी बताइए॥ ठीक है", 0)
        assertEquals(listOf("आपका खाता बंद हो जाएगा।", "ओटीपी बताइए॥"), out)
    }

    @Test fun `QA_segmenter_maxWordsBoundary`() {
        val w24 = (1..24).joinToString(" ") { "w$it" }; val w25 = (1..25).joinToString(" ") { "w$it" }
        assertTrue(StatementSegmenter().onSnapshot(w24, 0).isEmpty())
        assertEquals(listOf(w25), StatementSegmenter().onSnapshot(w25, 0))
    }

    @Test(timeout = 20_000) fun `QA_segmenter_veryLongSnapshotChunksAtMax25Words`() {
        val s = StatementSegmenter(); val out = s.onSnapshot((1..10_000).joinToString(" ") { "w$it" }, 0) + s.onTick(10_000)
        assertTrue(out.all { it.split(" ").size <= 25 }); assertEquals(10_000, out.sumOf { it.split(" ").size })
    }

    @Test fun `QA_segmenter_punctuationOrCaseRewriteDoesNotReemit`() {
        val s = StatementSegmenter()
        s.onSnapshot("please share your otp code now", 0)
        assertEquals(1, s.onTick(1200).size)
        assertTrue(s.onSnapshot("Please share your OTP code now.", 1300).isEmpty())
        assertTrue(s.onTick(5000).isEmpty())
    }

    @Test fun `QA_segmenter_resetForgetsHistory`() {
        val s = StatementSegmenter()
        s.onSnapshot("otp bata do abhi", 0); s.onTick(1200); s.reset()
        s.onSnapshot("otp bata do abhi", 5000)
        assertEquals(listOf("otp bata do abhi"), s.onTick(6200))
    }

    @Test fun `QA_segmenter_tokenizeAndNormalize`() {
        assertEquals(listOf("a", "b"), StatementSegmenter.tokenize("  a \t\n b  "))
        assertEquals("ओटीपी", StatementSegmenter.normalize("“ओटीपी”।"))
        assertTrue(StatementSegmenter.isTerminated("हैं।")); assertFalse(StatementSegmenter.isTerminated(""))
    }

    // ---------- CallRiskTracker ----------
    @Test fun `QA_tracker_verdictRiskCorners`() {
        assertEquals(0.0, qaVerdict(Label.SAFE, 1.0).risk, 1e-9); assertEquals(0.3, qaVerdict(Label.SAFE, 0.0).risk, 1e-9)
        assertEquals(0.4, qaVerdict(Label.SUSPICIOUS, 0.0).risk, 1e-9); assertEquals(0.6, qaVerdict(Label.SCAM, 0.0).risk, 1e-9)
        assertEquals(1.0, qaVerdict(Label.SCAM, 1.0).risk, 1e-9)
    }

    @Test fun `QA_tracker_levelThresholds`() {
        val t = CallRiskTracker(); t.record(qaVerdict(Label.SAFE, 0.0), 0); assertEquals(Label.SAFE, t.level())
        assertEquals(CallRiskTracker.PRIOR, t.risk, 1e-9)   // SAFE never goes below the prior
        val s = CallRiskTracker(); s.record(qaVerdict(Label.SUSPICIOUS, 0.7), 0); assertEquals(Label.SUSPICIOUS, s.level())
        val c = CallRiskTracker(); c.record(qaVerdict(Label.SCAM, 0.7), 0); assertEquals(Label.SCAM, c.level())
        val w = CallRiskTracker(); w.record(qaVerdict(Label.SCAM, 0.0), 0); assertEquals(Label.SUSPICIOUS, w.level())
    }

    @Test fun `QA_tracker_scamShownRedOnlyWhenCallIsScam`() {
        for (c in listOf(0.0, 0.2, 0.4, 0.6, 0.9, 1.0)) {
            val t = CallRiskTracker(); val shown = t.record(qaVerdict(Label.SCAM, c), 0)
            assertEquals(if (t.level() == Label.SCAM) Label.SCAM else Label.SUSPICIOUS, shown)
        }
    }

    @Test fun `QA_tracker_scamCallStaysRedThroughOneSafeLine`() {
        val t = CallRiskTracker(); t.record(qaVerdict(Label.SCAM, 0.95), 0); t.record(qaVerdict(Label.SAFE, 0.9), 1)
        assertEquals(Label.SCAM, t.level())
        assertEquals(Label.SCAM, t.record(qaVerdict(Label.SCAM, 0.5), 2))
    }

    @Test fun `QA_tracker_fewSafeLinesDoNotClearAScam`() {
        val t = CallRiskTracker(); t.record(qaVerdict(Label.SCAM, 1.0), 0)
        for (i in 1..3) t.record(qaVerdict(Label.SAFE, 1.0), i.toLong())
        assertEquals(Label.SCAM, t.level())
    }

    @Test fun `QA_tracker_longSafeTailBringsRiskBackDown`() {
        val t = CallRiskTracker(); t.record(qaVerdict(Label.SCAM, 1.0), 0)
        var last = t.risk
        for (i in 1..30) { t.record(qaVerdict(Label.SAFE, 1.0), i.toLong()); assertTrue(t.risk <= last); last = t.risk }
        assertEquals(Label.SAFE, t.level())
    }

    @Test fun `QA_tracker_expiryBoundary`() {
        val t = CallRiskTracker(30_000); t.record(qaVerdict(Label.SCAM, 1.0), 0)
        t.maybeExpire(30_000); assertEquals(1, t.statements)
        t.maybeExpire(30_001); assertEquals(0, t.statements); assertEquals(0.0, t.risk, 0.0)
    }

    @Test fun `QA_tracker_expiredCallStartsFreshOnNextRecord`() {
        val t = CallRiskTracker(1000); t.record(qaVerdict(Label.SCAM, 1.0), 0)
        t.record(qaVerdict(Label.SAFE, 1.0), 5000)
        assertEquals(1, t.statements); assertEquals(Label.SAFE, t.level())
    }

    @Test fun `QA_tracker_riskStaysInUnitIntervalOverRandomSequences`() {
        val rnd = java.util.Random(42); val t = CallRiskTracker()
        for (i in 0 until 2000) {
            t.record(qaVerdict(Label.values()[rnd.nextInt(3)], rnd.nextDouble()), i.toLong())
            assertTrue(t.risk in 0.0..1.0)
        }
    }

    @Test fun `QA_tracker_resetOnFreshTrackerIsHarmless`() { val t = CallRiskTracker(); t.reset(); assertEquals(0.0, t.risk, 0.0); assertEquals(Label.SAFE, t.level()) }

    // ---------- RecordingPipeline ----------
    private val rulesClassify: (String, Source) -> Verdict = { text, src ->
        val r = RuleScorer.score(text); val f = Fusion.fuse(null, r, RuleScorer.scamType(text))
        Verdict(text, f.label, f.confidence, f.reason, f.triggers, f.engine, 0, src, scamType = f.scamType)
    }

    @Test fun `QA_recording_noSegmentsIsSafeAndEmpty`() {
        val rep = RecordingPipeline(rulesClassify).run(emptyList())
        assertEquals(Label.SAFE, rep.overall); assertEquals(0.0, rep.risk, 0.0); assertTrue(rep.perStatement.isEmpty()); assertTrue(rep.topTriggers.isEmpty())
    }

    @Test fun `QA_recording_blankSegmentsOnlyIsSafe`() {
        val rep = RecordingPipeline(rulesClassify).run(listOf(SttSegment("", 0), SttSegment("   ", 1000)))
        assertTrue(rep.perStatement.isEmpty()); assertEquals(Label.SAFE, rep.overall)
    }

    @Test fun `QA_recording_everyStatementClassifiedAsRecordingSource`() {
        val seen = mutableSetOf<Source>()
        RecordingPipeline({ t, s -> seen += s; rulesClassify(t, s) }).run(listOf(SttSegment("Hello how are you today.", 0), SttSegment("Fine thanks.", 3000)))
        assertEquals(setOf(Source.RECORDING), seen)
    }

    @Test fun `QA_recording_hinglishScamScriptIsScam`() {
        val rep = RecordingPipeline(rulesClassify).run(listOf(
            SttSegment("Main CBI se bol raha hoon.", 0), SttSegment("Aap digital arrest mein hain.", 4000),
            SttSegment("Kisi ko mat batana aur call mat kaato.", 8000), SttSegment("Abhi AnyDesk install karo aur OTP bata do.", 12000)))
        assertEquals(Label.SCAM, rep.overall); assertTrue(rep.topTriggers.isNotEmpty())
    }

    @Test fun `QA_recording_devanagariScamScriptIsScam`() {
        val rep = RecordingPipeline(rulesClassify).run(listOf(
            SttSegment("मैं सीबीआई से बोल रहा हूं। आप डिजिटल अरेस्ट में हैं।", 0), SttSegment("किसी को मत बताना और फोन मत काटना।", 5000)))
        assertEquals(Label.SCAM, rep.overall)
    }

    @Test fun `QA_recording_longSilenceGapDoesNotForgetEarlierScam`() {
        val rep = RecordingPipeline(rulesClassify).run(listOf(
            SttSegment("You are under digital arrest.", 0), SttSegment("Okay then, see you for dinner tomorrow evening.", 3_600_000)))
        assertEquals(Label.SCAM, rep.overall)
    }

    @Test fun `QA_recording_benignChatterStaysSafe`() {
        val rep = RecordingPipeline(rulesClassify).run(listOf(
            SttSegment("Beta khana kha liya?", 0), SttSegment("Haan mummy, kal shaam ko milte hain.", 3000), SttSegment("Your order will be delivered tomorrow.", 6000)))
        assertEquals(Label.SAFE, rep.overall)
    }

    @Test fun `QA_recording_topTriggersCapAndCaseInsensitiveDedupe`() {
        val v = { t: String, s: Source -> Verdict(t, Label.SCAM, 0.9, "r", listOf("OTP", "otp ", "a$t", "b$t", "c$t", "d$t", "e$t"), "x", 0, s) }
        val rep = RecordingPipeline(v).run(listOf(SttSegment("one two three.", 0), SttSegment("four five six.", 3000)))
        assertTrue(rep.topTriggers.size <= 5)
        assertEquals(1, rep.topTriggers.count { it.trim().equals("otp", true) })
    }

    @Test fun `QA_recording_lowercaseCallReportIsCallDeterministic`() {
        val segs = listOf(SttSegment("Share your OTP now.", 0), SttSegment("Do it right now please.", 2000))
        assertEquals(RecordingPipeline(rulesClassify).run(segs), RecordingPipeline(rulesClassify).run(segs))
    }
}
