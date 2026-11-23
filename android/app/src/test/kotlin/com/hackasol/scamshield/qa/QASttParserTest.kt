package com.hackasol.scamshield.qa

import com.hackasol.scamshield.core.*
import org.junit.Assert.*
import org.junit.Test

class QASttParserTest {
    private fun p(s: String, fb: Long = 0) = SttResultParser.parse(s, fb)

    // ---------- empty / partial / final ----------
    @Test fun `QA_stt_partialsAndEmptyResultsAreNull`() {
        for (s in listOf("""{"partial":""}""", """{"partial":"आपका खाता"}""", """{"text":""}""", """{"text":"   \n\t "}""", "{}", """{"result":[]}""")) assertNull(s, p(s))
    }

    @Test fun `QA_stt_partialKeyIsIgnoredWhenFinalTextIsPresent`() {
        assertEquals("final words", p("""{"partial":"par","text":"final words"}""")?.text)
    }

    @Test fun `QA_stt_missingConfidenceAndMissingWordFieldsStillParse`() {
        assertEquals(SttSegment("otp bata do", 1500), p("""{"result":[{"start":1.5,"word":"otp"},{"word":"bata"}],"text":"otp bata do"}"""))
    }

    @Test fun `QA_stt_startUsesFirstWordOnlyAndRoundsToMillis`() {
        assertEquals(1000L, p("""{"result":[{"start":1.0004}],"text":"a b"}""")!!.startMs)
        assertEquals(2461L, p("""{"result":[{"start":2.4605},{"start":0.1}],"text":"a b"}""")!!.startMs)
        assertEquals(2000L, p("""{"result":[{"start":2}],"text":"a"}""")!!.startMs)
    }

    @Test fun `QA_stt_wrongTypedTimingFallsBackToFallbackStart`() {
        for (r in listOf("""[{"start":"2.5"}]""", "[1,2]", "[null]", "[]", """{"a":1}""", "\"x\"")) assertEquals(r, 900L, p("""{"result":$r,"text":"hello there"}""", 900)!!.startMs)
    }

    @Test fun `QA_stt_textThatIsNotAStringIsNull`() {
        for (t in listOf("123", "null", "true", "[\"a\"]", """{"a":"b"}""")) assertNull(t, p("""{"text":$t}"""))
    }

    // ---------- Hindi / Devanagari / Hinglish ----------
    @Test fun `QA_stt_rawDevanagariHinglishAndMixedAreKeptVerbatimAndTrimmed`() {
        assertEquals("आपका खाता बंद हो जाएगा", p("""{"text":"  आपका खाता बंद हो जाएगा  "}""")!!.text)
        assertEquals("aap digital arrest mein hain", p("""{"text":"aap digital arrest mein hain"}""")!!.text)
        assertEquals("OTP बताइए please", p("""{"text":"OTP बताइए please"}""")!!.text)
    }

    @Test fun `QA_stt_unicodeEscapedDevanagariAndSurrogatePairDecode`() {
        assertEquals("ओटीपी", p("""{"text":"\u0913\u091f\u0940\u092a\u0940"}""")!!.text)
        assertEquals("ok \uD83D\uDE00", p("""{"text":"ok \ud83d\ude00"}""")!!.text)
    }

    @Test fun `QA_stt_danaAndNewlineInsideTextSurvive`() {
        assertEquals("पहला।\nदूसरा॥", p("""{"text":"पहला।\nदूसरा॥"}""")!!.text)
    }

    // ---------- malformed / garbage ----------
    @Test fun `QA_stt_malformedJsonIsNullNotException`() {
        for (s in listOf("", "   ", "not json", "{", "}", "{\"text\"", "{\"text\":", "{\"text\":\"abc", "{\"text\":\"a\\", "{\"text\":\"\\u12\"}", "{\"text\":\"\\uZZZZ\"}",
            "{\"text\":\"\\q\"}", "{text:\"a\"}", "{\"text\":\"a\",}", "[1,2", "[", "\"str\"", "42", "null", "[]", "[{\"text\":\"a\"}]", "{\"result\":[{\"start\":}],\"text\":\"a\"}",
            "{\"result\":[{\"start\":1..2}],\"text\":\"a\"}", "\u0000\u0001", "{\"text\":\"a\" \"b\":1}")) assertNull("'$s'", p(s))
    }

    @Test fun `QA_stt_trailingJunkAfterValidObjectStillYieldsSegment`() {
        assertEquals("a b", p("""{"text":"a b"} garbage""")?.text)
    }

    @Test(timeout = 20_000) fun `QA_stt_veryLongTextIsParsedFullyAndFast`() {
        val long = "नमस्ते ".repeat(150_000)
        assertEquals(long.trim(), p("""{"text":"$long"}""")!!.text)
    }

