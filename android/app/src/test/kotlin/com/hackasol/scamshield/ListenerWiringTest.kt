package com.hackasol.scamshield

import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.NotificationMapper
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.Verdict
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ListenerWiringTest {
    private val body = "Your account will be blocked today, share OTP"
    private val classified = mutableListOf<Pair<String, Source>>()
    private val dispatched = mutableListOf<Pair<Verdict, Source>>()
    private val wiring = ListenerWiring(
        NotificationMapper(),
        { t, s -> classified += t to s; Verdict(t, Label.SCAM, 0.9, "r", emptyList(), "rules-only", 0, s) },
        { v, s -> dispatched += v to s },
    )

    private fun info(pkg: String, text: String = body, ongoing: Boolean = false, group: Boolean = false, ts: Long = 0) =
        NotificationInfo(pkg, "title", text, ongoing, group, ts)

    @Test fun T2_3_classifiesWithMappedSource() = runBlocking {
        wiring.onPosted(info("com.whatsapp"))
        wiring.onPosted(info("com.google.android.apps.messaging", "$body 2"))
        assertEquals(listOf(Source.WHATSAPP, Source.SMS), classified.map { it.second })
        assertEquals(body, classified[0].first)
        assertEquals(listOf(Source.WHATSAPP, Source.SMS), dispatched.map { it.second })
    }

    @Test fun T2_3_ignoresOwnAndOngoing() = runBlocking {
        wiring.onPosted(info(NotificationMapper.OWN_PACKAGE))
        wiring.onPosted(info("com.whatsapp", ongoing = true))
        wiring.onPosted(info("com.whatsapp", group = true))
        wiring.onPosted(info("com.whatsapp", "short"))
        assertTrue(classified.isEmpty() && dispatched.isEmpty())
    }

    @Test fun T2_3_dedupesRepeatedText() = runBlocking {
        wiring.onPosted(info("com.whatsapp", ts = 0))
        wiring.onPosted(info("com.whatsapp", ts = 1_000))
        assertEquals(1, classified.size)
    }
}
