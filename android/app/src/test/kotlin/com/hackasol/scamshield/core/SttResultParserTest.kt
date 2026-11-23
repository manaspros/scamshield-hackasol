package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SttResultParserTest {
    @Test
    fun T2_6_parsesVoskJson() {
        val hi = """{"result":[{"conf":0.9,"end":3.0,"start":2.46,"word":"आपका"},{"conf":1.0,"end":3.4,"start":3.0,"word":"खाता"}],"text":"आपका खाता"}"""
        assertEquals(SttSegment("आपका खाता", 2460), SttResultParser.parse(hi))

        // escapes: \u-escaped Devanagari char (U+0905), \" and \n
        assertEquals("अ \"ok\"\nx", SttResultParser.parse("""{"text":"अ \"ok\"\nx"}""")?.text)

        // no word timings -> fallback start
        assertEquals(SttSegment("hello", 777), SttResultParser.parse("""{"text":"hello"}""", 777))

        // empty / partial / garbage -> null
        assertNull(SttResultParser.parse("""{"text":""}"""))
        assertNull(SttResultParser.parse("""{"result":[],"text":"  "}"""))
        assertNull(SttResultParser.parse("""{"partial":"आपका"}"""))
        assertNull(SttResultParser.parse("{}"))
        assertNull(SttResultParser.parse(""))
        assertNull(SttResultParser.parse("{\"text\":\"abc"))
    }
}
