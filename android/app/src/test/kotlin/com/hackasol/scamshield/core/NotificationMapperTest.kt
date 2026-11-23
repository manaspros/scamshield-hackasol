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

    @Test fun abortedMessageIsNotDeduped() {   // classify threw: the retry 10 s later must go through
        val m = NotificationMapper()
        assertNotNull(map(m, "com.whatsapp", ts = 1_000))
        assertNull("claimed while classifying", map(m, "com.whatsapp", ts = 2_000))
        m.abort("com.whatsapp", "  $body ")
        assertNotNull(map(m, "com.whatsapp", ts = 11_000))
    }

    @Test fun sameTextFromAnotherPackageIsNotDeduped() {
        val m = NotificationMapper()
        map(m, "com.whatsapp", ts = 1_000)
        assertNotNull(map(m, "com.google.android.apps.messaging", ts = 2_000))
        assertNull(map(m, "com.whatsapp", ts = 3_000))
    }

    @Test fun concurrentMapAndCommitDoNotThrow() {
        val m = NotificationMapper()
        val errors = java.util.concurrent.ConcurrentLinkedQueue<Throwable>()
        val pool = java.util.concurrent.Executors.newFixedThreadPool(8)
        repeat(8) { th ->
            pool.execute {
                try {
                    repeat(2_000) { i ->
                        val t = "message number $i from thread $th long enough"
                        m.map("com.whatsapp", t, false, false, i.toLong())?.let { if (i % 2 == 0) m.abort("com.whatsapp", t) }
                    }
                } catch (e: Throwable) { errors += e }
            }
        }
        pool.shutdown()
        assertEquals(true, pool.awaitTermination(30, java.util.concurrent.TimeUnit.SECONDS))
        assertEquals(emptyList<Throwable>(), errors.toList())
    }

    @Test fun T2_2_ignoresOwn() {
        assertNull(map(NotificationMapper(), "com.hackasol.scamshield"))
    }
}
