package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class NotificationMapperTest {
    private val body = "Your account will be blocked today"

    private fun map(m: NotificationMapper, pkg: String, text: String = body, ts: Long = 0,
                    ongoing: Boolean = false, group: Boolean = false) =
        m.map(pkg, text, ongoing, group, ts)

    @Test fun T2_2_mapsPackages() {
        fun src(pkg: String) = map(NotificationMapper(), pkg)?.source
        assertEquals(Source.WHATSAPP, src("com.whatsapp"))
        assertEquals(Source.WHATSAPP, src("com.whatsapp.w4b"))
        assertEquals(Source.NOTIFICATION, src("org.telegram.messenger"))
        assertEquals(Source.SMS, src("com.google.android.apps.messaging"))
        assertEquals(Source.SMS, src("com.samsung.android.messaging"))
        assertEquals(Source.SMS, src("com.android.mms"))
        assertEquals(Source.SMS, src("com.oneplus.mms"))
        assertEquals(Source.NOTIFICATION, src("com.example.other"))
        // too short is ignored, exactly 15 chars is kept
        assertNull(map(NotificationMapper(), "com.whatsapp", "short text"))
        assertNotNull(map(NotificationMapper(), "com.whatsapp", "a".repeat(15)))
        assertNull(map(NotificationMapper(), "com.whatsapp", "a".repeat(14)))
        // ongoing and group summaries are ignored
        assertNull(map(NotificationMapper(), "com.whatsapp", ongoing = true))
        assertNull(map(NotificationMapper(), "com.whatsapp", group = true))
    }

    @Test fun T2_2_dedupes() {
        val m = NotificationMapper()
        assertNotNull(map(m, "com.whatsapp", ts = 1_000))
        assertNull(map(m, "com.whatsapp", ts = 31_000))
        assertNull(map(m, "com.whatsapp", text = "  $body ", ts = 60_999))
        assertNotNull(map(m, "com.whatsapp", ts = 61_000))
        assertNotNull(map(m, "com.whatsapp", text = "A different long message", ts = 61_500))
    }

    @Test fun T2_2_ignoresOwn() {
        assertNull(map(NotificationMapper(), "com.hackasol.scamshield"))
    }
}
