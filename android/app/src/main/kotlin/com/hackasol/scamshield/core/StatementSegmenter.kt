package com.hackasol.scamshield.core

/**
 * Turns a stream of caption *snapshots* (the whole visible caption text, which scrolls and gets
 * rewritten while the speaker talks) into discrete, de-duplicated *statements*.
 *
 * - New words = words after the latest occurrence of the tail of already-committed words.
 * - A statement is emitted when: a sentence terminator has words after it, the pending text
 *   reaches MAX_WORDS, or the pending text has been unchanged for STABLE_MS
 *   (TERMINATED_STABLE_MS if it already ends with . ? ! ।).
 *
 * Pure Kotlin; drive it with [onSnapshot] on every caption change and [onTick] periodically.
 */
class StatementSegmenter(
    private val stableMs: Long = 1200,
    private val terminatedStableMs: Long = 500,
    private val maxWords: Int = 25,
) {
    private var lastWords: List<String> = emptyList()
    private var lastChangeMs = 0L
    private val committed = ArrayDeque<String>()      // normalized, last COMMIT_MEMORY words
    private val recentStatements = ArrayDeque<String>()

    fun reset() {
        lastWords = emptyList(); committed.clear(); recentStatements.clear()
    }

    fun onSnapshot(text: String, nowMs: Long): List<String> {
        val words = tokenize(text)
        if (words != lastWords) {
            lastWords = words
            lastChangeMs = nowMs
        }
        return drain(nowMs)
    }

    fun onTick(nowMs: Long): List<String> = drain(nowMs)

    private fun drain(nowMs: Long): List<String> {
        val out = mutableListOf<String>()
        while (true) {
            val pending = pendingWords()
            if (pending.isEmpty()) break
            val stableFor = nowMs - lastChangeMs

            val termIdx = (0 until pending.size - 1).firstOrNull { isTerminated(pending[it]) }
            when {
                termIdx != null -> commit(pending.subList(0, termIdx + 1), out)
                pending.size >= maxWords -> commit(pending.subList(0, maxWords), out)
                stableFor >= stableMs ||
                    (isTerminated(pending.last()) && stableFor >= terminatedStableMs) -> {
                    commit(pending, out); return out
                }
                else -> return out
            }
        }
        return out
    }

    private fun pendingWords(): List<String> {
        if (committed.isEmpty()) return lastWords
        val norm = lastWords.map(::normalize)
        val maxM = minOf(8, committed.size)
        val minM = if (committed.size >= 2) 2 else 1
        for (m in maxM downTo minM) {
            val tail = committed.toList().takeLast(m)
            val pos = lastIndexOfSubList(norm, tail)
            if (pos >= 0) return lastWords.subList(pos + m, lastWords.size)
        }
        // No overlap: captions scrolled fully or were rewritten. Drop a leading run of words we
        // already committed recently to limit duplicates, then treat the rest as new.
        val seen = committed.toSet()
        var start = 0
        while (start < norm.size && norm[start] in seen && start < 6) start++
        return if (start == norm.size) emptyList() else lastWords.subList(start, lastWords.size)
    }

    private fun commit(words: List<String>, out: MutableList<String>) {
        val snapshot = words.toList()
        for (w in snapshot) {
            committed.addLast(normalize(w))
            if (committed.size > COMMIT_MEMORY) committed.removeFirst()
        }
        val statement = snapshot.joinToString(" ").trim()
        val key = statement.lowercase()
        if (statement.length < 2 || key in recentStatements) return
        recentStatements.addLast(key)
        if (recentStatements.size > 8) recentStatements.removeFirst()
        out += statement
    }

    companion object {
        private const val COMMIT_MEMORY = 60
        private val TERMINATORS = charArrayOf('.', '?', '!', '।', '॥')

        fun tokenize(text: String) = text.split(Regex("\\s+")).filter { it.isNotBlank() }
        // Trim punctuation only: Devanagari vowel signs are not "letters", so isLetterOrDigit would eat them.
        private const val PUNCT = ".,?!।॥\"'“”‘’:;()[]-–—…"
        fun normalize(w: String) = w.lowercase().trim { it.isWhitespace() || it in PUNCT }
        fun isTerminated(w: String) = w.isNotEmpty() && w.last() in TERMINATORS

        fun lastIndexOfSubList(hay: List<String>, needle: List<String>): Int {
            if (needle.isEmpty() || needle.size > hay.size) return -1
            for (i in hay.size - needle.size downTo 0) {
                var ok = true
                for (j in needle.indices) if (hay[i + j] != needle[j]) { ok = false; break }
                if (ok) return i
            }
            return -1
        }
    }
}
