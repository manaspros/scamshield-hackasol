package com.hackasol.scamshield.core

import java.net.URLDecoder
import java.nio.charset.StandardCharsets

/** Parsed UPI payment link. A scan always represents money leaving the user. */
data class UpiQr(
    val payeeAddress: String,
    val payeeName: String? = null,
    val amount: String? = null,
    val transactionNote: String? = null,
    val currency: String? = null,
    val isCollectRequest: Boolean = false,
) {
    fun nameMismatch(expectedName: String?): Boolean {
        val expected = normalizeName(expectedName.orEmpty())
        val actual = normalizeName(payeeName.orEmpty())
        return expected.isNotEmpty() && actual.isNotEmpty() && expected != actual
    }

    fun payFraming(): String = if (amount.isNullOrBlank()) {
        PAY_MONEY_FRAMING.format(payeeName?.takeIf { it.isNotBlank() } ?: payeeAddress)
    } else {
        PAY_AMOUNT_FRAMING.format(amount, payeeName?.takeIf { it.isNotBlank() } ?: payeeAddress)
    }

    companion object {
        const val PAY_AMOUNT_FRAMING = "You will PAY Rs %s to %s"
        const val PAY_MONEY_FRAMING = "You will PAY money to %s"
        const val NAME_MISMATCH_WARNING = "Name does not match this UPI ID"
        const val COLLECT_REQUEST_WARNING = "This QR requests money; scanning it sends money, it never receives money."

        /** Returns null for malformed links or invalid payee/amount fields. */
        fun parse(value: String?): UpiQr? {
            if (value == null) return null
            val text = value.trim()
            val schemeEnd = text.indexOf(':')
            if (schemeEnd < 0 || !text.substring(0, schemeEnd).equals("upi", ignoreCase = true)) return null
            val body = text.substring(schemeEnd + 1)
            if (!body.startsWith("//")) return null
            val pathAndQuery = body.substring(2)
            val queryAt = pathAndQuery.indexOf('?')
            if (queryAt < 0 || !pathAndQuery.substring(0, queryAt).equals("pay", ignoreCase = true)) return null
            val params = mutableMapOf<String, String>()
            try {
                pathAndQuery.substring(queryAt + 1).split('&').forEach { pair ->
                    if (pair.isEmpty()) return@forEach
                    val equalsAt = pair.indexOf('=')
                    val key = decode(if (equalsAt < 0) pair else pair.substring(0, equalsAt)).lowercase()
                    val content = decode(if (equalsAt < 0) "" else pair.substring(equalsAt + 1))
                    params[key] = content
                }
            } catch (_: IllegalArgumentException) {
                return null
            }
            val pa = params["pa"]?.trim()?.takeIf { PAYEE_ADDRESS.matches(it) } ?: return null
            val am = params["am"]?.trim()?.takeIf { it.isNotEmpty() }
            if (am != null && !AMOUNT.matches(am)) return null
            val note = params["tn"]
            val requestText = listOf(params["mode"], note, params["pn"])
                .filterNotNull().joinToString(" ").lowercase()
            return UpiQr(
                payeeAddress = pa,
                payeeName = params["pn"]?.takeIf { it.isNotBlank() },
                amount = am,
                transactionNote = note,
                currency = params["cu"]?.takeIf { it.isNotBlank() },
                isCollectRequest = COLLECT_WORDS.containsMatchIn(requestText),
            )
        }

        private val PAYEE_ADDRESS = Regex("^[^\\s@?&=]+@[^\\s@?&=]+$")
        private val AMOUNT = Regex("^[0-9]+(?:\\.[0-9]+)?$")
        private val COLLECT_WORDS = Regex("\\b(?:request|receive\\s+money|collect)\\b", RegexOption.IGNORE_CASE)

        private fun decode(value: String): String = URLDecoder.decode(value, StandardCharsets.UTF_8.name())
        private fun normalizeName(value: String): String = value.lowercase().filter { it.isLetterOrDigit() }
    }
}
