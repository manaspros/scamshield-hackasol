package com.hackasol.scamshield

import com.hackasol.scamshield.core.CallContext
import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.DataReset
import com.hackasol.scamshield.core.InMemoryVerdictLog
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.NotificationMapper
import com.hackasol.scamshield.core.Pipeline
import com.hackasol.scamshield.core.ScamType
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.Verdict
import com.hackasol.scamshield.core.VerdictEvent
import com.hackasol.scamshield.core.graph.AlertRef
import com.hackasol.scamshield.core.graph.EntityKind
import com.hackasol.scamshield.core.graph.EventType
import com.hackasol.scamshield.core.graph.FlagKind
import com.hackasol.scamshield.core.graph.GraphSnapshot
import com.hackasol.scamshield.core.graph.GraphStore
import com.hackasol.scamshield.core.graph.IngestDelta
import com.hackasol.scamshield.core.graph.KnowledgeGraph
import com.hackasol.scamshield.core.graph.PersistentKnowledgeGraph
import com.hackasol.scamshield.core.graph.TrustStatus
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Round 3 KB wiring: poisoning guard, newest-message pick, trust-quiet dispatch, call context, delete-my-data. Synthetic data only. */
class R3KbWiringTest {
    private val sms = "com.google.android.apps.messaging"
    private val orderText = "Your Amazon order has been confirmed and will arrive tomorrow"
    private val now = 10_000_000_000L

    private class Rig(val graph: KnowledgeGraph, label: () -> Label, loggedTs: Long = 777L) {
        val dispatched = mutableListOf<Verdict>()
        val wiring = ListenerWiring(
            NotificationMapper(),
            { t, s -> Verdict(t, Label.SAFE, 0.9, "r", emptyList(), "rules", 0, s) },
            { v, _ -> dispatched += v },
            graph,
            classifyLogged = { r: ClassifyRequest -> Verdict(r.text, label(), 0.9, "r", emptyList(), "rules", 0, r.source) to loggedTs },
        )
    }

    private fun smsInfo(text: String, title: String, post: Long = now, msgTs: Long = post, pkg: String = sms) =
        NotificationInfo(pkg, title, text, false, false, post, null, msgTs)

    @Test fun R3_KB_poison_scamVerdictDltOrderMessageCreatesNoOrderEvent() = runBlocking {
        val g = KnowledgeGraph()
        Rig(g, { Label.SCAM }).wiring.onPosted(smsInfo(orderText, "AX-AMAZON"))
        assertTrue(g.snapshot().events.isEmpty())
        assertFalse(g.knownSender("AX-AMAZON"))
        assertTrue(g.isEmpty)   // an untrusted ingest writes nothing, not even the cold-start counter
    }

    @Test fun R3_KB_poison_safeVerdictDltOrderMessageCreatesOrderEvent() = runBlocking {
        val g = KnowledgeGraph()
        Rig(g, { Label.SAFE }).wiring.onPosted(smsInfo(orderText, "AX-AMAZON"))
        assertEquals(listOf(EventType.ORDER), g.snapshot().events.map { it.type })
    }

    @Test fun R3_KB_poison_classifyThrowsMeansNoIngest() {
        val g = KnowledgeGraph()
        val w = ListenerWiring(NotificationMapper(), { _, _ -> error("x") }, { _, _ -> }, g, classifyLogged = { _ -> error("boom") })
        try { runBlocking { w.onPosted(smsInfo(orderText, "AX-AMAZON")) } } catch (_: IllegalStateException) {}
        assertTrue(g.isEmpty)
    }

    @Test fun R3_KB_dedupe_sameMessageTwiceCreatesOneEvent() = runBlocking {
        val g = KnowledgeGraph()
        val rig = Rig(g, { Label.SAFE })
        // Reposted past the mapper's 60 s window, same message time: the graph itself must not double-count it.
        rig.wiring.onPosted(smsInfo(orderText, "AX-AMAZON", post = now, msgTs = now - 5_000))
        rig.wiring.onPosted(smsInfo(orderText, "AX-AMAZON", post = now + 120_000, msgTs = now - 5_000))
        assertEquals(1, g.snapshot().events.size)
    }

