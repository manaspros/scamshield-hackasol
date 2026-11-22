package com.hackasol.scamshield.core

data class MappedNotification(val source: Source, val text: String)

/**
 * Pure filter/mapper for posted notifications. Stateful only for the 60 s text dedupe; the
 * caller passes the post time so tests need no clock.
 */
class NotificationMapper(
    private val ownPackage: String = OWN_PACKAGE,
    private val minLength: Int = MIN_LENGTH,
    private val dedupeMs: Long = DEDUPE_MS,
) {
    private val seen = HashMap<String, Long>()   // normalized text -> tsMs first accepted

    /** Returns null when the notification should be ignored. */
    fun map(pkg: String, text: String, ongoing: Boolean, groupSummary: Boolean, tsMs: Long): MappedNotification? {
        if (ongoing || groupSummary || pkg == ownPackage) return null
        val t = text.trim()
        if (t.length < minLength) return null
        val key = t.lowercase()
        seen.entries.removeAll { tsMs - it.value >= dedupeMs }
        if (seen.containsKey(key)) return null
        seen[key] = tsMs
        return MappedNotification(sourceFor(pkg), t)
    }

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
