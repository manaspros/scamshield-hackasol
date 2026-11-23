package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.graph.Brands
import com.hackasol.scamshield.core.graph.ContextRules
import com.hackasol.scamshield.core.graph.FlagKind
import com.hackasol.scamshield.core.graph.KnowledgeGraph
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Fix 2: genuine messages that rules used to lift, brand-host bypasses, and known-sender seeding. Synthetic text only. */
class R3Fix2Test {
    private val safeLlm = LlmResult(Label.SAFE, 0.3, "looks fine", null)

    private fun fuse(text: String, llm: LlmResult?): FusedResult =
        Fusion.fuse(llm, RuleScorer.score(text), RuleScorer.scamType(text))

    private val genuine = listOf(
        "papa hospital mein hain, urgent kaam hai, kal aaunga",
        "Papa ko hospital le gaye, bill pay kar diya",
        "One moment, I am at the hospital for 2 hours",
        "Your EMI of Rs 2,300 is overdue. In case you have already paid, please ignore.",
        "Watch Kaun Banega Crorepati tonight at 9 pm on Sony TV",
        "Dear customer, power supply will be cut off from 10am to 2pm for maintenance",
        "Your Jio plan will expire on 25 Nov. Recharge now to continue",
        "You have 3 pending tasks today",
        "Your Zoom video call recording is ready",
        "Your parcel is out for delivery. Call our helpline for help",
    )

    @Test fun R3_FIX2_genuineStaysSafe() {
        for (g in genuine) {
            assertEquals("rules: $g (${RuleScorer.score(g).score})", Label.SAFE, RuleScorer.score(g).label)
            assertEquals("fuse null: $g", Label.SAFE, fuse(g, null).label)
            assertEquals("fuse safe: $g", Label.SAFE, fuse(g, safeLlm).label)
        }
    }

    @Test fun R3_FIX2_noSingleRuleLiftOnGenuine() {
        // 0.30 is the lowest single-rule weight allowed to remain; none of these may match any rule above it.
        for (g in genuine) assertTrue("$g -> ${RuleScorer.score(g).triggers}", RuleScorer.score(g).score < 0.31)
    }

    @Test fun R3_FIX2_realScamsStillFire() {
        val scams = listOf(
            "Papa, main hospital mein hoon, is number pe 5000 bhejo",
            "Your loan is overdue. Pay now or legal notice will be sent to your contacts",
            "Congratulations! You won Kaun Banega Crorepati lottery, pay registration fee to claim",
            "Bijli ka bill pending hai, aaj raat 9:30 baje bijli kat jayegi, turant is number pe call karo 98XXXXXX10",
            "Your SIM will be blocked today, complete KYC now",
            "Task karo aur daily 5000 kamao, telegram group join karo",
            "I have your nude video, pay Rs 5000 or else I will make it viral",
        )
        for (s in scams) assertTrue("$s -> ${RuleScorer.score(s).score}", RuleScorer.score(s).label != Label.SAFE)
    }

    @Test fun R3_FIX2_officialShortDomainsAreNotLookalikes() {
        for (h in listOf("amzn.to", "a.co", "amzn.in", "paytm.me", "www.amazon.in")) {
            assertTrue(h, Brands.isOfficialHost(h)); assertNull(h, Brands.lookalikeOf(h))
        }
        assertEquals("amazon", Brands.lookalikeOf("amaz0n-refund.xyz"))
    }

    @Test fun R3_FIX2_sharedHostingIsNeverOfficial() {
        assertFalse(Brands.isOfficialHost("sbi-kyc.s3.amazonaws.com"))
        assertFalse(Brands.isOfficialHost("amazonaws.com"))
        for (h in listOf("cloudfront.net", "blogspot.com", "firebaseapp.com", "web.app", "github.io", "pages.dev", "netlify.app", "vercel.app", "herokuapp.com"))
            assertFalse(h, Brands.isOfficialHost("x.$h"))
        assertTrue(Brands.lookalikeOf("sbi-kyc.s3.amazonaws.com") != null)
    }

    @Test fun R3_FIX2_safeMessageFromNormalNumberDoesNotSeedKnownUpi() {
        val g = KnowledgeGraph()
        g.ingest("Your Zoom video call recording is ready", "VM-EXAMPL-S", 1_000L)   // warm graph
        g.ingest("hello, my id is example@upi, call 98XXXXXX10", "9800000010", 2_000L)
        assertFalse(g.knownUpi("example@upi"))
        assertFalse(g.knownNumber("98XXXXXX10"))
        val flags = ContextRules.newUpiPay("send money to example@upi", "9800000010", g)
        assertTrue(flags.toString(), flags.any { it.kind == FlagKind.NEW_UPI_PAY })
    }

    @Test fun R3_FIX2_dltSenderStillSeedsKnownUpi() {
        val g = KnowledgeGraph()
        g.ingest("Pay your bill at example@upi", "VM-EXAMPL-S", 1_000L)
        assertTrue(g.knownUpi("example@upi"))
    }
}
