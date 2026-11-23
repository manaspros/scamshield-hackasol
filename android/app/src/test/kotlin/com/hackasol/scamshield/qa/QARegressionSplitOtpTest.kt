package com.hackasol.scamshield.qa

import com.hackasol.scamshield.core.*
import org.junit.Assert.*
import org.junit.Test

/** Separator-split OTP digits must be masked in triggers (fixed in ea3f96e). */
class QARegressionSplitOtpTest {
    private fun leak(text: String) {
        val t = RuleScorer.score(text).triggers
        for (x in t) assertTrue("trigger '$x' carries ${x.count { Character.isDigit(it) }} digits for input '$text'", x.count { Character.isDigit(it) } < 4)
    }

    @Test fun `QA_e2ePrivacy_dashSplitOtp`() = leak("otp 482-913 bata do")
    @Test fun `QA_e2ePrivacy_dotSplitOtp`() = leak("otp 482.913 bata do")
    @Test fun `QA_e2ePrivacy_slashSplitOtp`() = leak("otp 482/913 bata do")
    @Test fun `QA_e2ePrivacy_spaceGroupedOtp`() = leak("otp 482 913 bata do")
    @Test fun `QA_e2ePrivacy_dashSplitDevanagariOtp`() = leak("ओटीपी ४८२-९१३ बताइए")
}
