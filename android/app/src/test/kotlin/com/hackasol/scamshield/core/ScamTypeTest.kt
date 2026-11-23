package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.graph.GraphContext
import com.hackasol.scamshield.core.graph.KnowledgeGraph
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ScamTypeTest {
    private fun parse(s: String) = LlmOutputParser.parse(s)!!

    @Test fun T1_2_parsesScamType() {
        assertEquals(ScamType.OTP, parse("""{"label":"SCAM","scam_type":"OTP","confidence":0.9,"reason":"x"}""").scamType)
        assertEquals(ScamType.DIGITAL_ARREST, parse("""{"label":"scam","scam_type":"digital_arrest","confidence":0.9}""").scamType)
        assertEquals(ScamType.KYC, parse("""{"label":"SUSPICIOUS","scam_type":"KYC","confidence":0.7}""").scamType)
        assertEquals(ScamType.OTHER, parse("""{"label":"SCAM","confidence":0.9,"reason":"x"}""").scamType)
        assertEquals(ScamType.OTHER, parse("""{"label":"SCAM","scam_type":"ROMANCE","confidence":0.9}""").scamType)
        assertEquals(ScamType.OTHER, parse("""{"label":"SUSPICIOUS","scam_type":"NONE","confidence":0.6}""").scamType)
        assertNull(parse("""{"label":"SAFE","scam_type":"NONE","confidence":0.9}""").scamType)
        assertNull(parse("""{"label":"SAFE","scam_type":"OTP","confidence":0.9}""").scamType)
        assertNull(parse("SAFE - normal chat").scamType)
        assertEquals(ScamType.OTHER, parse("SCAM").scamType)
        assertNull(ScamType.parse("NONE"))
        assertEquals(ScamType.COURIER_CUSTOMS, ScamType.parse(" courier-customs "))
    }

    @Test fun T1_2_ruleTypeFallback() {
        assertEquals(ScamType.OTP, RuleScorer.scamType("Sir aapke phone pe ek OTP aaya hoga, woh jaldi bata dijiye"))
        assertEquals(ScamType.DIGITAL_ARREST, RuleScorer.scamType("You are under digital arrest, do not tell anyone"))
        assertEquals(ScamType.COURIER_CUSTOMS, RuleScorer.scamType("Your parcel to Taiwan has drugs, press 1 to talk to customs officer"))
        assertEquals(ScamType.KYC, RuleScorer.scamType("Main SBI bank se bol raha hoon, aapka KYC pending hai"))
        assertEquals(ScamType.LOAN_APP, RuleScorer.scamType("Instant loan approved, pay the processing fee"))
        assertEquals(ScamType.OTHER, RuleScorer.scamType("Congratulations, you have won a lottery"))
        assertNull(RuleScorer.scamType("Beta khana kha liya? Kal shaam ko milte hain"))
        // existing outputs unchanged
        assertEquals(Label.SAFE, RuleScorer.score("Beta khana kha liya?").label)
    }

    private class Case(
        val id: String, val input: String, val output: String,
        val context: List<String> = emptyList(), val contextLabel: String = GemmaPrompt.CALL_CONTEXT_LABEL,
    )

    private val cases = listOf(
        Case("otp_en", "Sir, please share the OTP you just received to verify your account",
            """{"label":"SCAM","scam_type":"OTP","confidence":0.96,"reason":"Asks you to share OTP"}"""),
        Case("kyc_hi", "आपका केवाईसी अधूरा है, आज ही अपडेट करें",
            """{"label":"SUSPICIOUS","scam_type":"KYC","confidence":0.8,"reason":"Unsolicited KYC claim"}"""),
        Case("digital_arrest_hinglish", "Aap digital arrest mein hain, kisi ko mat batana",
            """{"label":"SCAM","scam_type":"DIGITAL_ARREST","confidence":0.99,"reason":"Digital arrest threat"}"""),
        Case("courier_customs_en", "Your parcel is held at customs, press 1 to speak to the officer",
            """{"label":"SCAM","scam_type":"COURIER_CUSTOMS","confidence":0.94,"reason":"Fake customs parcel story"}"""),
        Case("fake_qr_en", "Scan this QR code to receive your refund of Rs 5000",
            """{"label":"SCAM","scam_type":"FAKE_QR","confidence":0.9,"reason":"Refund via QR scan"}"""),
        Case("loan_app_hinglish", "Instant loan approved, app download karo aur processing fee bhejo",
            """{"label":"SCAM","scam_type":"LOAN_APP","confidence":0.91,"reason":"Loan app with upfront fee"}"""),
        Case("investment_en", "Join our VIP group for guaranteed 30% daily returns",
            """{"label":"SCAM","scam_type":"INVESTMENT","confidence":0.92,"reason":"Guaranteed returns claim"}"""),
        Case("job_en", "Earn Rs 5000 daily liking videos, pay a registration fee first",
            """{"label":"SCAM","scam_type":"JOB","confidence":0.9,"reason":"Job needs upfront fee"}"""),
        Case("mistaken_transfer_en", "Sorry, I sent Rs 10000 to your number by mistake, please send it back to example@upi",
            """{"label":"SCAM","scam_type":"MISTAKEN_TRANSFER","confidence":0.88,"reason":"Fake mistaken transfer"}"""),
        Case("other_en", "You have won a lottery, pay the tax to claim your prize",
            """{"label":"SCAM","scam_type":"OTHER","confidence":0.85,"reason":"Lottery claim"}"""),
        Case("safe_delivery", "Your order will be delivered tomorrow between 10 and 12",
            """{"label":"SAFE","scam_type":"NONE","confidence":0.9,"reason":"Routine delivery update"}"""),
        Case("edge_missing_type_scam", "Share the OTP sent to 98XXXXXX01",
            """{"label":"SCAM","confidence":0.9,"reason":"Asks OTP"}"""),
        Case("edge_missing_type_safe", "Are we meeting for lunch tomorrow?",
            """{"label":"SAFE","confidence":0.95,"reason":"Normal chat"}"""),
        Case("edge_unknown_type", "Send your photo to example@upi to join the dating club",
            """{"label":"SCAM","scam_type":"ROMANCE","confidence":0.8,"reason":"Dating club fee"}"""),
        Case("edge_lowercase", "Your account will be blocked, update KYC now",
            """{"label":"scam","scam_type":"digital_arrest","confidence":0.88,"reason":"lower case output"}"""),
        Case("edge_fenced_percent", "Bank se bol raha hoon, KYC update karo",
            "Sure!\n```json\n{ \"label\": \"suspicious\", \"scam_type\": \"KYC\", \"confidence\": 70%, \"reason\": \"KYC claim\" }\n```"),
        Case("edge_safe_with_type", "Dinner at 8?",
            """{"label":"SAFE","scam_type":"OTP","confidence":0.9,"reason":"Model slip"}"""),
        Case("edge_quote_in_input", "He said \"share the OTP\" on the call",
            """{"label":"SCAM","scam_type":"OTP","confidence":0.7,"reason":"Quoted OTP request"}"""),
        Case("edge_long_input", "ab ".repeat(150) + "tail beyond the 300 character cut",
            """{"label":"SAFE","scam_type":"NONE","confidence":0.6,"reason":"Gibberish"}"""),
        // Graph context (T5.3): label "Known context"; ML ports must reproduce `<label>: "a" | "b"`.
        Case("graph_ctx_no_order", "Your order is held at customs, pay the fee at the link to release it",
            """{"label":"SCAM","scam_type":"COURIER_CUSTOMS","confidence":0.9,"reason":"No order on record, fee demand"}""",
            listOf("No ORDER event from examplecourier since install", GraphContext.SENDER_FIRST_TEXT), GraphContext.LABEL),
        Case("graph_ctx_cold_start", "Your bill is overdue, pay now or the service will be cut",
            """{"label":"SUSPICIOUS","scam_type":"OTHER","confidence":0.6,"reason":"Cannot confirm this bill"}""",
            listOf(KnowledgeGraph.COLD_START_TEXT), GraphContext.LABEL),
    )

    private fun esc(s: String): String = buildString {
        for (c in s) when {
            c == '"' -> append("\\\"")
            c == '\\' -> append("\\\\")
            c == '\n' -> append("\\n")
            c == '\r' -> append("\\r")
            c == '\t' -> append("\\t")
            c < ' ' -> append("\\u%04x".format(c.code))
            else -> append(c)
        }
    }
    private fun q(s: String) = "\"${esc(s)}\""

    @Test fun T1_2_goldenWritten() {
        val sb = StringBuilder("[\n")
        cases.forEachIndexed { i, c ->
            val r = LlmOutputParser.parse(c.output)
            assertNotNull(c.id, r)
            r!!
            val reasons = if (r.reason.isEmpty()) "[]" else "[${q(r.reason)}]"
            sb.append("  {\n")
                .append("    \"id\": ").append(q(c.id)).append(",\n")
                .append("    \"input_text\": ").append(q(c.input)).append(",\n")
                .append(if (c.context.isEmpty()) "" else "    \"context\": [${c.context.joinToString(", ") { q(it) }}],\n    \"context_label\": ${q(c.contextLabel)},\n")
                .append("    \"prompt\": ").append(q(GemmaPrompt.build(c.input, c.context, c.contextLabel))).append(",\n")
                .append("    \"model_output\": ").append(q(c.output)).append(",\n")
                .append("    \"parsed\": {\"label\": ").append(q(r.label.name))
                .append(", \"confidence\": ").append(r.confidence.toString())
                .append(", \"scam_type\": ").append(r.scamType?.let { q(it.name) } ?: "null")
                .append(", \"reasons\": ").append(reasons).append("}\n")
                .append("  }").append(if (i < cases.size - 1) ",\n" else "\n")
        }
        sb.append("]\n")
        val f = File("../../data/golden/prompt_golden.json")
        f.parentFile?.mkdirs()
        f.writeText(sb.toString(), Charsets.UTF_8)
        assertTrue(f.length() > 0)
        assertTrue(cases.size >= 8)
        assertEquals(ScamType.values().toSet(), cases.mapNotNull { LlmOutputParser.parse(it.output)?.scamType }.toSet())
    }
}
