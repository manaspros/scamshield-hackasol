package com.hackasol.scamshield.core

import com.hackasol.scamshield.core.InCallSignals.KIND_APP_INSTALLED
import com.hackasol.scamshield.core.InCallSignals.KIND_OTP
import com.hackasol.scamshield.core.InCallSignals.KIND_PAYMENT_APP
import com.hackasol.scamshield.core.InCallSignals.KIND_REMOTE_APP
import com.hackasol.scamshield.core.InCallSignals.KIND_SCREEN_SHARE
import com.hackasol.scamshield.core.demo.DemoRunner
import com.hackasol.scamshield.core.demo.DemoScenarios
import com.hackasol.scamshield.core.graph.KnowledgeGraph
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveSignalsTest {
    private fun v(label: Label, source: Source = Source.SIGNAL) =
        Verdict("x", label, 0.9, "r", emptyList(), "in-call signal", 0, source)

    // ---- screen-share matcher ----

    @Test fun LIVE_screenShareDialog_matchesSystemUiText() {
        val texts = listOf(
            "Start recording or casting?",
            "Start recording or casting with Chrome? While you're recording, Android has access to anything visible on your screen.",
            "Start sharing?",
            "Share or record your screen",
            "Share entire screen",
            "This app will have access to all of the information that is visible on your screen or played from your device",
            "रिकॉर्डिंग या कास्टिंग शुरू करें?",
        )
        for (t in texts) assertNotNull(t, InCallSignals.fromWindowText("com.android.systemui", t))
        assertNotNull(InCallSignals.fromWindowText("com.google.android.permissioncontroller", "Start sharing?"))
    }

    @Test fun LIVE_screenShareDialog_isScamAndNeedsSystemPackage() {
        val s = InCallSignals.fromWindowText("com.android.systemui", "Start recording or casting?")!!
        assertEquals(KIND_SCREEN_SHARE, s.kind)
        assertEquals(Label.SCAM, s.label)
        // A chat that merely says it, or an unrelated system window, is not the dialog.
        assertNull(InCallSignals.fromWindowText("com.whatsapp", "Start sharing?"))
        assertNull(InCallSignals.fromWindowText("com.android.systemui", "Wi-Fi, Bluetooth, Flashlight"))
        assertNull(InCallSignals.fromWindowText("com.android.systemui", ""))
    }

    @Test fun LIVE_screenShareNotification_matches() {
        for (t in listOf("You're sharing your screen", "Screen sharing", "Casting screen to Living room TV", "स्क्रीन शेयर चालू है")) {
            val s = InCallSignals.fromNotification(t)
            assertEquals(t, KIND_SCREEN_SHARE, s?.kind)
            assertEquals(Label.SCAM, s!!.label)
        }
        assertNull(InCallSignals.fromNotification("Mom: dinner at 8?"))
        assertNull(InCallSignals.fromNotification("Podcasting tips for beginners"))
    }

    @Test fun LIVE_otpNotificationStillWinsAndKeepsKind() {
        assertEquals(KIND_OTP, InCallSignals.fromNotification("AX-HDFCBK 482913 is your OTP")!!.kind)
        assertEquals("otp_during_call", KIND_OTP)
    }

    // ---- remote list ----

    @Test fun LIVE_remoteList_hasChromeRemoteDesktopQuickAssistRustDeskAirDroid() {
        for (pkg in listOf(
            "com.google.chromeremotedesktop", "com.microsoft.quickassist", "com.carriez.flutter_hbb", "com.rustdesk.rustdesk",
            "com.sand.airdroid", "com.sand.airmirror", "com.sand.airsos", "com.teamviewer.host.market", "com.anydesk.anydeskandroid",
        )) {
            val s = InCallSignals.fromForegroundApp(pkg)
            assertEquals(pkg, KIND_REMOTE_APP, s?.kind)
            assertEquals(Label.SCAM, s!!.label)
        }
        assertEquals("Chrome Remote Desktop", InCallSignals.fromForegroundApp("com.google.chromeremotedesktop")!!.trigger)
    }

    @Test fun LIVE_kindsAreDistinct() {
        val kinds = listOf(KIND_OTP, KIND_REMOTE_APP, KIND_PAYMENT_APP, KIND_SCREEN_SHARE, KIND_APP_INSTALLED)
        assertEquals(kinds.size, kinds.toSet().size)
    }

    // ---- app installed during a call ----

    @Test fun LIVE_install_knownRemoteAppIsScam() {
        val s = InCallSignals.fromInstall("com.anydesk.anydeskandroid", null, null)
        assertEquals(KIND_APP_INSTALLED, s.kind)
        assertEquals(Label.SCAM, s.label)
        assertEquals("AnyDesk", s.trigger)
    }

    @Test fun LIVE_install_highRiskPermissionsAreScam() {
        val perms = listOf("android.permission.RECEIVE_SMS", "android.permission.READ_SMS", "android.permission.BIND_ACCESSIBILITY_SERVICE")
        val s = InCallSignals.fromInstall("com.example.fastloan", "Fast Loan", perms)
        assertEquals(Label.SCAM, s.label)
        assertEquals("Fast Loan", s.trigger)
    }

    @Test fun LIVE_install_otherwiseSuspicious_evenWhenPermissionsUnreadable() {
        assertEquals(Label.SUSPICIOUS, InCallSignals.fromInstall("com.example.notes", "Notes", listOf("android.permission.INTERNET")).label)
        val hidden = InCallSignals.fromInstall("com.example.hidden", null, null)   // package visibility hid the app
        assertEquals(Label.SUSPICIOUS, hidden.label)
        assertEquals("com.example.hidden", hidden.trigger)
    }

    // ---- alert policy ----

    @Test fun LIVE_policy_signalsAreLive_scamBubblesAndNotifies() {
        assertEquals(AlertPlan(bubble = true, notify = true, reportAction = true), AlertPolicy.plan(Label.SCAM, Source.SIGNAL))
        assertEquals(AlertPlan(bubble = true, notify = false, reportAction = true), AlertPolicy.plan(Label.SUSPICIOUS, Source.SIGNAL))
        assertEquals(AlertPlan(false, false, false), AlertPolicy.plan(Label.SAFE, Source.SIGNAL))
        // Not-live sources are unchanged.
        assertFalse(AlertPolicy.plan(Label.SCAM, Source.RECORDING).bubble)
        assertTrue(AlertPolicy.plan(Label.SCAM, Source.CAPTION).bubble)
    }

    @Test fun LIVE_policy_remoteOtpScreenShareInstallAlwaysBubble() {
        for (k in listOf(KIND_REMOTE_APP, KIND_OTP, KIND_SCREEN_SHARE, KIND_APP_INSTALLED)) {
            for (callLevel in Label.values()) {
                val p = AlertPolicy.plan(v(Label.SCAM), k, callLevel)
                assertTrue("$k/$callLevel", p.bubble && p.notify && p.reportAction)
            }
            assertTrue(k, AlertPolicy.plan(v(Label.SUSPICIOUS), k, Label.SAFE).bubble)
        }
    }

    @Test fun LIVE_policy_paymentAppIsAChipUnlessCallAlreadyHighRisk() {
        // A silent notification is never seen mid-call: a chip is visible but pops no card and makes no sound.
        val low = AlertPolicy.plan(v(Label.SUSPICIOUS), KIND_PAYMENT_APP, Label.SUSPICIOUS)
        assertEquals(AlertPlan.of(Surface.CHIP), low)
        assertEquals(AlertPlan.of(Surface.CHIP), AlertPolicy.plan(v(Label.SUSPICIOUS), KIND_PAYMENT_APP, Label.SAFE))
        val high = AlertPolicy.plan(v(Label.SUSPICIOUS), KIND_PAYMENT_APP, Label.SCAM)
        assertEquals(AlertPlan(bubble = true, notify = true, reportAction = true), high)
    }

    @Test fun LIVE_policy_paymentEscalatesAfterScamCaptionInTheTracker() {
        val tracker = CallRiskTracker()
        val caption = Verdict("OTP bata do", Label.SCAM, 0.95, "r", emptyList(), "rules", 0, Source.CAPTION)
        tracker.record(caption, 1_000)
        val pay = InCallSignals.toVerdict(InCallSignals.fromForegroundApp("com.phonepe.app")!!)
        val shown = tracker.record(pay, 4_000)
        assertEquals(Label.SCAM, tracker.level())
        assertTrue(AlertPolicy.plan(pay.copy(label = shown), KIND_PAYMENT_APP, tracker.level()).bubble)
        // Alone, the same payment signal is only a chip, never a card.
        val fresh = CallRiskTracker()
        val s2 = fresh.record(pay, 1_000)
        assertEquals(Surface.CHIP, AlertPolicy.plan(pay.copy(label = s2), KIND_PAYMENT_APP, fresh.level()).surface)
    }

    // ---- call-start re-check + dedupe ----

    @Test fun LIVE_callStart_remoteAppOpenedJustBeforeTheCallIsCaught() {
        val g = SignalGate()
        g.noteForeground("com.anydesk.anydeskandroid", 10_000)   // window event while no call was active
        g.noteForeground("com.android.incallui", 12_000)         // the in-call UI does not hide it
        g.startCall()
        val s = g.callStartSignal(activePkg = null, nowMs = 12_500)
        assertEquals(KIND_REMOTE_APP, s?.kind)
    }

    @Test fun LIVE_callStart_activeWindowIsChecked_staleAndBenignAreNot() {
        val g = SignalGate()
        assertEquals(KIND_REMOTE_APP, g.callStartSignal("com.google.chromeremotedesktop", 1_000)?.kind)
        val stale = SignalGate()
        stale.noteForeground("com.anydesk.anydeskandroid", 1_000)
        assertNull("opened 3 minutes before the call", stale.callStartSignal(null, 181_000))
        val benign = SignalGate()
        benign.noteForeground("com.whatsapp", 1_000)
        assertNull(benign.callStartSignal("com.google.android.dialer", 2_000))
        // A later benign app replaces the remote app as "last seen".
        val moved = SignalGate()
        moved.noteForeground("com.anydesk.anydeskandroid", 1_000)
        moved.noteForeground("com.android.launcher", 2_000)
        assertNull(moved.callStartSignal(null, 3_000))
    }

    @Test fun LIVE_dedupe_oneAlertPerKindPerCall_resetsOnNewCall() {
        val g = SignalGate()
        val any = InCallSignals.fromForegroundApp("com.anydesk.anydeskandroid")
        assertNotNull(g.accept(any))
        assertNull(g.accept(any))
        assertNull("another remote app is the same kind", g.accept(InCallSignals.fromForegroundApp("com.rustdesk.rustdesk")))
        assertNotNull("a different kind still fires", g.accept(InCallSignals.fromNotification("482913 is your OTP")))
        assertNull(g.accept(null))
        g.startCall()
        assertNotNull(g.accept(any))
    }

    @Test fun LIVE_dedupe_callStartDoesNotRepeatAnAlreadyFiredKind() {
        val g = SignalGate()
        g.noteForeground("com.anydesk.anydeskandroid", 1_000)
        assertNotNull(g.callStartSignal(null, 1_500))
        assertNull(g.callStartSignal("com.anydesk.anydeskandroid", 2_000))
    }

    // ---- language layer ----

    @Test fun LIVE_overlayTexts_everyKindLocalised() {
        val kinds = listOf(KIND_REMOTE_APP, KIND_OTP, KIND_SCREEN_SHARE, KIND_APP_INSTALLED, KIND_PAYMENT_APP, "unknown_kind")
        for (k in kinds) {
            for (lang in listOf("en", "hi", "hne")) {
                assertTrue(L10n.signalTitle(k, lang).isNotBlank())
                assertTrue(L10n.signalLine(k, "AnyDesk", lang).isNotBlank())
                assertTrue(L10n.signalAdvice(k, lang).isNotBlank())
            }
            assertNotEquals(k, L10n.signalTitle(k, "en"), L10n.signalTitle(k, "hi"))
            assertNotEquals(k, L10n.signalAdvice(k, "en"), L10n.signalAdvice(k, "hi"))
        }
        assertTrue(L10n.signalLine(KIND_REMOTE_APP, "AnyDesk", "en").contains("AnyDesk"))
        // The OTP line never carries the OTP text.
        assertFalse(L10n.signalLine(KIND_OTP, "482913", "en").contains("482913"))
    }

    // ---- Demo Lab ----

    private fun run(id: String) = runBlocking {
        DemoRunner(KnowledgeGraph(), InMemoryVerdictLog(), null, clock = { 1_700_000_000_000L }).run(DemoScenarios.byId(id)!!)
    }

    @Test fun LIVE_demo_remoteAccess_captionThenAnyDeskThenOtp_endsScamWithBubbleAndAlert() {
        val r = run("live_remote_access")
        assertEquals(3, r.steps.size)
        assertTrue(r.steps.joinToString { "${it.fused.label} ${it.actualFlags}" }, r.pass)
        val (caption, anydesk, otp) = r.steps
        assertTrue("caption bubble", caption.bubble)
        assertEquals(Label.SCAM, anydesk.fused.label)
        assertEquals(listOf(KIND_REMOTE_APP), anydesk.fused.raisedBy)
        assertTrue(anydesk.bubble)
        assertEquals(Label.SCAM, otp.fused.label)
        assertEquals(listOf(KIND_OTP), otp.fused.raisedBy)
        assertTrue(otp.bubble)
        assertNotNull(otp.alert)
        assertTrue(otp.alert!!.reportAction)
        assertTrue(otp.alert.title.startsWith("[DEMO] "))
        assertEquals(Source.SIGNAL, otp.source)
    }

    @Test fun LIVE_demo_screenShare_captionThenConsentDialog_isScamWithBubble() {
        val r = run("live_screen_share")
        assertEquals(2, r.steps.size)
        assertTrue(r.steps.joinToString { "${it.fused.label} ${it.actualFlags}" }, r.pass)
        val dialog = r.steps[1]
        assertEquals(Label.SCAM, dialog.fused.label)
        assertEquals(listOf(KIND_SCREEN_SHARE), dialog.fused.raisedBy)
        assertTrue(dialog.bubble)
        assertNotNull(dialog.alert)
        assertNotEquals(Label.SAFE, r.steps[0].fused.label)   // 'screen share karo' is flagged by the rules too
    }

    @Test fun LIVE_demo_signalStepNeverFiresTwiceInOneRun() {
        val twice = DemoScenarios.byId("live_remote_access")!!.let { s ->
            s.copy(steps = s.steps + s.steps[1])
        }
        val r = runBlocking { DemoRunner(KnowledgeGraph(), InMemoryVerdictLog(), null, clock = { 1_700_000_000_000L }).run(twice) }
        assertEquals(Label.SAFE, r.steps.last().fused.label)   // deduped: "No signal raised"
        assertFalse(r.pass)
    }

    // ---- red-team fixes ----

    @Test fun LIVE_otpSignalNeverCarriesTheCode() {
        for (t in listOf("482913 is your OTP for login", "Your OTP is 482913", "Use verification code 48 29 13 to sign in")) {
            val s = InCallSignals.fromNotification(t)!!
            assertEquals(KIND_OTP, s.kind)
            assertEquals(InCallSignals.OTP_TRIGGER, s.trigger)
            assertFalse(InCallSignals.toVerdict(s).text.contains("482913"))
        }
    }

    @Test fun LIVE_listenerFallbackOnlyWhenAccessibilityIsOff() {
        val l = ListenerCallSignals()
        val otp = "Your OTP is 482913"
        assertNull(l.onNotification(otp, inCall = true, callGeneration = 1, accessibilityRunning = true, enabled = true))
        assertNull(l.onNotification(otp, inCall = false, callGeneration = 1, accessibilityRunning = false, enabled = true))
        assertNull(l.onNotification(otp, inCall = true, callGeneration = 1, accessibilityRunning = false, enabled = false))
        assertEquals(KIND_OTP, l.onNotification(otp, true, 1, false, true)?.kind)
        assertNull("once per call", l.onNotification(otp, true, 1, false, true))
        assertEquals(KIND_SCREEN_SHARE, l.onNotification("You're sharing your screen", true, 1, false, true)?.kind)
        assertEquals("next call alerts again", KIND_OTP, l.onNotification(otp, true, 2, false, true)?.kind)
        assertNull(l.onNotification("Lunch at 1?", true, 2, false, true))
    }

    @Test fun LIVE_callContextGenerationPerCall() {
        CallContext.clear()
        val g0 = CallContext.callGeneration
        assertFalse(CallContext.inCall(1_000))
        CallContext.onCallNotification("Mom", "Ongoing call", 1_000, "k")
        CallContext.onCallNotification("Mom", "Ongoing call", 2_000, "k")   // same call, notification updated
        assertTrue(CallContext.inCall(2_500))
        assertEquals(g0 + 1, CallContext.callGeneration)
        CallContext.onRemoved("k")
        assertFalse(CallContext.inCall(3_000))
        CallContext.onCallNotification("+91 98000 00010", "Incoming call", 4_000, "k")
        assertEquals(g0 + 2, CallContext.callGeneration)
        CallContext.clear()
    }

    @Test fun LIVE_criticalKindsAskAndPaymentIsNotCritical() {
        assertTrue(InCallSignals.CRITICAL_KINDS.containsAll(listOf(KIND_OTP, KIND_REMOTE_APP, KIND_SCREEN_SHARE, KIND_APP_INSTALLED)))
        assertFalse(KIND_PAYMENT_APP in InCallSignals.CRITICAL_KINDS)
        for (lang in listOf("en", "hi")) assertTrue(L10n.areYouSure(lang).isNotBlank() && L10n.imSure(lang).isNotBlank() && L10n.leaveApp(lang).isNotBlank())
    }
}

