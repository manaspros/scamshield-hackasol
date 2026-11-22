package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordingPipelineTest {
    private val scamWords = listOf("otp", "block", "police", "arrest")

    // Fake classifier: keyword hit -> SCAM, else SAFE.
    private fun classify(text: String, source: Source): Verdict {
        assertEquals(Source.RECORDING, source)
        val hits = scamWords.filter { text.lowercase().contains(it) }
        return Verdict(
            text = text,
            label = if (hits.isEmpty()) Label.SAFE else Label.SCAM,
            confidence = 0.95, reason = "fake", triggers = hits,
            engine = "rules-only", latencyMs = 0, source = source,
        )
    }

    private fun segs(vararg lines: String) =
        lines.mapIndexed { i, t -> SttSegment(t, i * 3_000L) }

    @Test fun T2_4_scamScriptRaisesRisk() {
        val report = RecordingPipeline(::classify).run(segs(
            "Namaste sir main bank se bol raha hoon.",
            "Aapka account block ho jayega.",
            "Turant apna OTP bataiye warna police case hoga.",
            "Abhi batao",
        ))
        assertEquals(Label.SCAM, report.overall)
        assertTrue(report.risk >= 0.6)
        assertTrue(report.perStatement.any { it.verdict.label == Label.SCAM })
        assertTrue(report.topTriggers.containsAll(listOf("block", "otp", "police")))
    }

    @Test fun T2_4_genuineCallStaysSafe() {
        val report = RecordingPipeline(::classify).run(segs(
            "Haan mummy main shaam ko ghar aa raha hoon.",
            "Sabzi le aaunga aur dudh bhi.",
            "Theek hai phir milte hain.",
        ))
        assertEquals(Label.SAFE, report.overall)
        assertTrue(report.perStatement.isNotEmpty())
        assertTrue(report.perStatement.all { it.verdict.label == Label.SAFE })
        assertTrue(report.topTriggers.isEmpty())
    }
}
