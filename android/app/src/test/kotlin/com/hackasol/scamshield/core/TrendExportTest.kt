package com.hackasol.scamshield.core

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class TrendExportTest {
    private fun ev(id: Long, ts: Long, type: ScamType?, label: Label) =
        VerdictEvent(id, ts, Source.SMS, label, 0.9, type, listOf("secret phrase 98XXXXXX01"), "rules-only")

    @Test fun T3_8_threeKeysOnly() {
        // 2026-01-05T19:00:00Z is already 2026-01-06 00:30 in Asia/Kolkata.
        val utcEvening = 1_767_639_600_000L
        val events = listOf(
            ev(1, utcEvening, ScamType.OTP, Label.SCAM),
            ev(2, utcEvening + 86_400_000L, ScamType.INVESTMENT, Label.SUSPICIOUS),
            ev(3, utcEvening, null, Label.SAFE),
            ev(4, utcEvening, ScamType.KYC, Label.SAFE),
            ev(5, utcEvening, null, Label.SCAM),
        )
        val district = "Raipur" // from data/districts.json
        val rows = TrendExport.rows(events, district)
        assertEquals(2, rows.size)
        assertEquals("2026-01-06", rows[0].date)
        assertEquals("2026-01-07", rows[1].date)

        val json = TrendExport.toJson(rows)
        assertEquals(
            "[{\"district\":\"Raipur\",\"scam_type\":\"OTP\",\"date\":\"2026-01-06\"}," +
                "{\"district\":\"Raipur\",\"scam_type\":\"INVESTMENT\",\"date\":\"2026-01-07\"}]",
            json,
        )
        assertFalse(json.contains("secret"))
        assertFalse(json.contains("98XXXXXX01"))
        assertEquals("[]", TrendExport.toJson(emptyList()))

        // Test working dir is android/app; validate with: node dashboard/validate.mjs android/app/build/trend_export.json
        val out = File("build/trend_export.json")
        out.parentFile?.mkdirs()
        out.writeText(json)
        assertEquals(json, out.readText())
    }
}
