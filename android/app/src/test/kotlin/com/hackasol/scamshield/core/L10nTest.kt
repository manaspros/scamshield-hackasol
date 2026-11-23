package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.graph.ContextFlag
import com.hackasol.scamshield.core.graph.FlagKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class L10nTest {
    private val deva = Regex("[\\u0900-\\u097F]")
    private val quote = "OTP bata dijiye"

    private fun v(label: Label, source: Source = Source.CAPTION) = Verdict(
        text = "synthetic message", label = label, confidence = 0.9, reason = "test",
        triggers = listOf(quote), engine = "rules-only", latencyMs = 0, source = source,
    )

    private fun fields(label: Label, type: ScamType?, lang: String?) =
        v(label, if (label == Label.SCAM) Source.CAPTION else Source.SMS).let {
        if (lang == null) AlertNotificationMapper.fields(AlertPolicy.plan(it, it.source), it, type)!!
        else AlertNotificationMapper.fields(AlertPolicy.plan(it, it.source), it, type, lang)!!
    }

    @Test fun L10N_normalize() {
        assertEquals("en", normalizeLang("en"))
        assertEquals("hne", normalizeLang(" HNE "))
        assertEquals("hi", normalizeLang("hi"))
        assertEquals("hi", normalizeLang(null))
        assertEquals("hi", normalizeLang("fr"))
    }

    @Test fun L10N_notificationEnglish() {
        val f = fields(Label.SCAM, ScamType.OTP, "en")
        assertEquals("Scam warning", f.title)
        assertEquals("OTP scam · \"$quote\" · Do not share OTP/PIN/money", f.text)
        assertEquals("Report", f.actions.single().label)
        assertEquals("report", f.actions.single().route)
        assertFalse(deva.containsMatchIn(f.title + f.text.replace(quote, "") + f.actions[0].label))
        assertEquals("Suspicious", fields(Label.SUSPICIOUS, null, "en").title)
    }

    @Test fun L10N_notificationEnglishAllTypesAreAscii() {
        for (t in ScamType.values()) L10n.scamType(t, "en")?.let { assertFalse(deva.containsMatchIn(it)) }
    }

    @Test fun L10N_notificationHindiAndDefault() {
        val f = fields(Label.SCAM, ScamType.OTP, "hi")
        assertEquals("स्कैम की चेतावनी (SCAM)", f.title)
        assertTrue(f.text.contains("OTP ठगी") && f.text.contains("OTP/PIN/पैसे न दें"))
        assertEquals("रिपोर्ट करें (Report)", f.actions.single().label)
        assertEquals(f, fields(Label.SCAM, ScamType.OTP, null))
        assertEquals(f, fields(Label.SCAM, ScamType.OTP, "xx"))
        assertEquals(f, fields(Label.SCAM, ScamType.OTP, "hne"))
    }

    @Test fun L10N_ruleReasonsEveryId() {
        assertEquals(44, L10n.ruleIds.size)
        for (id in L10n.ruleIds) {
            val en = L10n.ruleReason(id, "en"); val hi = L10n.ruleReason(id, "hi"); val hne = L10n.ruleReason(id, "hne")
            assertTrue(id, en.isNotBlank() && en != id && !deva.containsMatchIn(en))
            assertTrue(id, deva.containsMatchIn(hi))
            assertEquals(id, hi, hne)
        }
        assertEquals("zzz", L10n.ruleReason("zzz", "en"))
    }

    @Test fun L10N_ruleScorerReasonByLang() {
        val t = "OTP bata dijiye"
        assertEquals("Asks you to share an OTP/code", RuleScorer.score(t).reason.substringBefore(";"))
        assertEquals("Asks you to share an OTP/code", RuleScorer.score(t, "en").reason.substringBefore(";"))
        assertTrue(deva.containsMatchIn(RuleScorer.score(t, "hi").reason))
        assertEquals("No scam phrases found", RuleScorer.score("hello there", "en").reason)
        assertTrue(deva.containsMatchIn(RuleScorer.score("hello there", "hi").reason))
        assertEquals(RuleScorer.score(t).score, RuleScorer.score(t, "hi").score, 0.0)
    }

    @Test fun L10N_flagReasons() {
        val link = ContextFlag(FlagKind.LINK_NOT_ALLOWLISTED, "Link goes to evil.example, not a .bank.in or .gov.in site.")
        assertEquals(link.reason, L10n.flagReason(link, "en"))
        val hi = L10n.flagReason(link, "hi")
        assertTrue(hi.contains("evil.example") && deva.containsMatchIn(hi))
        for (k in FlagKind.values()) {
            val f = ContextFlag(k, "English text")
            assertTrue(k.name, deva.containsMatchIn(L10n.flagReason(f, "hi")) || k == FlagKind.LINK_NOT_ALLOWLISTED)
            assertEquals("English text", L10n.flagReason(f, "en"))
        }
    }

    @Test fun L10N_overlayStrings() {
        assertEquals("This statement is SCAM · 87%", L10n.overlayTitle(Label.SCAM, 87, "en"))
        assertEquals("This may be a scam — do not share OTP / PIN / money", L10n.overlayLine(Label.SCAM, "en"))
        assertEquals("यह धोखाधड़ी हो सकती है — OTP / PIN / पैसे न दें", L10n.overlayLine(Label.SCAM, "hi"))
        assertEquals("Why: ", L10n.why("en")); assertEquals("Heard: ", L10n.heard("en")); assertEquals("Engine: ", L10n.engine("en"))
        assertEquals("Overall call: SCAM risk 80%", L10n.overallCall(Label.SCAM, 80, "en"))
        assertEquals("Call 1930", L10n.call1930("en"))
        assertTrue(deva.containsMatchIn(L10n.why("hi") + L10n.overallCall(Label.SCAM, 80, "hne")))
        for (l in Label.values()) assertFalse(deva.containsMatchIn(L10n.overlayLine(l, "en")))
        val cap = L10n.captionTitle("en") + L10n.captionLine("en") + L10n.captionHint("en") + L10n.openVolumePanel("en")
        assertFalse(deva.containsMatchIn(cap))
        assertTrue(deva.containsMatchIn(L10n.captionLine("hi")))
    }
}
