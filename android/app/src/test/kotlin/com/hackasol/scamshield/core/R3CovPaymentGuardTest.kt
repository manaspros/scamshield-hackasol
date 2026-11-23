package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class R3CovPaymentGuardTest {
    private val pay = "com.phonepe.app"
    private val now = 10_000_000L
    private val w = PaymentGuard.WINDOW_MS
    private val cd = PaymentGuard.COOLDOWN_MS

    @Test fun R3_COV_foreground_insideWindowWarns() = assertTrue(PaymentGuard.shouldWarnOnForeground(pay, now, now - 60_000, null))
    @Test fun R3_COV_foreground_exactlyAtWindowBoundaryWarns() = assertTrue(PaymentGuard.shouldWarnOnForeground(pay, now, now - w, null))
    @Test fun R3_COV_foreground_afterWindowNoWarn() = assertFalse(PaymentGuard.shouldWarnOnForeground(pay, now, now - w - 1, null))
    @Test fun R3_COV_foreground_noPriorVerdictNoWarn() = assertFalse(PaymentGuard.shouldWarnOnForeground(pay, now, null, null))
    @Test fun R3_COV_foreground_nonPaymentAppNoWarn() = assertFalse(PaymentGuard.shouldWarnOnForeground("com.whatsapp", now, now - 1000, null))
    @Test fun R3_COV_foreground_futureVerdictTimestampNoWarn() = assertFalse(PaymentGuard.shouldWarnOnForeground(pay, now, now + 1, null))

    @Test fun R3_COV_foreground_cooldownSuppressesThenAllows() {
        assertFalse(PaymentGuard.shouldWarnOnForeground(pay, now, now - 1000, now - 1000))
        assertFalse(PaymentGuard.shouldWarnOnForeground(pay, now, now - 1000, now - cd + 1))
        assertTrue(PaymentGuard.shouldWarnOnForeground(pay, now, now - 1000, now - cd))
        assertTrue("future lastWarned (clock change) must not mute forever", PaymentGuard.shouldWarnOnForeground(pay, now, now - 1000, now + 5))
    }

    @Test fun R3_COV_collect_cooldownAppliesToCollectToo() {
        assertTrue(PaymentGuard.shouldWarnOnCollect(pay, "", "Collect request from example@upi", now, null))
        assertFalse(PaymentGuard.shouldWarnOnCollect(pay, "", "Collect request from example@upi", now, now - 1000))
    }

    @Test fun R3_COV_collect_positives() {
        val pos = listOf(
            "Collect request of Rs 500 from example@upi. Approve to pay",
            "Enter UPI PIN to receive Rs 2000",
            "example@upi has requested money from you",
            "Payment request from Ramesh",
            "आपको पैसे का अनुरोध मिला है",
            "Unhone paise maange hain, approve karein",
            "Request bheji gayi hai 500 rupaye ki",
        )
        for (t in pos) assertTrue(t, PaymentGuard.isUpiCollectRequest(pay, "", t))
        assertTrue(PaymentGuard.isUpiCollectRequest("com.google.android.apps.messaging", "VK-BANK", "Collect request pending, enter UPI PIN to receive"))
    }

    @Test fun R3_COV_collect_negatives() {
        val neg = listOf(
            "Rs 500 credited to your account from example@upi",
            "Payment of Rs 250 successful to Shop",
            "123456 is your OTP for payment request. Do not share",
            "Money received from Ramesh",
        )
        for (t in neg) assertFalse(t, PaymentGuard.isUpiCollectRequest(pay, "", t))
        assertFalse(PaymentGuard.isUpiCollectRequest("com.whatsapp", "", "Collect request from example@upi"))
    }

    @Test fun R3_COV_content_allLangsNonEmptyAnd1930Action() {
        for (l in listOf("en", "hi", "hne")) {
            val c = PaymentGuard.content(l)
            assertTrue(l, c.title.isNotBlank() && c.text.isNotBlank() && c.callFamily.isNotBlank() && c.channel.isNotBlank())
            assertTrue(l, c.call1930.contains("1930"))
        }
        assertEquals("Receiving money never needs your PIN. Ask family first", PaymentGuard.content("en").text)
        assertEquals("1930", PaymentGuard.HELPLINE)
    }
}
