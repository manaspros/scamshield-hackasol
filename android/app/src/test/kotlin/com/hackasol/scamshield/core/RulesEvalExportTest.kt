package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/** Run: `RULES_EVAL_CSV=ml/reports/heldout.csv ./gradlew :app:testDebugUnitTest --tests '*RulesEvalExportTest*'` (path relative to repo root; default data/golden/eval_smoke.csv). */
class RulesEvalExportTest {
    /** RFC 4180 reader: quoted fields, "" escapes, commas/newlines inside quotes, LF or CRLF. */
    private fun parseCsv(s: String): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val f = StringBuilder()
        var inQ = false
        var i = 0
        fun endField() { row.add(f.toString()); f.setLength(0) }
        fun endRow() { endField(); if (!(row.size == 1 && row[0].isEmpty())) rows.add(row); row = mutableListOf() }
        while (i < s.length) {
            val c = s[i]
            when {
                inQ && c == '"' && i + 1 < s.length && s[i + 1] == '"' -> { f.append('"'); i++ }
                c == '"' -> inQ = !inQ
                !inQ && c == ',' -> endField()
                !inQ && c == '\r' -> {}
                !inQ && c == '\n' -> endRow()
                else -> f.append(c)
            }
            i++
        }
        if (f.isNotEmpty() || row.isNotEmpty()) endRow()
        return rows
    }

    private fun esc(s: String) = buildString {
        for (c in s) when {
            c == '"' -> append("\\\"")
            c == '\\' -> append("\\\\")
            c == '\n' -> append("\\n")
            c == '\r' -> append("\\r")
            c == '\t' -> append("\\t")
            c < ' ' -> append("\\u%04x".format(c.code))
            else -> append(c)
        }
    }
    private fun q(s: String) = "\"${esc(s)}\""
    private fun qn(s: String?) = if (s == null) "null" else q(s)

    @Test fun T1_12_writesJsonl() {
        val all = parseCsv(File("../../" + (System.getenv("RULES_EVAL_CSV")?.takeIf { it.isNotBlank() } ?: "data/golden/eval_smoke.csv")).readText(Charsets.UTF_8))
        assertEquals(listOf("text", "label", "lang", "scam_type", "template_id", "source"), all[0])
        val data = all.drop(1)
        val sb = StringBuilder()
        data.forEachIndexed { i, r ->
            assertEquals("row $i columns", 6, r.size)
            val text = r[0].trim()
            val res = RuleScorer.score(text)
            val goldType = r[3].trim().ifEmpty { null }
            // "text" is the key ml/scamshield_ml/eval_heldout.load_rules_preds joins on
            sb.append("{\"row\":").append(i)
                .append(",\"text\":").append(q(text))
                .append(",\"label\":").append(q(res.label.name))
                .append(",\"scam_type\":").append(qn(RuleScorer.scamType(text)?.name))
                .append(",\"triggers\":[").append(res.triggers.joinToString(",") { q(it) }).append(']')
                .append(",\"gold_label\":").append(q(r[1].trim()))
                .append(",\"gold_scam_type\":").append(qn(goldType))
                .append(",\"lang\":").append(q(r[2].trim()))
                .append(",\"template_id\":").append(q(r[4].trim()))
                .append("}\n")
        }
        val out = File("build/rules_preds.jsonl")
        out.parentFile?.mkdirs()
        out.writeText(sb.toString(), Charsets.UTF_8)
        assertEquals(data.size, out.readLines().size)
    }
}
