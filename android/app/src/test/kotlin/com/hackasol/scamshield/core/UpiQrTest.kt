package com.hackasol.scamshield.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UpiQrTest {
    @Test fun T4_1_parsesPaTn() {
        val parsed = UpiQr.parse("UPI://PAY?PA=shop%40psp&PN=Priya+Stores&tn=Order%2012&cu=INR")!!
        assertEquals("shop@psp", parsed.payeeAddress)
        assertEquals("Priya Stores", parsed.payeeName)
        assertEquals("Order 12", parsed.transactionNote)
        assertEquals("INR", parsed.currency)
        assertFalse(parsed.isCollectRequest)
    }

    @Test fun T4_1_nameMismatch() {
        val parsed = UpiQr.parse("upi://pay?pa=shop%40psp&pn=Priya%20Stores")!!
        assertFalse(parsed.nameMismatch("PRIYA stores!"))
        assertTrue(parsed.nameMismatch("Priya Store"))
        assertEquals(UpiQr.NAME_MISMATCH_WARNING, UpiQr.NAME_MISMATCH_WARNING)
    }

    @Test fun T4_1_payFraming() {
        val withAmount = UpiQr.parse("upi://pay?pa=shop%40psp&pn=Priya+Stores&am=125.50")!!
        assertEquals("You will PAY Rs 125.50 to Priya Stores", withAmount.payFraming())
        val withoutAmount = UpiQr.parse("upi://pay?pa=shop%40psp&pn=Priya+Stores")!!
        assertEquals("You will PAY money to Priya Stores", withoutAmount.payFraming())
        val request = UpiQr.parse("upi://pay?pa=shop%40psp&pn=Priya&tn=Please%20collect%20payment")!!
        assertTrue(request.isCollectRequest)
        assertEquals(UpiQr.COLLECT_REQUEST_WARNING, UpiQr.COLLECT_REQUEST_WARNING)
    }

    @Test fun T4_1_rejectsMalformed() {
        assertNull(UpiQr.parse("https://pay?pa=shop%40psp"))
        assertNull(UpiQr.parse("upi://pay?pa=missing-at"))
        assertNull(UpiQr.parse("upi://pay?pa=shop%40psp&am=12abc"))
        assertNull(UpiQr.parse("upi://pay?pa=shop%40psp&pn=%ZZ"))
    }

    @Test fun T4_1_amountAndRiskyVpa() {
        val q = UpiQr.parse("upi://pay?pa=refund.helpdesk@oksbi&pn=Priya Stores&am=4999")!!
        assertEquals("4999", q.amount)
        assertEquals("Priya Stores", q.payeeName)
        assertEquals("₹4,999", q.displayAmount())
        assertEquals("You will PAY ₹4,999 to Priya Stores", q.payFramingEn())
        assertEquals("आप Priya Stores को ₹4,999 भेजेंगे", q.payFramingHi())
        assertTrue(q.hasRiskyPayee())
        val risk = Pipeline.upiRisk(q, null)!!
        assertEquals(Label.SUSPICIOUS, risk.label)
        assertTrue(UpiQr.RISKY_PAYEE_TRIGGER in risk.triggers)
        assertFalse(UpiQr.parse("upi://pay?pa=shop%40psp&pn=Priya")!!.hasRiskyPayee())
        assertEquals("₹1,00,000.50", UpiQr("a@b", amount = "100000.50").displayAmount())
        assertEquals("₹5", UpiQr("a@b", amount = "5").displayAmount())
    }
}