    @Test fun R3_KB_alertRef_nonSafeRemembersEntitiesUnderLoggedTs_safeDoesNot() = runBlocking {
        val g = KnowledgeGraph()
        Rig(g, { Label.SCAM }, loggedTs = 4242L).wiring.onPosted(smsInfo("Send refund to example@okaxis or call 9800000010 now please", "9800000099"))
        val ref = g.alertRef(4242L)!!
        assertEquals("9800000099", ref.sender)
        assertTrue("9800000010" in ref.numbers)
        assertEquals(listOf("example@okaxis"), ref.upiIds)
        assertTrue(g.feedback(4242L, scam = true, nowMs = now))
        assertTrue(g.isReported(EntityKind.SENDER, "9800000099"))
        assertTrue(g.isReported(EntityKind.UPI, "example@okaxis"))
        val g2 = KnowledgeGraph()
        Rig(g2, { Label.SAFE }, loggedTs = 5L).wiring.onPosted(smsInfo("Your ExampleBank statement is ready to view in the app", "VM-EXMPBK"))
        assertNull(g2.alertRef(5L))
    }

    @Test fun R3_KB_alertRef_whatsappKeyIsPrefixedAndNeverIngestedAsSender() = runBlocking {
        val g = KnowledgeGraph()
        val rig = Rig(g, { Label.SUSPICIOUS }, loggedTs = 9L)
        rig.wiring.onPosted(smsInfo("Hey please send the money to my new account today", "Contact Name", pkg = "com.whatsapp"))
        assertEquals("wa:Contact Name", g.alertRef(9L)!!.sender)
        assertTrue(g.snapshot().senders.isEmpty())
        g.feedback(9L, scam = false, nowMs = now)
        assertTrue(g.isTrusted("wa:Contact Name"))
    }

    @Test fun R3_KB_newestMessage_picksLastBundleWithItsTime() {
        assertEquals("newest one" to 200L, NewestMessage.pick(listOf("old one" to 100L, "newest one" to 200L), 999L))
        assertEquals("only" to 999L, NewestMessage.pick(listOf("only" to 0L), 999L))   // no time: post time
        assertNull(NewestMessage.pick(emptyList(), 1L))
    }

    @Test fun R3_KB_newestMessage_blankLastBundleIsNullNotAnOlderText() {
        val photoLast = listOf<Pair<String?, Long>>("old text" to 100L, null to 300L)
        assertNull(NewestMessage.pick(photoLast, 999L))
        assertNull(NewestMessage.pick(listOf<Pair<String?, Long>>("old text" to 100L, "  " to 400L), 999L))
        assertNull(NewestMessage.pick(listOf(null to 5L, "" to 6L), 1L))
    }

    @Test fun R3_KB_quiet_trustedSenderDebitScareSuspiciousStillAlerts() = runBlocking {
        val g = KnowledgeGraph(clock = { now }).apply {
            ingest("hello there friend how are you", "", now - 1)
            mark(EntityKind.SENDER, "9800000020", TrustStatus.TRUSTED, now - 1)
        }
        val rig = Rig(g, { Label.SUSPICIOUS })
        rig.wiring.onPosted(smsInfo("Your a/c debited Rs 9,999. If not you, call 98XXXXXX10 to cancel", "9800000020", now))
        assertEquals(1, rig.dispatched.size)
    }

    @Test fun R3_KB_quiet_trustedSuspiciousIsNotDispatchedButTrustedOtpScamIs() = runBlocking {
        val g = KnowledgeGraph().apply {
            ingest("hello there friend how are you", "", now - 1)   // warm graph
            mark(EntityKind.SENDER, "VM-EXMPBK", TrustStatus.TRUSTED, now - 1)
        }
        val label = arrayOf(Label.SUSPICIOUS)
        val rig = Rig(g, { label[0] })
        rig.wiring.onPosted(smsInfo("Your ExampleBank parcel is delayed, track it in the app", "VM-EXMPBK", now))
        assertTrue("quiet: trusted sender, SUSPICIOUS, no hard signal", rig.dispatched.isEmpty())
        label[0] = Label.SCAM
        rig.wiring.onPosted(smsInfo("Your ExampleBank account will be blocked today, share OTP to unblock", "VM-EXMPBK", now + 120_000))
        assertEquals(1, rig.dispatched.size)
        // An untrusted sender gets the SUSPICIOUS heads-up as before.
        label[0] = Label.SUSPICIOUS
        rig.wiring.onPosted(smsInfo("Your OtherBank parcel is delayed, track it in the app", "VM-OTHRBK", now + 240_000))
        assertEquals(2, rig.dispatched.size)
    }

