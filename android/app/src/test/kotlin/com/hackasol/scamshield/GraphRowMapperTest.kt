package com.hackasol.scamshield

import com.hackasol.scamshield.core.graph.EventType
import com.hackasol.scamshield.core.graph.GraphEvent
import com.hackasol.scamshield.core.graph.SenderRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GraphRowMapperTest {
    @Test fun T5_3_rowRoundTrip() {
        val e = GraphEvent("examplebank", EventType.CREDIT, 1_700_000_000_000L, "VM-EXMPBK")
        val er = GraphRowMapper.eventToRow(e)
        assertEquals(setOf("brand", "type", "ts_ms", "sender"), er.keys)   // no column for message text
        assertEquals(e, GraphRowMapper.eventFromRow(er))

        val s = SenderRecord("VM-EXMPBK", 10L, 20L, 3, true)
        assertEquals(s, GraphRowMapper.senderFromRow(GraphRowMapper.senderToRow(s)))
        val plain = SenderRecord("9800000001", 1L, 1L, 1, false)
        assertEquals(plain, GraphRowMapper.senderFromRow(GraphRowMapper.senderToRow(plain)))

        assertEquals("9800000001", GraphRowMapper.numberFromRow(GraphRowMapper.numberToRow("9800000001")))
        assertEquals("example@upi", GraphRowMapper.upiFromRow(GraphRowMapper.upiToRow("example@upi")))

        // Unusable rows are dropped, not thrown.
        assertNull(GraphRowMapper.eventFromRow(er + ("type" to "REFUND")))
        assertNull(GraphRowMapper.eventFromRow(er - "ts_ms"))
        assertNull(GraphRowMapper.senderFromRow(mapOf("sender" to "X")))
    }
}
