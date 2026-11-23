package com.hackasol.scamshield.core

import java.text.Normalizer

/**
 * Undoes cheap evasions before the rules match: "O T P", "o.t.p", "0TP", "ОТР" (Cyrillic), "ＯＴＰ" (fullwidth),
 * zero-width characters inside words, emoji between words, and the Devanagari nukta ("गिरफ़्तार" vs "गिरफ्तार").
 * The rules see the normalised copy only; triggers are cut from it and then masked as before. Pure.
 */
object TextNormalizer {
    private const val NUKTA = '़'

    // Cyrillic and Greek letters that look like Latin ones (lower and upper case), the ones used to dodge keyword filters.
    private val LOOKALIKE: Map<Char, Char> = buildMap {
        "аa еe оo рp сc уy хx іi јj ѕs ԁd ɡg һh ӏl ԛq ԝw".split(' ').forEach { put(it[0], it[1]) }
        "АA ВB ЕE КK МM НH ОO РP СC ТT УY ХX ІI ЈJ ЅS".split(' ').forEach { put(it[0], it[1]) }
        "αa οo ρp νv τt ιi κk ΑA ΒB ΕE ΗH ΙI ΚK ΜM ΝN ΟO ΡP ΤT ΥY ΧX ΖZ".split(' ').forEach { put(it[0], it[1]) }
    }

    // Three or more single letters split by one space, dot, dash, underscore or star: "O T P", "K.Y.C", "a n y d e s k".
    // Only single letters, so ordinary words ("I am a boy") are left alone.
    private val SPELLED = Regex("(?<![\\p{L}\\p{N}])(?:\\p{L}[ .\\-_*]){2,}\\p{L}(?![\\p{L}\\p{N}])")
    private val ZERO_TP = Regex("(?<![\\p{L}\\p{N}])0tp(?![\\p{L}\\p{N}])", RegexOption.IGNORE_CASE)
    private val HINDI_OTP = Regex("ओ[\\s.]*टी[\\s.]*पी\\.?")
    // Pictographs and symbols between words ("share 🙏 the OTP"): replaced by a space so word windows still count words.
    private val SYMBOLS = Regex("[\\p{So}\\p{Sk}\\x{1F000}-\\x{1FAFF}\\x{2600}-\\x{27BF}\\x{FE0F}]+")

    /** NFKC + nukta removal only: safe to apply to regex patterns too (they must match folded text). */
    fun foldScript(s: String): String = Normalizer.normalize(s, Normalizer.Form.NFKC).let { n ->
        if (n.indexOf(NUKTA) < 0) n else n.replace(NUKTA.toString(), "")
    }

    fun normalize(text: String): String {
        var t = foldScript(text)
        // Format characters (zero-width space/joiner, BOM, soft hyphen) never belong inside a word.
        t = t.filterNot { Character.getType(it) == Character.FORMAT.toInt() }
        if (t.any { it in LOOKALIKE }) t = t.map { LOOKALIKE[it] ?: it }.joinToString("")
        t = SYMBOLS.replace(t, " ")
        t = SPELLED.replace(t) { m -> m.value.filter { it.isLetter() } }
        t = ZERO_TP.replace(t, "otp")
        t = HINDI_OTP.replace(t, "ओटीपी")
        return t
    }
}
