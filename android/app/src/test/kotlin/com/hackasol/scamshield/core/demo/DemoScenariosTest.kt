package com.hackasol.scamshield.core.demo

import com.hackasol.scamshield.core.FusedResult
import com.hackasol.scamshield.core.Fusion
import com.hackasol.scamshield.core.InMemoryVerdictLog
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.LlmResult
import com.hackasol.scamshield.core.ScamType
import com.hackasol.scamshield.core.TrendExport
import com.hackasol.scamshield.core.graph.ContextFlag
import com.hackasol.scamshield.core.graph.ContextRules
import com.hackasol.scamshield.core.graph.FlagKind
import com.hackasol.scamshield.core.graph.GraphContext
import com.hackasol.scamshield.core.graph.KnowledgeGraph
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DemoScenariosTest {
    private val t0 = 1_700_000_000_000L

    private fun run(id: String, classify: DemoClassify? = null, graph: KnowledgeGraph = KnowledgeGraph(), log: InMemoryVerdictLog = InMemoryVerdictLog()) =
        runBlocking { DemoRunner(graph, log, classify, clock = { t0 }).run(DemoScenarios.byId(id)!!) }

    @Test fun T8_1_mistakenTransferA_fakeCreditFlagged() {
        val r = run("mistaken_a")
        // The SMS alone looks harmless; the follow-up call is what the context layer catches.
        assertEquals(Label.SAFE, r.steps[0].fused.label)
        val call = r.steps[1]
        assertEquals(listOf(FlagKind.FAKE_CREDIT), call.actualFlags)
        assertEquals(Label.SCAM, call.fused.label)   // fake credit + return request: SCAM, so the heads-up alert fires
        assertNotNull(call.alert)
        assertEquals(ContextRules.MISTAKEN_A_TEXT, call.fused.reason)
        assertEquals(ScamType.MISTAKEN_TRANSFER, call.fused.scamType)
        assertEquals(listOf("FAKE_CREDIT"), call.fused.raisedBy)
        assertNull(call.gemma)
        assertEquals("rules", r.engineUsed)
        assertTrue(r.pass)
        // Same script with a model that says SUSPICIOUS: gemma trace is filled in and the flag is still present.
        val g = run("mistaken_a", { _, _, _, _ -> LlmResult(Label.SUSPICIOUS, 0.7, "fake model", ScamType.MISTAKEN_TRANSFER) })
        assertEquals("gemma", g.engineUsed)
        assertNotNull(g.steps[1].gemma)
        assertEquals(listOf(FlagKind.FAKE_CREDIT), g.steps[1].actualFlags)
    }

    @Test fun T8_1_genuineOtpSafe() {
        val r = run("genuine_otp")
        val genuine = r.steps[0]
        assertEquals(Label.SAFE, genuine.fused.label)
        assertTrue(genuine.actualFlags.isEmpty())
        assertNull(genuine.alert)
        assertTrue(genuine.pass)
        // Contrast: a caller asking for the OTP is a SCAM and raises a [DEMO]-prefixed alert.
        val ask = r.steps[1]
        assertEquals(Label.SCAM, ask.fused.label)
        assertTrue(ask.alert!!.title.startsWith("[DEMO] "))
        assertTrue(ask.alert.reportAction)
    }

    @Test fun T8_1_mistakenTransferB_returnWarningLeads() {
        val call = run("mistaken_b").steps[1]
        assertEquals(listOf(FlagKind.RETURN_VIA_BANK_ONLY), call.actualFlags)
        assertEquals(ContextRules.MISTAKEN_B_TEXT, call.fused.reason)
    }

    @Test fun T8_1_demoNamespaceIsolated() {
        val realLog = InMemoryVerdictLog()
        val realGraph = KnowledgeGraph()
        val demoLog = InMemoryVerdictLog()
        val demoGraph = KnowledgeGraph()
        val runner = DemoRunner(demoGraph, demoLog, null, clock = { t0 })   // the real log/graph are never handed to the runner
        runBlocking { DemoScenarios.ALL.forEach { runner.run(it) } }
        assertTrue(realLog.since(0).isEmpty())
        assertTrue(realGraph.isEmpty)
        assertTrue(TrendExport.rows(realLog.since(0), "district-a").isEmpty())
        // The demo stores did receive the data (so the assertions above are meaningful).
        assertTrue(demoLog.since(0).isNotEmpty())
        assertTrue(!demoGraph.isEmpty)
        assertTrue(TrendExport.rows(demoLog.since(0), "district-a").isNotEmpty())
    }

    @Test fun T8_1_knownContextReachesClassifier() {
        val seen = mutableListOf<Triple<String, List<String>, String>>()
        run("delivery_genuine", { text, _, ctx, label -> seen += Triple(text, ctx, label); LlmResult(Label.SAFE, 0.9, "fake") })
        val ofd = seen.first { it.first.contains("out for delivery") }
        assertEquals(GraphContext.LABEL, ofd.third)
        assertTrue(ofd.second.single().startsWith("Last ORDER event from delhivery"))
    }

    @Test fun T8_1_allScenariosMeetExpectations() {
        assertTrue(DemoScenarios.ALL.size >= 10)
        assertEquals(DemoScenarios.ALL.size, DemoScenarios.ALL.map { it.id }.toSet().size)
        val icons = setOf("sms", "call", "local_shipping", "qr_code", "family_restroom", "verified", "gavel", "link")
        for (s in DemoScenarios.ALL) {
            assertTrue("icon ${s.icon} of ${s.id}", s.icon in icons)
            assertTrue(s.steps.isNotEmpty())
            val r = run(s.id)   // rules mode, fresh graph and log per scenario
            val bad = r.steps.filter { !it.pass }.joinToString { "[#${it.index + 1} got ${it.fused.label} ${it.actualFlags}, want ${it.expectedLabel} ${it.expectedFlags}]" }
            assertEquals("${s.id}: ${r.note} $bad", s.steps.size, r.steps.size)
            assertTrue("${s.id} failed: $bad ${r.note}", r.pass)
        }
    }

    @Test fun T8_1_fakeCreditReturnRaisesOnlyWithFlag() {
        fun fr(l: Label) = FusedResult(l, 0.5, null, emptyList(), "rules-only", "r")
        val fake = listOf(ContextFlag(FlagKind.FAKE_CREDIT, "no money arrived"))
        assertEquals(Label.SCAM, Fusion.raiseForFakeCreditReturn(fr(Label.SUSPICIOUS), fake).label)
        assertEquals(Label.SAFE, Fusion.raiseForFakeCreditReturn(fr(Label.SAFE), fake).label)
        assertEquals(Label.SUSPICIOUS, Fusion.raiseForFakeCreditReturn(fr(Label.SUSPICIOUS), emptyList()).label)
        val other = listOf(ContextFlag(FlagKind.RETURN_VIA_BANK_ONLY, "b"), ContextFlag(FlagKind.NON_DLT_SENDER, "n"))
        assertEquals(Label.SUSPICIOUS, Fusion.raiseForFakeCreditReturn(fr(Label.SUSPICIOUS), other).label)
    }
}
