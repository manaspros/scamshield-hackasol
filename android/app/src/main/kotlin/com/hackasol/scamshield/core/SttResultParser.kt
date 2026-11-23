package com.hackasol.scamshield.core

/**
 * Vosk recognizer JSON -> [SttSegment]. Hand-parsed because org.json is stubbed in JVM unit tests.
 *
 * Final result: {"result":[{"word":"..","start":1.23,"end":1.5,"conf":1.0}],"text":".."}
 * Returns null for empty text and for partials ({"partial":".."}) or unparsable input.
 * startMs = first word's start * 1000, else [fallbackStartMs] (result without word timings).
 */
object SttResultParser {
    fun parse(json: String, fallbackStartMs: Long = 0L): SttSegment? {
        val parsed = try {
            Reader(json).value() as? Map<*, *>
        } catch (_: IllegalArgumentException) {
            null
        }
        val obj = parsed ?: return null
        val text = (obj["text"] as? String)?.trim().orEmpty()
        if (text.isEmpty()) return null
        val first = (obj["result"] as? List<*>)?.firstOrNull() as? Map<*, *>
        val startMs = (first?.get("start") as? Double)?.let { Math.round(it * 1000) } ?: fallbackStartMs
        return SttSegment(text, startMs)
    }

    // Minimal JSON reader: objects -> Map, arrays -> List, strings (all escapes), numbers -> Double, literals.
    private class Reader(private val s: String) {
        private var i = 0
        private fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }
        private fun fail(): Nothing = throw IllegalArgumentException("bad json at $i")

        fun value(): Any? {
            ws()
            if (i >= s.length) fail()
            return when (s[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> num()
            }
        }

        private fun lit(w: String, v: Any?): Any? {
            if (!s.startsWith(w, i)) fail()
            i += w.length
            return v
        }

        private fun num(): Double {
            val st = i
            while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++
            return s.substring(st, i).toDoubleOrNull() ?: fail()
        }

        private fun str(): String {
            i++ // opening quote
            val sb = StringBuilder()
            while (i < s.length) {
                val c = s[i++]
                if (c == '"') return sb.toString()
                if (c != '\\') { sb.append(c); continue }
                if (i >= s.length) fail()
                when (val e = s[i++]) {
                    'n' -> sb.append('\n')
                    't' -> sb.append('\t')
                    'r' -> sb.append('\r')
                    'b' -> sb.append('\b')
                    'f' -> sb.append('\u000c')
                    '"', '\\', '/' -> sb.append(e)
                    'u' -> {
                        if (i + 4 > s.length) fail()
                        sb.append((s.substring(i, i + 4).toIntOrNull(16) ?: fail()).toChar())
                        i += 4
                    }
                    else -> fail()
                }
            }
            fail()
        }

        private fun arr(): List<Any?> {
            i++
            val out = mutableListOf<Any?>()
            ws()
            if (i < s.length && s[i] == ']') { i++; return out }
            while (true) {
                out += value()
                ws()
                if (i >= s.length) fail()
                when (s[i++]) {
                    ',' -> {}
                    ']' -> return out
                    else -> fail()
                }
            }
        }

        private fun obj(): Map<String, Any?> {
            i++
            val out = mutableMapOf<String, Any?>()
            ws()
            if (i < s.length && s[i] == '}') { i++; return out }
            while (true) {
                ws()
                if (i >= s.length || s[i] != '"') fail()
                val k = str()
                ws()
                if (i >= s.length || s[i++] != ':') fail()
                out[k] = value()
                ws()
                if (i >= s.length) fail()
                when (s[i++]) {
                    ',' -> {}
                    '}' -> return out
                    else -> fail()
                }
            }
        }
    }
}
