package com.hackasol.scamshield.core

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** A place to report. phone and/or url may be null. */
data class ReportTarget(val name: String, val phone: String?, val url: String?)

// [VERIFY] all contact points below against official sources before the demo / release.
object ReportTargets {
    const val HELPLINE_1930 = "1930"                                              // [VERIFY]
    /** Women's helpline, offered (opt-in) in the report chat. */
    const val WOMEN_HELPLINE_181 = "181"                                          // [VERIFY]
    const val CYBERCRIME_URL = "https://cybercrime.gov.in"                        // [VERIFY]
    const val CHAKSHU_URL = "https://sancharsaathi.gov.in/sfc/"                   // [VERIFY]

    val HELPLINE = ReportTarget("National Cyber Crime Helpline", HELPLINE_1930, null)
    val CYBERCRIME_PORTAL = ReportTarget("National Cyber Crime Reporting Portal", null, CYBERCRIME_URL)
    val CHAKSHU = ReportTarget("Chakshu (Sanchar Saathi)", null, CHAKSHU_URL)

    /** Money already lost: helpline + portal. Not yet lost: Chakshu + helpline. */
    fun forOutcome(moneyLost: Boolean): List<ReportTarget> =
        if (moneyLost) listOf(HELPLINE, CYBERCRIME_PORTAL) else listOf(CHAKSHU, HELPLINE)
}

data class EvidenceEntry(val tsMs: Long, val time: String, val scamType: ScamType?, val source: Source, val triggers: List<String>)

/** A field the user fills in themselves; value starts empty. */
data class UserField(val key: String, val label: String, val value: String = "")

data class ReportPack(
    val moneyLost: Boolean,
    val targets: List<ReportTarget>,
    val evidence: List<EvidenceEntry>,
    val userFields: List<UserField>,
) {
    fun toJson(): String = buildString {
        append("{\"money_lost\":").append(moneyLost)
        append(",\"targets\":[")
        append(targets.joinToString(",") {
            "{\"name\":${jsonQuote(it.name)},\"phone\":${it.phone?.let(::jsonQuote) ?: "null"},\"url\":${it.url?.let(::jsonQuote) ?: "null"}}"
        })
        append("],\"evidence\":[")
        append(evidence.joinToString(",") { e ->
            "{\"ts_ms\":${e.tsMs},\"time\":${jsonQuote(e.time)},\"scam_type\":${e.scamType?.let { jsonQuote(it.name) } ?: "null"}," +
                "\"source\":${jsonQuote(e.source.name)},\"triggers\":[${e.triggers.joinToString(",") { jsonQuote(it) }}]}"
        })
        append("],\"user_fields\":[")
        append(userFields.joinToString(",") {
            "{\"key\":${jsonQuote(it.key)},\"label\":${jsonQuote(it.label)},\"value\":${jsonQuote(it.value)}}"
        })
        append("]}")
    }

    companion object {
        const val DEFAULT_WINDOW_MS = 24L * 60 * 60 * 1000
        private val IST: ZoneId = ZoneId.of("Asia/Kolkata")
        private val TIME_FMT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm 'IST'").withZone(IST)

        fun formatTime(tsMs: Long): String = TIME_FMT.format(Instant.ofEpochMilli(tsMs))

        fun emptyUserFields(): List<UserField> = listOf(
            UserField("scammer_number", "Scammer phone number / UPI ID"),
            UserField("amount", "Amount lost (INR)"),
            UserField("utr", "UTR / transaction ID"),
            UserField("screenshots", "Screenshots (file names)"),
            UserField("notes", "Other details from the report chat"),
        )

        /** Pre-fills evidence from events in [nowMs - windowMs, nowMs]; SAFE verdicts are not evidence. */
        fun build(
            events: List<VerdictEvent>,
            moneyLost: Boolean,
            nowMs: Long,
            windowMs: Long = DEFAULT_WINDOW_MS,
        ): ReportPack {
            val evidence = events
                .filter { it.label != Label.SAFE && it.tsMs >= nowMs - windowMs && it.tsMs <= nowMs }
                .sortedBy { it.tsMs }
                .map { EvidenceEntry(it.tsMs, formatTime(it.tsMs), it.scamType, it.source, it.triggers) }
            return ReportPack(moneyLost, ReportTargets.forOutcome(moneyLost), evidence, emptyUserFields())
        }
    }
}