    @Test fun R3_KB_quiet_whatsappTrustUsesWaKeyAndHardSignalStillAlerts() = runBlocking {
        val g = KnowledgeGraph().apply {
            ingest("hello there friend how are you", "", now - 1)
            mark(EntityKind.SENDER, "wa:Contact Name", TrustStatus.TRUSTED, now - 1)
        }
        val rig = Rig(g, { Label.SUSPICIOUS })
        rig.wiring.onPosted(smsInfo("Hey are we still meeting for dinner today at eight", "Contact Name", now, pkg = "com.whatsapp"))
        assertTrue(rig.dispatched.isEmpty())
        // Reported later: REPORTED_ENTITY is a hard signal, so the same sender alerts again.
        g.mark(EntityKind.SENDER, "wa:Contact Name", TrustStatus.REPORTED, now)
        rig.wiring.onPosted(smsInfo("Hey are we still meeting for dinner today at nine", "Contact Name", now + 120_000, pkg = "com.whatsapp"))
        assertEquals(1, rig.dispatched.size)
    }

    // ---- call context ----

    @Test fun R3_KB_callContext_numberFromTitleThenTextNameOnlyIsNull() {
        CallContext.clear()
        CallContext.onCallNotification("+91 98000 00010", "Ongoing call", 1_000L)
        assertEquals("919800000010", CallContext.caller(2_000L))
        CallContext.onCallNotification("Mom", "Ongoing call 00:12", 1_000L)
        assertNull(CallContext.caller(2_000L))
        CallContext.onCallNotification("Unknown", "Incoming call from 098000 00010", 1_000L)
        assertEquals("09800000010", CallContext.caller(2_000L))
        CallContext.onCallNotification("1600123456", "", 1_000L)
        assertEquals("1600123456", CallContext.caller(2_000L))
        CallContext.clear()
    }

    @Test fun R3_KB_callContext_clearsOnRemovalAndExpiresAfterTwoHours() {
        CallContext.onCallNotification("9800000010", "", 0L)
        assertEquals("9800000010", CallContext.caller(CallContext.MAX_AGE_MS))
        assertNull(CallContext.caller(CallContext.MAX_AGE_MS + 1))
        assertNull(CallContext.caller(-1L))
        CallContext.clear()
        assertNull(CallContext.caller(1L))
    }

    @Test fun R3_KB_callContext_onlyCallCategoryCountsNotDialerPackage() {
        assertTrue(CallContext.isCallNotification("call"))
        assertFalse(CallContext.isCallNotification("msg"))
        assertFalse(CallContext.isCallNotification(null))   // a dialer's missed-call / promo notification has no call category
    }

    @Test fun R3_KB_callContext_removalClearsOnlyTheNotificationThatSetTheNumber() {
        CallContext.clear()
        CallContext.onCallNotification("9800000010", "", 1_000L, key = "k-call")
        CallContext.onRemoved("k-other")
        assertEquals("9800000010", CallContext.caller(2_000L))
        CallContext.onRemoved("k-call")
        assertNull(CallContext.caller(2_000L))
        CallContext.onCallNotification("9800000010", "", 1_000L)   // no key stored: no removal matches
        CallContext.onRemoved("k-call")
        assertEquals("9800000010", CallContext.caller(2_000L))
        CallContext.clear()
    }

    @Test fun R3_KB_callContext_bankTalkFromNon1600CallerFlagsAnd1600DoesNot() {
        val g = KnowledgeGraph().apply { ingest("hello there friend how are you", "", now - 1) }
        val req = ClassifyRequest("This is the HDFC bank calling about your account, please share your details", source = Source.CAPTION)
        CallContext.onCallNotification("+91 98000 00010", "Incoming call", now)
        val bad = Pipeline.withCallContext(req, g, now, CallContext.caller(now))
        assertTrue(bad.contextFlags.any { it.kind == FlagKind.NON_1600_BANK_CALL })
        CallContext.onCallNotification("1600123456", "Incoming call", now)
        val ok = Pipeline.withCallContext(req, g, now, CallContext.caller(now))
        assertFalse(ok.contextFlags.any { it.kind == FlagKind.NON_1600_BANK_CALL })
        CallContext.onCallNotification("Mom", "Incoming call", now)   // saved contact: no number, no verdict
        assertFalse(Pipeline.withCallContext(req, g, now, CallContext.caller(now)).contextFlags.any { it.kind == FlagKind.NON_1600_BANK_CALL })
        CallContext.clear()
    }

