package com.hackasol.scamshield.core

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Anonymised trend rows for dashboard/validate.mjs: exactly {district, scam_type, date}.
 * scam_type vocabulary == ScamType enum names (dashboard/agg.mjs SCAM_TYPES is identical).
 * District must be one of data/districts.json; it is chosen by the user and passed in, never inferred.
 */
data class TrendRow(val district: String, val scamType: ScamType, val date: String)

object TrendExport {
    private val DATE_FMT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd").withZone(ZoneId.of("Asia/Kolkata"))

    fun rows(events: List<VerdictEvent>, district: String): List<TrendRow> =
        events.mapNotNull { e ->
            val type = e.scamType
            if (e.label == Label.SAFE || type == null) null
            else TrendRow(district, type, DATE_FMT.format(Instant.ofEpochMilli(e.tsMs)))
        }

    /** Key order is fixed as district, scam_type, date. */
    fun toJson(rows: List<TrendRow>): String =
        rows.joinToString(",", "[", "]") {
            "{\"district\":${jsonQuote(it.district)},\"scam_type\":${jsonQuote(it.scamType.name)},\"date\":${jsonQuote(it.date)}}"
        }

    fun export(events: List<VerdictEvent>, district: String): String = toJson(rows(events, district))
}
