package com.hackasol.scamshield.core

import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Offline RFC 6238 TOTP helpers. Secrets are represented as RFC 4648 base32 strings. */
object Totp {
    private const val STEP_SECONDS = 30L
    private const val BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    private val random = SecureRandom()

    /** Generates a random base32 secret suitable for pairing between devices. */
    @JvmStatic
    @JvmOverloads
    fun generateSecret(byteCount: Int = 20): String {
        require(byteCount > 0) { "byteCount must be positive" }
        val bytes = ByteArray(byteCount)
        random.nextBytes(bytes)
        return encodeBase32(bytes)
    }

    /** Returns the code for [timeMillis], using a 30-second step and six digits by default. */
    @JvmStatic
    @JvmOverloads
    fun code(secretBase32: String, timeMillis: Long = System.currentTimeMillis(), digits: Int = 6): String {
        require(digits in 1..10) { "digits must be between 1 and 10" }
        require(timeMillis >= 0) { "timeMillis must not be negative" }
        val counter = timeMillis / 1000L / STEP_SECONDS
        val key = decodeBase32(secretBase32)
        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec(key, "HmacSHA1"))
        val digest = mac.doFinal(ByteArray(8) { index -> (counter ushr (56 - index * 8)).toByte() })
        val offset = digest.last().toInt() and 0x0f
        val binary = ((digest[offset].toInt() and 0x7f) shl 24) or
            ((digest[offset + 1].toInt() and 0xff) shl 16) or
            ((digest[offset + 2].toInt() and 0xff) shl 8) or
            (digest[offset + 3].toInt() and 0xff)
        val modulus = powerOfTen(digits)
        return (binary.toLong() % modulus).toString().padStart(digits, '0')
    }

    /** Accepts the current code and one adjacent 30-second step on either side. */
    @JvmStatic
    @JvmOverloads
    fun verify(secretBase32: String, candidate: String, timeMillis: Long = System.currentTimeMillis(), digits: Int = 6): Boolean {
        if (candidate.length != digits || !candidate.all { it in '0'..'9' }) return false
        if (timeMillis < 0) return false
        val currentStep = timeMillis / 1000L / STEP_SECONDS
        return (-1L..1L).any { delta ->
            val step = currentStep + delta
            step >= 0 && constantTimeEquals(codeForStep(secretBase32, step, digits), candidate)
        }
    }

    private fun codeForStep(secret: String, step: Long, digits: Int): String {
        // Converting the step to its exact timestamp avoids changing the public time-based API.
        return code(secret, step * STEP_SECONDS * 1000L, digits)
    }

    private fun constantTimeEquals(left: String, right: String): Boolean {
        var difference = left.length xor right.length
        for (i in left.indices) difference = difference or (left[i].code xor (right.getOrElse(i) { '\u0000' }.code))
        return difference == 0
    }

    private fun powerOfTen(digits: Int): Long {
        var result = 1L
        repeat(digits) { result *= 10L }
        return result
    }

    private fun encodeBase32(bytes: ByteArray): String {
        val output = StringBuilder((bytes.size * 8 + 4) / 5)
        var buffer = 0
        var bits = 0
        for (byte in bytes) {
            buffer = (buffer shl 8) or (byte.toInt() and 0xff)
            bits += 8
            while (bits >= 5) {
                bits -= 5
                output.append(BASE32_ALPHABET[(buffer ushr bits) and 31])
            }
        }
        if (bits > 0) output.append(BASE32_ALPHABET[(buffer shl (5 - bits)) and 31])
        return output.toString()
    }

    private fun decodeBase32(value: String): ByteArray {
        val normalized = value.trim().uppercase().replace("=", "")
        require(normalized.isNotEmpty()) { "Base32 secret must not be empty" }
        val output = ByteArray(normalized.length * 5 / 8)
        var buffer = 0
        var bits = 0
        var outputIndex = 0
        for (char in normalized) {
            val symbol = BASE32_ALPHABET.indexOf(char)
            require(symbol >= 0) { "Invalid base32 secret" }
            buffer = (buffer shl 5) or symbol
            bits += 5
            if (bits >= 8) {
                bits -= 8
                output[outputIndex++] = (buffer ushr bits).toByte()
            }
        }
        require(bits == 0 || (buffer and ((1 shl bits) - 1)) == 0) { "Invalid base32 padding bits" }
        return output
    }
}
