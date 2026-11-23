package com.hackasol.scamshield.qa

import com.hackasol.scamshield.core.*
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

class QAReportsTest {
    private val now = 10_000_000_000L
    private val win = ReportPack.DEFAULT_WINDOW_MS

    // ---------- Golden hour ----------
    @Test fun `QA_golden_boundaries`() {
        val g = GoldenHour(1000)
        assertEquals(GoldenHour.DURATION_MS, g.remainingMs(1000)); assertFalse(g.expired(1000))
        assertEquals(1L, g.remainingMs(1000 + GoldenHour.DURATION_MS - 1)); assertFalse(g.expired(1000 + GoldenHour.DURATION_MS - 1))
        assertEquals(0L, g.remainingMs(1000 + GoldenHour.DURATION_MS)); assertTrue(g.expired(1000 + GoldenHour.DURATION_MS))
    }

    @Test fun `QA_golden_clockBeforeStartAndFarFutureAreClamped`() {
        val g = GoldenHour(1_000_000)
        assertEquals(GoldenHour.DURATION_MS, g.remainingMs(0)); assertEquals(0L, g.remainingMs(Long.MAX_VALUE / 2))
        assertFalse(g.expired(0))
    }

    // ---------- Report pack ----------
    @Test fun `QA_pack_windowEdgesInclusiveAndFutureExcluded`() {
        val ev = listOf(qaEvent(1, now - win - 1), qaEvent(2, now - win), qaEvent(3, now), qaEvent(4, now + 1))
        assertEquals(listOf(now - win, now), ReportPack.build(ev, true, now).evidence.map { it.tsMs })
    }

    @Test fun `QA_pack_safeNeverEvidenceAndOutputSorted`() {
        val ev = listOf(qaEvent(1, now - 10), qaEvent(2, now - 30), qaEvent(3, now - 20, Label.SAFE, null))
        assertEquals(listOf(now - 30, now - 10), ReportPack.build(ev, false, now).evidence.map { it.tsMs })
    }

    @Test fun `QA_pack_emptyEventsStillYieldTargetsAndBlankUserFields`() {
        val p = ReportPack.build(emptyList(), true, now)
        assertTrue(p.evidence.isEmpty()); assertEquals(5, p.userFields.size); assertTrue(p.userFields.all { it.value.isEmpty() })
        QAJson.assertValid(p.toJson())
    }

    @Test fun `QA_pack_targetsDependOnMoneyLost`() {
        assertEquals(listOf("1930", null), ReportTargets.forOutcome(true).map { it.phone })
        assertEquals(ReportTargets.CYBERCRIME_URL, ReportTargets.forOutcome(true)[1].url)
        assertEquals(listOf(ReportTargets.CHAKSHU_URL, null), ReportTargets.forOutcome(false).map { it.url })
        assertEquals("1930", ReportTargets.forOutcome(false)[1].phone)
    }

    @Test fun `QA_pack_jsonValidWithNastyTriggersAndDevanagari`() {
        val nasty = listOf("a\"b\\c", "line\nbreak\ttab\u0001", "ओटीपी बताइए", " ", "😀")
        val j = ReportPack.build(listOf(qaEvent(1, now, triggers = nasty)), true, now).toJson()
        QAJson.assertValid(j)
    }

    @Test fun `QA_pack_istTimeFormat`() {
        assertEquals("2026-01-06 00:00 IST", ReportPack.formatTime(1_767_637_800_000L))
    }

    @Test fun `QA_pack_evidenceCarriesNoRawMessageText`() {
        assertEquals(setOf("tsMs", "time", "scamType", "source", "triggers"), EvidenceEntry::class.java.declaredFields.map { it.name }.toSet())
    }

    // ---------- Case card ----------
    @Test fun `QA_card_nullGraphSerialisesAsJsonNull`() {
        val c = CaseCard(GoldenHour(5), ReportPack.build(emptyList(), true, now)); QAJson.assertValid(c.toJson()); assertTrue(c.toJson().endsWith("\"graph\":null}"))
    }

    @Test fun `QA_card_graphEmbeddedVerbatim`() {
        val c = CaseCard(GoldenHour(5), ReportPack.build(emptyList(), true, now), "{\"nodes\":[1,2]}")
        QAJson.assertValid(c.toJson()); assertTrue(c.toJson().contains("\"graph\":{\"nodes\":[1,2]}"))
    }

