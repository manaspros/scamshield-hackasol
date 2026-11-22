package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TotpTest {
    @Test fun T5_6_rfcVectors() {
        val secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" // Base32 of RFC 6238's SHA1 test secret.
        val vectors = listOf(
            59L to "94287082",
            1111111109L to "07081804",
            1111111111L to "14050471",
            1234567890L to "89005924",
            2000000000L to "69279037",
            20000000000L to "65353130"
        )
        vectors.forEach { (seconds, expected) -> assertEquals(expected, Totp.code(secret, seconds * 1000L, 8)) }
    }

    @Test fun T5_6_codesMatchOffline() {
        val sharedSecret = Totp.generateSecret()
        val time = 1_800_000_000_000L
        val firstPhoneCode = Totp.code(sharedSecret, time)
        val secondPhoneCode = Totp.code(sharedSecret, time)
        assertEquals(firstPhoneCode, secondPhoneCode)
        assertTrue(Totp.verify(sharedSecret, firstPhoneCode, time))
    }
}