    // ---- delete my data ----

    private class FakeStore : GraphStore {
        var cleared = 0
        var clearOk = true
        var snap = GraphSnapshot.EMPTY
        val refs = mutableMapOf<Long, AlertRef>()
        override fun load() = snap
        override fun apply(delta: IngestDelta) { snap = snap.copy(ingested = snap.ingested + 1, events = snap.events + delta.events) }
        override fun prune(cutoffMs: Long) {}
        override fun clear(): Boolean { cleared++; snap = GraphSnapshot.EMPTY; refs.clear(); return clearOk }
        override fun mark(kind: EntityKind, key: String, status: TrustStatus, tsMs: Long) {}
        override fun putAlertRef(r: AlertRef) { refs[r.tsMs] = r }
        override fun alertRef(tsMs: Long) = refs[tsMs]
    }

    private fun event(ts: Long) = VerdictEvent(0, ts, Source.SMS, Label.SCAM, 0.9, ScamType.OTP, listOf("t"), "rules")

    @Test fun R3_KB_deleteMyData_emptiesSharedGraphAndStore_logOnlyWithAlsoAlerts() {
        val store = FakeStore()
        val g = PersistentKnowledgeGraph(store)
        g.ingest(orderText, "AX-AMAZON", now)
        g.rememberAlert(AlertRef(1L, "9800000099", listOf("9800000010"), emptyList()))
        g.mark(EntityKind.SENDER, "VM-EXMPBK", TrustStatus.TRUSTED, now)
        assertFalse(g.isEmpty)
        val log = InMemoryVerdictLog().apply { append(event(1)) }
        val demoLog = InMemoryVerdictLog().apply { append(event(2)) }   // the Demo Lab's separate log

        DataReset.run(g, log, alsoAlerts = false)
        assertTrue(g.isEmpty && g.snapshot().events.isEmpty() && g.snapshot().trust.isEmpty())
        assertNull(g.alertRef(1L))
        assertEquals(1, store.cleared)
        assertTrue(store.snap.events.isEmpty())
        assertEquals("alerts kept when not asked", 1, log.since(0).size)

        DataReset.run(g, log, alsoAlerts = true)
        assertTrue(log.since(0).isEmpty())
        assertEquals("demo log untouched", 1, demoLog.since(0).size)
        DataReset.run(g, null, alsoAlerts = true)   // no log yet: no crash
    }

    @Test fun R3_KB_deleteMyData_reportsFailureWhenStoreOrVerdictLogClearFails() {
        val ok = PersistentKnowledgeGraph(FakeStore())
        assertTrue(DataReset.run(ok, InMemoryVerdictLog(), alsoAlerts = true))
        val badStore = FakeStore().apply { clearOk = false }
        assertFalse(PersistentKnowledgeGraph(badStore).clear())
        assertFalse(DataReset.run(PersistentKnowledgeGraph(badStore), null, alsoAlerts = false))
        val throwingLog = object : com.hackasol.scamshield.core.VerdictLog by InMemoryVerdictLog() {
            override fun clear() = throw IllegalStateException("db locked")
        }
        assertFalse(DataReset.run(PersistentKnowledgeGraph(FakeStore()), throwingLog, alsoAlerts = true))
        assertTrue("log is not touched without alsoAlerts", DataReset.run(PersistentKnowledgeGraph(FakeStore()), throwingLog, alsoAlerts = false))
    }

    @Test fun R3_KB_verdictLogClear_clearsOnlyItsOwnInstance() {
        val real = InMemoryVerdictLog().apply { append(event(1)); append(event(2)) }
        val demo = InMemoryVerdictLog().apply { append(event(3)) }
        real.clear()
        assertTrue(real.since(0).isEmpty() && real.latest() == null && real.countsByType().isEmpty())
        assertEquals(3L, demo.latest()!!.tsMs)
        assertNotNull(demo.since(0).singleOrNull())
    }
}
