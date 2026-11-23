package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReportPackTest {
    private val hour = 3_600_000L
    private val now = 1_800_000_000_000L

    private fun ev(id: Long, ts: Long, type: ScamType?, label: Label, triggers: List<String>) =
        VerdictEvent(id, ts, Source.WHATSAPP, label, 0.9, type, triggers, "rules-only")

    @Test fun T3_1_prefillsFromEvents() {
        val events = listOf(
            ev(1, now - 2 * hour, ScamType.DIGITAL_ARREST, Label.SCAM, listOf("CBI", "digital arrest")),
            ev(2, now - 1 * hour, null, Label.SAFE, emptyList()),
            ev(3, now - 48 * hour, ScamType.OTP, Label.SCAM, listOf("otp")),
        )
        val pack = ReportPack.build(events, moneyLost = true, nowMs = now)
        assertEquals(1, pack.evidence.size)
        val e = pack.evidence[0]
        assertEquals(ScamType.DIGITAL_ARREST, e.scamType)
        assertEquals(Source.WHATSAPP, e.source)
        assertEquals(listOf("CBI", "digital arrest"), e.triggers)
        assertTrue(e.time.endsWith("IST"))
        assertEquals(listOf("scammer_number", "amount", "utr", "screenshots", "notes"), pack.userFields.map { it.key })
        assertTrue(pack.userFields.all { it.value.isEmpty() })
        assertTrue(pack.toJson().contains("\"digital arrest\""))
    }

    @Test fun T3_1_lostVsNotYetTargets() {
        val lost = ReportPack.build(emptyList(), moneyLost = true, nowMs = now).targets
        assertEquals(listOf("1930", null), lost.map { it.phone })
        assertEquals("https://cybercrime.gov.in", lost.mapNotNull { it.url }.single())
        val notYet = ReportPack.build(emptyList(), moneyLost = false, nowMs = now).targets
        assertEquals("https://sancharsaathi.gov.in/sfc/", notYet.mapNotNull { it.url }.single())
        assertTrue(notYet.any { it.phone == "1930" })
        assertTrue(notYet.none { it.url == ReportTargets.CYBERCRIME_URL })
    }
}
