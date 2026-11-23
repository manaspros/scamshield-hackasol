package com.hackasol.scamshield.qa

import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.ScamType
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.Verdict
import com.hackasol.scamshield.core.VerdictEvent
import java.io.File

/** Resolve android/app regardless of whether Gradle runs tests from android/app or elsewhere. */
internal object QAPaths {
    val appDir: File by lazy {
        var d: File? = File(System.getProperty("user.dir")).absoluteFile
        while (d != null) {
            if (File(d, "src/main/AndroidManifest.xml").exists()) return@lazy d
            if (File(d, "app/src/main/AndroidManifest.xml").exists()) return@lazy File(d, "app")
            if (File(d, "android/app/src/main/AndroidManifest.xml").exists()) return@lazy File(d, "android/app")
            d = d.parentFile
        }
        error("cannot locate android/app from ${System.getProperty("user.dir")}")
    }
    val repoRoot: File get() = appDir.parentFile.parentFile
}

internal fun qaVerdict(label: Label, conf: Double, text: String = "t", source: Source = Source.PASTE, triggers: List<String> = emptyList()) =
    Verdict(text, label, conf, "r", triggers, "rules-only", 0, source)

internal fun qaEvent(id: Long = 1, ts: Long = 0, label: Label = Label.SCAM, type: ScamType? = ScamType.OTP,
                     triggers: List<String> = listOf("otp"), source: Source = Source.SMS) =
    VerdictEvent(id, ts, source, label, 0.9, type, triggers, "rules-only")

/** Minimal strict JSON validator (org.json is stubbed in JVM unit tests). Throws on malformed input. */
internal object QAJson {
    fun assertValid(s: String) {
        val p = P(s); p.ws(); p.value(); p.ws()
        check(p.i == s.length) { "trailing data at ${p.i}" }
    }
    private class P(val s: String) {
        var i = 0
        fun ws() { while (i < s.length && s[i] in " \t\r\n") i++ }
        fun value() {
            check(i < s.length) { "eof" }
            when (s[i]) {
                '{' -> obj(); '[' -> arr(); '"' -> str()
                't' -> lit("true"); 'f' -> lit("false"); 'n' -> lit("null")
                else -> num()
            }
        }
        fun lit(w: String) { check(s.startsWith(w, i)) { "bad literal at $i" }; i += w.length }
        fun num() {
            val m = Regex("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?").matchAt(s, i)
            check(m != null) { "bad number at $i" }; i += m!!.value.length
        }
        fun str() {
            check(s[i] == '"'); i++
            while (true) {
                check(i < s.length) { "unterminated string" }
                val c = s[i++]
                when {
                    c == '"' -> return
                    c < ' ' -> error("raw control char at ${i - 1}")
                    c == '\\' -> {
                        check(i < s.length); val e = s[i++]
                        if (e == 'u') { check(i + 4 <= s.length && s.substring(i, i + 4).all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }); i += 4 }
                        else check(e in "\"\\/bfnrt") { "bad escape" }
                    }
                }
            }
        }
        fun arr() {
            i++; ws(); if (s[i] == ']') { i++; return }
            while (true) { ws(); value(); ws(); if (s[i] == ',') { i++; continue }; check(s[i] == ']'); i++; return }
        }
        fun obj() {
            i++; ws(); if (s[i] == '}') { i++; return }
            while (true) { ws(); str(); ws(); check(s[i] == ':'); i++; ws(); value(); ws(); if (s[i] == ',') { i++; continue }; check(s[i] == '}'); i++; return }
        }
    }
}
