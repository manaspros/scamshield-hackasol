package com.hackasol.scamshield.core

data class MappedNotification(val source: Source, val text: String)

/**
 * Pure filter/mapper for posted notifications. Stateful only for the 60 s dedupe; the caller passes the post time so
 * tests need no clock. [map] claims the message; the caller calls [abort] if classify then fails, so a failed
 * classify does not suppress the retry. Keyed by package + text. Thread-safe. [onDrop] receives the drop reason (never the text).
 */
class NotificationMapper(
    private val ownPackage: String = OWN_PACKAGE,
    private val minLength: Int = MIN_LENGTH,
    private val dedupeMs: Long = DEDUPE_MS,
    private val onDrop: (String) -> Unit = {},
) {
    private val seen = HashMap<String, Long>()   // "pkg|normalized text" -> tsMs committed; guarded by this

    /** Returns null when the notification should be ignored. */
    @Synchronized
    fun map(pkg: String, text: String, ongoing: Boolean, groupSummary: Boolean, tsMs: Long): MappedNotification? {
        if (ongoing || groupSummary || pkg == ownPackage) { onDrop("ongoing_group_or_own pkg=$pkg"); return null }
        val t = text.trim()
        if (t.length < minLength) { onDrop("too_short pkg=$pkg len=${t.length}"); return null }
        seen.entries.removeAll { tsMs - it.value >= dedupeMs }
        val k = key(pkg, t)
        if (seen.containsKey(k)) { onDrop("duplicate pkg=$pkg len=${t.length}"); return null }
        seen[k] = tsMs   // claimed now: the same message often arrives twice within milliseconds, while the first is still classifying
        return MappedNotification(sourceFor(pkg), t)
    }

    /** Releases the claim from [map] when classify failed or was cancelled, so the retry is not dropped for 60 s. */
    @Synchronized
    fun abort(pkg: String, text: String) { seen.remove(key(pkg, text.trim())) }

    private fun key(pkg: String, trimmed: String) = pkg + "|" + trimmed.lowercase()

    companion object {
        const val OWN_PACKAGE = "com.hackasol.scamshield"
        const val MIN_LENGTH = 15
        const val DEDUPE_MS = 60_000L

        private val WHATSAPP = setOf("com.whatsapp", "com.whatsapp.w4b")
        private val SMS_APPS = setOf(
            "com.google.android.apps.messaging", "com.samsung.android.messaging",
            "com.android.mms", "com.oneplus.mms",
        )

        // Telegram (org.telegram.messenger) has no Source of its own, so it falls into NOTIFICATION.
        fun sourceFor(pkg: String): Source = when (pkg) {
            in WHATSAPP -> Source.WHATSAPP
            in SMS_APPS -> Source.SMS
            else -> Source.NOTIFICATION
        }
    }
}
