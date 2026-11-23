package com.hackasol.scamshield

import com.hackasol.scamshield.core.graph.EventType
import com.hackasol.scamshield.core.graph.GraphEvent
import com.hackasol.scamshield.core.graph.SenderRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GraphRowMapperTest {
    @Test fun R3_KB_rowMapper_amountTrustAndAlertRefRoundTrip() {
        val e = GraphEvent("hdfcbank", EventType.DEBIT, 5L, "AX-HDFCBK", 1500.5)
        assertEquals(e, GraphRowMapper.eventFromRow(GraphRowMapper.eventToRow(e)))
        assertEquals(1500.5, GraphRowMapper.eventFromRow(GraphRowMapper.eventToRow(e))!!.amountRupees!!, 0.0)
        // SQLite hands an INTEGER column back as Long: a whole-rupee amount stored as 500 reads back as 500.0.
        assertEquals(500.0, GraphRowMapper.eventFromRow(GraphRowMapper.eventToRow(e) + ("amount" to 500L))!!.amountRupees!!, 0.0)
        assertNull(GraphRowMapper.eventFromRow(GraphRowMapper.eventToRow(e) + ("amount" to null))!!.amountRupees)
        // v1 rows have no amount column at all.
        assertNull(GraphRowMapper.eventFromRow(GraphRowMapper.eventToRow(e) - "amount")!!.amountRupees)

        val t = com.hackasol.scamshield.core.graph.TrustRecord(com.hackasol.scamshield.core.graph.EntityKind.UPI, "example@okaxis", com.hackasol.scamshield.core.graph.TrustStatus.REPORTED, 9L)
        assertEquals(t, GraphRowMapper.trustFromRow(GraphRowMapper.trustToRow(t)))
        assertNull(GraphRowMapper.trustFromRow(GraphRowMapper.trustToRow(t) + ("status" to "BOGUS")))

        val r = com.hackasol.scamshield.core.graph.AlertRef(7L, "wa:Someone", listOf("9800000010", "9800000011"), listOf("example@okaxis"))
        val row = GraphRowMapper.alertRefToRow(r)
        assertEquals(setOf("ts_ms", "sender", "numbers", "upi_ids"), row.keys)
        assertEquals(r, GraphRowMapper.alertRefFromRow(row))
        assertEquals(com.hackasol.scamshield.core.graph.AlertRef(1L, "", emptyList(), emptyList()),
            GraphRowMapper.alertRefFromRow(GraphRowMapper.alertRefToRow(com.hackasol.scamshield.core.graph.AlertRef(1L, "", emptyList(), emptyList()))))

        assertEquals(null, GraphRowMapper.lastSeenFromRow(mapOf("last_seen" to 0L)))   // migrated default = unknown
        assertEquals(42L, GraphRowMapper.lastSeenFromRow(mapOf("last_seen" to 42L)))
    }

    @Test fun T5_3_rowRoundTrip() {
        val e = GraphEvent("examplebank", EventType.CREDIT, 1_700_000_000_000L, "VM-EXMPBK")
        val er = GraphRowMapper.eventToRow(e)
        assertEquals(setOf("brand", "type", "ts_ms", "sender", "amount"), er.keys)   // no column for message text
        assertEquals(e, GraphRowMapper.eventFromRow(er))
        assertNull(GraphRowMapper.eventFromRow(er)!!.amountRupees)

        val s = SenderRecord("VM-EXMPBK", 10L, 20L, 3, true)
        assertEquals(s, GraphRowMapper.senderFromRow(GraphRowMapper.senderToRow(s)))
        val plain = SenderRecord("9800000001", 1L, 1L, 1, false)
        assertEquals(plain, GraphRowMapper.senderFromRow(GraphRowMapper.senderToRow(plain)))

        assertEquals("9800000001", GraphRowMapper.numberFromRow(GraphRowMapper.numberToRow("9800000001")))
        assertEquals("example@upi", GraphRowMapper.upiFromRow(GraphRowMapper.upiToRow("example@upi")))

        // Unusable rows are dropped, not thrown.
        assertNull(GraphRowMapper.eventFromRow(er + ("type" to "BOGUS")))
        assertNull(GraphRowMapper.eventFromRow(er - "ts_ms"))
        assertNull(GraphRowMapper.senderFromRow(mapOf("sender" to "X")))
    }
}
