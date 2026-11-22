package com.hackasol.scamshield.core

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GoldenHourTest {
    private val now = 1_800_000_000_000L
    private val min = 60_000L

    private fun logWithEvents(): InMemoryVerdictLog = InMemoryVerdictLog().apply {
        append(VerdictEvent(1, now - 10 * min, Source.SMS, Label.SCAM, 0.95, ScamType.KYC, listOf("KYC update"), "rules-only"))
        append(VerdictEvent(2, now - 5 * min, Source.RECORDING, Label.SCAM, 0.9, ScamType.DIGITAL_ARREST, listOf("CBI \"officer\""), "gemma+rules"))
    }

    @Test fun T5_4_cardPrefilled() {
        val card = CaseCard.fromLog(logWithEvents(), startMs = now, nowMs = now)
        assertTrue(card.pack.moneyLost)
        assertEquals(listOf(ScamType.KYC, ScamType.DIGITAL_ARREST), card.pack.evidence.map { it.scamType })
        assertEquals(4, card.pack.userFields.size)
        assertNull(card.graphJson)
        assertTrue(card.toJson().contains("\"graph\":null"))
        assertTrue(CaseCard.fromLog(logWithEvents(), now, now, "{\"nodes\":[]}").toJson().contains("\"graph\":{\"nodes\":[]}"))

        val gh = card.goldenHour
        assertEquals(60 * min, gh.remainingMs(now))
        assertEquals(45 * min, gh.remainingMs(now + 15 * min))
        assertFalse(gh.expired(now + 59 * min))
        assertTrue(gh.expired(now + 60 * min))
        assertEquals(0L, gh.remainingMs(now + 120 * min))
        assertEquals(60 * min, gh.remainingMs(now - 5 * min)) // clock skew before start is clamped
    }

    @Test fun T5_4_zipManifestVerifies() {
        val events = logWithEvents().since(0)
        val card = CaseCard.fromLog(logWithEvents(), startMs = now, nowMs = now)
        val bytes = EvidenceZip.build(card, events)
        assertTrue(EvidenceZip.verify(bytes))

        val entries = linkedMapOf<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { z ->
            while (true) { val e = z.nextEntry ?: break; entries[e.name] = z.readBytes() }
        }
        assertEquals(setOf("card.json", "events.json", "manifest.json"), entries.keys)
        val manifest = String(entries.getValue("manifest.json"))
        assertTrue(manifest.contains(EvidenceZip.sha256Hex(entries.getValue("card.json"))))
        assertTrue(manifest.contains(EvidenceZip.sha256Hex(entries.getValue("events.json"))))

        fun rezip(m: Map<String, ByteArray>): ByteArray {
            val out = ByteArrayOutputStream()
            ZipOutputStream(out).use { z -> m.forEach { (n, b) -> z.putNextEntry(ZipEntry(n)); z.write(b); z.closeEntry() } }
            return out.toByteArray()
        }
        assertTrue(EvidenceZip.verify(rezip(entries)))
        // tampered events.json
        assertFalse(EvidenceZip.verify(rezip(entries + ("events.json" to "[]".toByteArray()))))
        // missing manifest, extra unlisted file, garbage bytes
        assertFalse(EvidenceZip.verify(rezip(entries - "manifest.json")))
        assertFalse(EvidenceZip.verify(rezip(entries + ("extra.txt" to "x".toByteArray()))))
        assertFalse(EvidenceZip.verify(ByteArray(0)))
    }
}
