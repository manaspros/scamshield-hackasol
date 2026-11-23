package com.hackasol.scamshield

import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.FusedResult
import com.hackasol.scamshield.core.Fusion
import com.hackasol.scamshield.core.FusionWeights
import com.hackasol.scamshield.core.GemmaPrompt
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.LlmResult
import com.hackasol.scamshield.core.NotificationMapper
import com.hackasol.scamshield.core.RuleScorer
import com.hackasol.scamshield.core.Verdict
import com.hackasol.scamshield.core.graph.ContextFlag
import com.hackasol.scamshield.core.graph.FlagKind
import com.hackasol.scamshield.core.graph.GraphContext
import com.hackasol.scamshield.core.graph.KnowledgeGraph
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GraphWiringTest {
    private val sms = "com.google.android.apps.messaging"
    private val now = 10_000_000_000L
    private val noEvent = ContextFlag(FlagKind.NO_MATCHING_EVENT, "No bill or order from examplebank on record, but this message claims one.")

    /** Same composition TextApi.classifyUnlogged uses, with a fake LLM instead of Gemma. */
    private fun fuse(llm: LlmResult, text: String, flags: List<ContextFlag>): FusedResult =
        Fusion.raiseForContext(Fusion.fuse(llm, RuleScorer.score(text), RuleScorer.scamType(text)), flags)

    private fun info(text: String, title: String, ts: Long) = NotificationInfo(sms, title, text, false, false, ts)

    private fun rig(captured: MutableList<ClassifyRequest>) = KnowledgeGraph().let { g ->
        g to ListenerWiring(
            NotificationMapper(),
            { t, s -> Verdict(t, Label.SAFE, 0.9, "r", emptyList(), "rules-only", 0, s) },
            { _, _ -> },
            g,
            { r -> captured += r; Verdict(r.text, Label.SAFE, 0.9, "r", emptyList(), "gemma+rules", 0, r.source) },
        )
    }

    @Test fun T5_3_ruleHitNeverDowngrades() {
        val text = "hello there friend"   // neutral: RuleScorer adds nothing, so only context can raise
        // SAFE + no-bill-event flag -> SUSPICIOUS; the context reason leads the triggers and is the reason.
        val up = fuse(LlmResult(Label.SAFE, 0.9, "Normal"), text, listOf(noEvent))
        assertEquals(Label.SUSPICIOUS, up.label)
        assertEquals(noEvent.reason, up.triggers.first())
        assertEquals(noEvent.reason, up.reason)
        assertTrue(up.confidence >= FusionWeights.CONTEXT_RAISED_CONF)
        // SCAM + no flags stays SCAM, unchanged.
        val scam = LlmResult(Label.SCAM, 0.9, "OTP ask")
        val base = Fusion.fuse(scam, RuleScorer.score(text), RuleScorer.scamType(text))
        assertEquals(base, fuse(scam, text, emptyList()))
        // SCAM is never lowered, whatever the flags; SAFE with only weak flags is not raised.
        val weak = listOf(ContextFlag(FlagKind.NON_DLT_SENDER, "n"), ContextFlag(FlagKind.LINK_NOT_ALLOWLISTED, "l"))
        assertEquals(Label.SCAM, fuse(scam, text, weak + noEvent).label)
        assertEquals(Label.SAFE, fuse(LlmResult(Label.SAFE, 0.9, "Normal"), text, weak).label)
        // SUSPICIOUS -> SCAM needs strong combined evidence; one flag is not enough.
        val susp = LlmResult(Label.SUSPICIOUS, 0.7, "claim")
        assertEquals(Label.SUSPICIOUS, fuse(susp, text, listOf(noEvent)).label)
        assertEquals(Label.SCAM, fuse(susp, text, listOf(noEvent, ContextFlag(FlagKind.FAKE_CREDIT, "f"))).label)
    }

    @Test fun T5_3_contextReachesPrompt() = runBlocking {
        val captured = mutableListOf<ClassifyRequest>()
        val (g, w) = rig(captured)
        // 1) empty graph: cold-start line, and no NO_MATCHING_EVENT flag (would be false certainty).
        w.onPosted(info("Your ExampleBank bill is overdue, pay at example.com", "VM-EXMPBK", now))
        assertEquals(listOf(KnowledgeGraph.COLD_START_TEXT), captured[0].context)
        assertEquals(GraphContext.LABEL, captured[0].contextLabel)
        assertFalse(captured[0].contextFlags.any { it.kind == FlagKind.NO_MATCHING_EVENT })
        // Ingest ran after classify: graph is now non-empty.
        assertFalse(g.isEmpty)
        // 2) warm graph, a claim with no event on record from a first-time sender.
        w.onPosted(info("Your ExampleCourier parcel order is held, pay the fee now", "9800000001", now + 1000))
        val r = captured[1]
        assertEquals(listOf("No ORDER event from examplecourier since install", GraphContext.SENDER_FIRST_TEXT), r.context)
        assertTrue(r.contextFlags.any { it.kind == FlagKind.NO_MATCHING_EVENT })
        assertTrue(r.context.all { it.length <= GraphContext.MAX_ITEM_CHARS && !it.contains("pay the fee") })
        // The prompt renders it under the new label; the default label output is unchanged.
        val p = GemmaPrompt.build(r.text, r.context, r.contextLabel)
        assertTrue(p.contains("\nKnown context: \"No ORDER event from examplecourier since install\" | \"Sender history: first message from this sender\"\nSTATEMENT: "))
        assertTrue(GemmaPrompt.build("x", listOf("a", "b")).endsWith("\nEarlier in this call: \"a\" | \"b\"\nSTATEMENT: \"x\"\n"))
        // 3) a genuine DLT event report is not flagged as having no predecessor, and later claims see it.
        w.onPosted(info("Your ExampleBank bill is generated, due date 5th", "VM-EXMPBK", now + 2000))
        assertFalse(captured[2].contextFlags.any { it.kind == FlagKind.NO_MATCHING_EVENT })
        w.onPosted(info("ExampleBank: your bill payment is pending, pay now", "VM-EXMPBK", now + 3000))
        assertTrue(captured[3].context.any { it.startsWith("Last BILL event from examplebank") })
        assertFalse(captured[3].contextFlags.any { it.kind == FlagKind.NO_MATCHING_EVENT })
        // WhatsApp title is a contact name: never judged as a sender header.
        captured.clear()
        w.onPosted(NotificationInfo("com.whatsapp", "Contact Name", "Hey are we still meeting for dinner today", false, false, now + 4000))
        assertFalse(captured.single().contextFlags.any { it.kind == FlagKind.NON_DLT_SENDER })
    }
}
