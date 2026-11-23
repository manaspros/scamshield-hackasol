package com.hackasol.scamshield.qa

import com.hackasol.scamshield.core.*
import com.hackasol.scamshield.core.graph.ClaimParsers
import org.junit.Assert.*
import org.junit.Test

/** Regression tests for bugs found by QA and since fixed. */
class QAFixedBugsTest {
    @Test fun `QA_rules_genuineBankOtpSmsMustNotBeScam`() {
        val r = RuleScorer.score("Your OTP is 482913. Do not share it with anyone.")
        assertNotEquals("genuine OTP notice scored ${r.score} ${r.triggers}", Label.SCAM, r.label)
    }

    @Test fun `QA_rules_triggersMustNotContainOtpDigits`() {
        val r = RuleScorer.score("OTP 482913 please bhejo")
        assertTrue("triggers leak OTP value: ${r.triggers}", r.triggers.none { it.contains("482913") })
    }

    @Test fun `QA_prompt_contextKeepsLastTwoNonBlankEntries`() {
        val s = GemmaPrompt.build("q", listOf("aaa", "bbb", ""))
        assertTrue(s, s.contains("\"aaa\" | \"bbb\""))
    }

    @Test fun `QA_parser_notSafeProseDoesNotBecomeSafe`() {
        assertEquals(Label.SCAM, LlmOutputParser.parse("This is NOT SAFE. It is a SCAM.")?.label)
    }

    @Test fun `QA_log_latestOnTimestampTieReturnsLastAppended`() {
        val l = InMemoryVerdictLog(); l.append(qaEvent(1, 100)); l.append(qaEvent(2, 100))
        assertEquals("SqliteVerdictLog orders ts DESC, id DESC; in-memory must agree", 2L, l.latest()!!.id)
    }

    @Test fun `QA_upi_devanagariNamesDifferingOnlyInVowelSignsMismatch`() {
        assertTrue(UpiQr("a@b", payeeName = "राम").nameMismatch("रम"))
    }

    @Test fun `QA_claims_zeroPrefixedIndianMobileIsDetected`() {
        assertEquals(listOf("9876543210"), ClaimParsers.numbers("call 09876543210 now"))
    }
}
