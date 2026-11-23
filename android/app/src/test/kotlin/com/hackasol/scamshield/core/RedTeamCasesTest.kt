package com.hackasol.scamshield.core

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Red-team probes (evasions, Hinglish/Hindi phrasings, everyday genuine messages) through the rules-only path, the one
 * that runs when no model is installed. Cases are in src/test/resources/redteam_cases.txt; S?/G? lines are known gaps.
 */
class RedTeamCasesTest {
    private fun cases(): List<Pair<String, String>> {
        val f = listOf("src/test/resources/redteam_cases.txt", "app/src/test/resources/redteam_cases.txt").map(::File).first { it.exists() }
        return f.readLines().filter { it.isNotBlank() && !it.startsWith("#") }.map { l ->
            l.substringBefore('|') to l.substringAfter('|').replace("\\n", "\n").replace("<ZW>", "​").replace("<ZWJ>", "‍")
        }
    }

    private fun label(text: String) = Pipeline.decide(text, RuleScorer.score(text), null, emptyList()).label

    @Test fun scamsAreNotSafeAndGenuineMessagesAre() {
        val bad = cases().filter { (exp, _) -> exp == "S" || exp == "G" }.mapNotNull { (exp, text) ->
            val l = label(text)
            if ((exp == "S" && l == Label.SAFE) || (exp == "G" && l != Label.SAFE)) "[$exp got $l] $text" else null
        }
        assertTrue("${bad.size} red-team cases wrong:\n" + bad.joinToString("\n"), bad.isEmpty())
    }

    @Test fun evasionsNormaliseToTheSameVerdict() {
        val base = label("Sir please share the OTP you just received")
        for (t in listOf("Sir please share the O T P you just received", "Sir please share the 0TP you just received",
            "Sir please share the O​TP you just received", "Sir please share the ОТР you just received",
            "Sir please share the ＯＴＰ you just received", "Sir please share 🙏 the OTP 🙏 you just received"))
            assertTrue(t, label(t) == base)
    }

    @Test fun normalizerLeavesOrdinaryTextAlone() {
        for (t in listOf("I am a boy", "Plan A or B", "मैं घर जा रहा हूँ", "Meeting at 5 p.m. today"))
            assertTrue(t, TextNormalizer.normalize(t) == t)
        assertTrue(TextNormalizer.normalize("K.Y.C") == "KYC")
        assertTrue(TextNormalizer.normalize("गिरफ़्तार") == "गिरफ्तार")
    }
}
