package com.hackasol.scamshield.core

/**
 * Case-insensitive regex whose \b and \w understand Devanagari on BOTH runtimes:
 *  - Android (ICU regex): Unicode-aware by default, and the inline (?U) flag is NOT supported
 *    (it throws at compile time -> ExceptionInInitializerError -> NoClassDefFoundError).
 *  - Desktop JVM (unit tests): ASCII-only by default, needs (?U) = UNICODE_CHARACTER_CLASS.
 */
internal object UnicodeRegex {
    private val isAndroid: Boolean = System.getProperty("java.vm.name")?.contains("Dalvik", ignoreCase = true) == true ||
        System.getProperty("java.vendor")?.contains("Android", ignoreCase = true) == true

    private val prefix = if (isAndroid) "(?i)" else "(?iU)"

    fun of(pattern: String): Regex = Regex(prefix + pattern)
}
