package com.hackasol.scamshield

import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.ScamType
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.VerdictEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class VerdictRowMapperTest {
    @Test fun T1_4_rowRoundTrip() {
        val e = VerdictEvent(7, 1_700_000_000_123, Source.SMS, Label.SCAM, 0.91, ScamType.OTP,
            listOf("share otp", "say \"now\"", "back\\slash", "line\nbreak", "uni\u001Fsep \u0001 हि"), "gemma+rules")
        val row = VerdictRowMapper.toRow(e) + ("id" to 7L)
        assertEquals(e, VerdictRowMapper.fromRow(row))
    }

    @Test fun T1_4_nullScamTypeAndEmptyTriggers() {
        val e = VerdictEvent(1, 5, Source.CAPTION, Label.SAFE, 0.2, null, emptyList(), "rules-only")
        val row = VerdictRowMapper.toRow(e)
        assertNull(row["scam_type"])
        assertEquals(e, VerdictRowMapper.fromRow(row + ("id" to 1L)))
    }

    @Test fun T1_4_badRowIsNullNotThrow() {
        assertNull(VerdictRowMapper.fromRow(mapOf("label" to "???", "ts_ms" to 1L)))
        assertEquals(listOf("a"), VerdictRowMapper.decodeTriggers("[\"a\",\"unterminated"))
    }
}
