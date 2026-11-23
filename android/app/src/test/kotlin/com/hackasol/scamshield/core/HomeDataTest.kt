package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.graph.EventType
import com.hackasol.scamshield.core.graph.GraphEvent
import com.hackasol.scamshield.core.graph.GraphSnapshot
import com.hackasol.scamshield.core.graph.SenderRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeDataTest {
    private val now = 1_800_000_000_000L
    private val h = 3_600_000L

    private fun ev(id: Long, ageH: Long, label: Label, type: ScamType? = ScamType.KYC) =
        VerdictEvent(id, now - ageH * h, Source.SMS, label, 0.9, type, listOf("t$id"), "rules-only")

    @Test fun HOME_graphSummary_emptyGraphIsFlaggedEmpty() {
        val m = GraphSummary.build(GraphSnapshot.EMPTY)
        assertTrue(m["empty"] as Boolean)
        assertTrue((m["brands"] as List<*>).isEmpty())
    }

    @Test fun HOME_graphSummary_groupsBrandsNewestFirstAndCountsContactsOnly() {
        val snap = GraphSnapshot(
            ingested = 5,
            senders = listOf(
                SenderRecord("AX-EXMPBK", now - 9 * h, now - h, 4, true),
                SenderRecord("+919999900000", now - 2 * h, now - 2 * h, 1, false),
            ),
            numbers = listOf("9999900000"), upiIds = listOf("a@upi", "b@upi"),
            events = listOf(
                GraphEvent("examplebank", EventType.CREDIT, now - 5 * h, "AX-EXMPBK"),
                GraphEvent("examplebank", EventType.CREDIT, now - h, "AX-EXMPBK"),
                GraphEvent("shopco", EventType.ORDER, now - 3 * h, "AX-SHOPCO"),
            ),
        )
        val m = GraphSummary.build(snap)
        assertFalse(m["empty"] as Boolean)
        val brands = m["brands"] as List<*>
        assertEquals(listOf("examplebank", "shopco"), brands.map { (it as Map<*, *>)["brand"] })
        assertEquals(2, (brands[0] as Map<*, *>)["count"])
        assertEquals(1, ((brands[1] as Map<*, *>)["types"] as Map<*, *>)["ORDER"])
        assertEquals(listOf(now - h, now - 3 * h, now - 5 * h), (m["recent"] as List<*>).map { (it as Map<*, *>)["tsMs"] })
        assertEquals("AX-EXMPBK", ((m["senders"] as List<*>)[0] as Map<*, *>)["sender"])
        assertEquals(1, m["numbers"])
        assertEquals(2, m["upiIds"])
        assertFalse("raw values must not be exposed", m.toString().contains("a@upi"))
    }

    @Test fun HOME_senders_neverExposePhoneNumbers() {
        val raw = listOf("9999900000", "+919999900001", "+91 99999 00002", "98765-43210", "0091 9999 900003", "12345", "567676", "a@upi", "AB-9999900")
        val snap = GraphSnapshot(
            ingested = 20,
            senders = listOf(SenderRecord("VM-SBIINB", now - h, now, 3, true)) + raw.map { SenderRecord(it, now - h, now, 2, false) },
            numbers = emptyList(), upiIds = emptyList(), events = emptyList(),
        )
        val m = GraphSummary.build(snap)
        assertEquals(listOf("VM-SBIINB"), (m["senders"] as List<*>).map { (it as Map<*, *>)["sender"] })
        assertEquals(raw.size, m["personalSenders"])
        assertEquals(raw.size * 2, m["personalMessages"])
        val out = m.toString()
        raw.forEach { assertFalse("leaked $it", out.contains(it)) }
        assertFalse(Regex("\\d{6}").containsMatchIn(out.replace(now.toString(), "").replace((now - h).toString(), "")))
    }

    @Test fun HOME_evidenceSelect_defaultsToLast24hFlaggedOnlyOldestFirst() {
        val all = listOf(ev(1, 30, Label.SCAM), ev(2, 5, Label.SAFE), ev(3, 4, Label.SUSPICIOUS), ev(4, 1, Label.SCAM))
        assertEquals(listOf(3L, 4L), EvidenceMake.select(all, null, now).map { it.id })
    }

    @Test fun HOME_evidenceSelect_singleEventKeepsOldAlertButNeverSafe() {
        val all = listOf(ev(1, 300, Label.SCAM), ev(2, 5, Label.SAFE))
        assertEquals(listOf(1L), EvidenceMake.select(all, 1L, now).map { it.id })
        assertTrue(EvidenceMake.select(all, 2L, now).isEmpty())
        assertTrue(EvidenceMake.select(all, 99L, now).isEmpty())
    }

    @Test fun HOME_evidenceCard_packHoldsOldSingleEventAndZipVerifies() {
        val old = ev(1, 300, Label.SCAM)
        val card = EvidenceMake.card(listOf(old), now)
        assertEquals(1, card.pack.evidence.size)
        assertTrue(EvidenceZip.verify(EvidenceZip.build(card, listOf(old))))
    }
}
