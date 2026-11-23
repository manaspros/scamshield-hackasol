package com.hackasol.scamshield.core

/**
 * Caller number of the call in progress, read from the dialer's own notification (no READ_PHONE_STATE / READ_CALL_LOG).
 * A saved contact shows a name, not a number: then there is no number and the bank-call rule stays silent (correct).
 * Holds a number only, never message text. Cleared when the call notification is removed; also expires after 2 h.
 */
object CallContext {
    const val MAX_AGE_MS = 2L * 60 * 60 * 1000
    const val CATEGORY_CALL = "call"   // Notification.CATEGORY_CALL
    private val DIGIT_RUN = Regex("""\+?\d[\d ()\-.]*""")

    private class Seen(val number: String?, val tsMs: Long, val key: String?)
    @Volatile private var latest: Seen? = null
    /** Bumped when a call notification arrives while no call was known: one value per call, for per-call dedupe. */
    @Volatile var callGeneration = 0L; private set

    /** Only the platform's call category counts: a package match would also take a dialer's missed-call or promo notification. */
    fun isCallNotification(category: String?): Boolean = category == CATEGORY_CALL

    /** [key] is the notification's key, so only its own removal clears the number (see [onRemoved]). */
    @Synchronized
    fun onCallNotification(title: String, text: String, nowMs: Long, key: String? = null) {
        if (!inCall(nowMs)) callGeneration++
        latest = Seen(numberIn(title) ?: numberIn(text), nowMs, key)
    }

    /** A call notification is showing (a number or a saved contact's name), seen within the last 2 h. */
    fun inCall(nowMs: Long): Boolean = latest?.let { nowMs - it.tsMs in 0..MAX_AGE_MS } ?: false

    /** Clears only when the removed notification is the one that set the current number. */
    @Synchronized
    fun onRemoved(key: String) { if (latest?.key == key) latest = null }

    fun clear() { latest = null }

    /** Digits of the caller number (e.g. "+91 98000 00010" -> "919800000010"), or null: no number, cleared, or older than 2 h. */
    fun caller(nowMs: Long): String? = latest?.takeIf { nowMs - it.tsMs in 0..MAX_AGE_MS }?.number

    /** First run of 10 to 15 digits (separators ignored); a name or a short code like "00:12" gives null. */
    internal fun numberIn(s: String): String? =
        DIGIT_RUN.findAll(s).map { m -> m.value.filter { it.isDigit() } }.firstOrNull { it.length in 10..15 }
}