    @Test fun `QA_card_fromLogUsesOnlyWindowedNonSafeEvents`() {
        val log = InMemoryVerdictLog()
        log.append(qaEvent(1, now - win - 5)); log.append(qaEvent(2, now - 100)); log.append(qaEvent(3, now - 50, Label.SAFE, null))
        val c = CaseCard.fromLog(log, startMs = now - 10, nowMs = now)
        assertEquals(1, c.pack.evidence.size); assertTrue(c.pack.moneyLost); assertEquals(now - 10, c.goldenHour.startMs)
    }

    // ---------- Evidence zip ----------
    private fun card(events: List<VerdictEvent> = listOf(qaEvent(1, now - 100))) = CaseCard(GoldenHour(now - 50), ReportPack.build(events, true, now))
    private fun entries(zip: ByteArray): LinkedHashMap<String, ByteArray> {
        val m = LinkedHashMap<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(zip)).use { z -> while (true) { val e = z.nextEntry ?: break; m[e.name] = z.readBytes() } }
        return m
    }
    private fun rezip(m: Map<String, ByteArray>): ByteArray {
        val o = ByteArrayOutputStream(); ZipOutputStream(o).use { z -> for ((n, b) in m) { z.putNextEntry(ZipEntry(n)); z.write(b); z.closeEntry() } }; return o.toByteArray()
    }

    @Test fun `QA_zip_buildIsDeterministicAndVerifies`() {
        val ev = listOf(qaEvent(1, now - 100)); val a = EvidenceZip.build(card(ev), ev)
        assertArrayEquals(a, EvidenceZip.build(card(ev), ev)); assertTrue(EvidenceZip.verify(a))
        assertEquals(listOf("card.json", "events.json", "manifest.json"), entries(a).keys.toList())
    }

    @Test fun `QA_zip_containedJsonIsValidWithNastyStrings`() {
        val ev = listOf(qaEvent(1, now - 100, triggers = listOf("q\"uote", "ओटीपी", "nl\n", "\u0000")))
        for ((_, b) in entries(EvidenceZip.build(card(ev), ev))) QAJson.assertValid(String(b, Charsets.UTF_8))
    }

    @Test fun `QA_zip_eventsJsonHasNoTextKey`() {
        assertFalse(EvidenceZip.eventsJson(listOf(qaEvent())).contains("\"text\""))
        assertEquals("[]", EvidenceZip.eventsJson(emptyList()))
    }

    @Test fun `QA_zip_tamperedEventsFailsVerify`() {
        val ev = listOf(qaEvent(1, now - 100)); val m = entries(EvidenceZip.build(card(ev), ev))
        m["events.json"] = "[]".toByteArray(); assertFalse(EvidenceZip.verify(rezip(m)))
    }

    @Test fun `QA_zip_tamperedManifestHashFailsVerify`() {
        val ev = listOf(qaEvent(1, now - 100)); val m = entries(EvidenceZip.build(card(ev), ev))
        val man = String(m["manifest.json"]!!); m["manifest.json"] = man.replaceFirst(Regex("[0-9a-f]{64}"), "0".repeat(64)).toByteArray()
        assertFalse(EvidenceZip.verify(rezip(m)))
    }

    @Test fun `QA_zip_extraOrMissingEntryFailsVerify`() {
        val ev = listOf(qaEvent(1, now - 100)); val m = entries(EvidenceZip.build(card(ev), ev))
        assertFalse(EvidenceZip.verify(rezip(m + ("../evil.txt" to "x".toByteArray()))))
        assertFalse(EvidenceZip.verify(rezip(m - "manifest.json")))
        assertFalse(EvidenceZip.verify(rezip(m - "card.json")))
    }

    @Test fun `QA_zip_garbageEmptyAndTruncatedFailVerifyWithoutThrowing`() {
        assertFalse(EvidenceZip.verify(ByteArray(0))); assertFalse(EvidenceZip.verify("not a zip at all".toByteArray()))
        val ev = listOf(qaEvent(1, now - 100)); val z = EvidenceZip.build(card(ev), ev)
        assertFalse(EvidenceZip.verify(z.copyOf(z.size / 2)))
    }

    @Test fun `QA_zip_emptyManifestListingFailsVerify`() {
        assertFalse(EvidenceZip.verify(rezip(mapOf("manifest.json" to "{\"sha256\":{}}".toByteArray()))))
    }

    @Test fun `QA_zip_sha256KnownVector`() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", EvidenceZip.sha256Hex("abc".toByteArray()))
    }
}
