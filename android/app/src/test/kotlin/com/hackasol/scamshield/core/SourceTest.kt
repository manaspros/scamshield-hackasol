package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Test

class SourceTest {
    @Test fun T1_1_parsesLegacyStrings() {
        assertEquals(Source.CAPTION, Source.parse("caption"))
        assertEquals(Source.PASTE, Source.parse("manual"))
        assertEquals(Source.PASTE, Source.parse("try_api"))
        assertEquals(Source.PASTE, Source.parse("try-api"))
        assertEquals(Source.SHARE, Source.parse("share"))
        assertEquals(Source.SMS, Source.parse("sms"))
        assertEquals(Source.WHATSAPP, Source.parse("whatsapp"))
        assertEquals(Source.NOTIFICATION, Source.parse("signal"))
        assertEquals(Source.RECORDING, Source.parse("recording"))
        assertEquals(Source.CAPTION, Source.parse(" CAPTION "))
        assertEquals(Source.PASTE, Source.parse("PASTE"))
        assertEquals(Source.SHARE, Source.parse("Share"))
        assertEquals(Source.SMS, Source.parse("SMS"))
        assertEquals(Source.WHATSAPP, Source.parse("WhatsApp"))
        assertEquals(Source.NOTIFICATION, Source.parse("notification"))
        assertEquals(Source.RECORDING, Source.parse("RECORDING"))
        assertEquals(Source.CAPTION, Source.parse(null))
        assertEquals(Source.CAPTION, Source.parse("unrecognized"))
    }
}