    @Test(timeout = 20_000) fun `QA_stt_veryLongGarbageIsNullAndFast`() {
        assertNull(p("x".repeat(1_000_000))); assertNull(p("{\"text\":\"" + "y".repeat(1_000_000)))
    }

    @Test fun `QA_stt_manyWordsInResultArray`() {
        val words = (1..20_000).joinToString(",") { """{"conf":1.0,"start":${it / 10.0},"word":"w$it"}""" }
        assertEquals(100L, p("""{"result":[$words],"text":"w1 w2"}""")!!.startMs)
    }

    // ---------- feeding StatementSegmenter / RecordingPipeline ----------
    private val rulesClassify: (String, Source) -> Verdict = { text, src ->
        val r = RuleScorer.score(text); val f = Fusion.fuse(null, r, RuleScorer.scamType(text))
        Verdict(text, f.label, f.confidence, f.reason, f.triggers, f.engine, 0, src, scamType = f.scamType)
    }
    private fun segs(vararg json: String): List<SttSegment> = json.mapIndexedNotNull { i, j -> p(j, i * 4000L) }

    @Test fun `QA_stt_unpunctuatedFinalsBecomeOneStatementEach`() {
        val list = segs(
            """{"result":[{"start":0.5}],"text":"आपका बैंक खाता बंद हो जाएगा"}""",
            """{"partial":"ignored partial"}""",
            """{"result":[{"start":4.5}],"text":"मैं सीबीआई से बोल रहा हूं"}""",
            """{"result":[{"start":8.5}],"text":"अपना ओटीपी बताइए"}""")
        assertEquals(3, list.size)
        val rep = RecordingPipeline(rulesClassify).run(list)
        assertEquals(list.map { it.text }, rep.perStatement.map { it.verdict.text })
    }

    @Test fun `QA_stt_hindiScamCallFromVoskJsonIsScam`() {
        val rep = RecordingPipeline(rulesClassify).run(segs(
            """{"text":"मैं सीबीआई से बोल रहा हूं आप डिजिटल अरेस्ट में हैं"}""",
            """{"text":"किसी को मत बताना और फोन मत काटना"}""",
            """{"text":"अभी स्क्रीन शेयर करो और पैसे ट्रांसफर करो"}"""))
        assertEquals(Label.SCAM, rep.overall)
    }

    @Test fun `QA_stt_hinglishScamCallFromVoskJsonIsScam`() {
        val rep = RecordingPipeline(rulesClassify).run(segs(
            """{"text":"main CBI se bol raha hoon aap digital arrest mein hain"}""",
            """{"text":"kisi ko mat batana aur call mat kaato"}""", """{"text":"abhi anydesk install karo aur otp bata do"}"""))
        assertEquals(Label.SCAM, rep.overall)
    }

    @Test fun `QA_stt_benignHindiCallFromVoskJsonIsSafeAndEmptyResultsAddNothing`() {
        val list = segs("""{"text":"बेटा खाना खा लिया"}""", """{"text":""}""", """{"partial":"कल शाम"}""", """{"text":"कल शाम को मिलते हैं"}""")
        assertEquals(2, list.size)
        assertEquals(Label.SAFE, RecordingPipeline(rulesClassify).run(list).overall)
    }

    @Test fun `QA_stt_noSegmentsAtAllGivesSafeEmptyReport`() {
        val rep = RecordingPipeline(rulesClassify).run(segs("""{"partial":"x"}""", "garbage", """{"text":""}"""))
        assertTrue(rep.perStatement.isEmpty()); assertEquals(Label.SAFE, rep.overall)
    }

    @Test fun `QA_stt_longUnpunctuatedFinalIsChunkedAtMax25Words`() {
        val text = (1..60).joinToString(" ") { "शब्द$it" }
        val rep = RecordingPipeline(rulesClassify).run(listOf(p("""{"text":"$text"}""")!!))
        assertTrue(rep.perStatement.size >= 3); assertTrue(rep.perStatement.all { it.verdict.text.split(" ").size <= 25 })
        assertEquals(60, rep.perStatement.sumOf { it.verdict.text.split(" ").size })
    }

    @Test fun `QA_stt_dandaSplitsOneFinalIntoTwoStatements`() {
        val rep = RecordingPipeline(rulesClassify).run(listOf(p("""{"text":"आपका खाता बंद है। अपना ओटीपी बताइए"}""")!!))
        assertEquals(2, rep.perStatement.size); assertTrue(rep.perStatement[0].verdict.text.endsWith("।"))
    }
}
