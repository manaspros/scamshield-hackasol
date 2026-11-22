package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class VerdictLogTest {
    private fun ev(id: Long, ts: Long, type: ScamType?, label: Label = Label.SCAM) =
        VerdictEvent(id, ts, Source.SMS, label, 0.9, type, listOf("otp"), "rules-only")

    @Test fun T1_3_countsByType() {
        val log = InMemoryVerdictLog()
        assertEquals(emptyMap<ScamType, Int>(), log.countsByType())
        log.append(ev(1, 10, ScamType.OTP))
        log.append(ev(2, 20, ScamType.OTP))
        log.append(ev(3, 30, ScamType.KYC))
        log.append(ev(4, 40, null, Label.SAFE))
        assertEquals(mapOf(ScamType.OTP to 2, ScamType.KYC to 1), log.countsByType())
    }

    @Test fun T1_3_sinceFilters() {
        val log = InMemoryVerdictLog()
        assertNull(log.latest())
        log.append(ev(1, 100, ScamType.OTP))
        log.append(ev(3, 300, ScamType.JOB))
        log.append(ev(2, 200, ScamType.KYC))
        assertEquals(listOf(2L, 3L), log.since(200).map { it.id })
        assertEquals(emptyList<VerdictEvent>(), log.since(301))
        assertEquals(3L, log.latest()!!.id)
    }
}
