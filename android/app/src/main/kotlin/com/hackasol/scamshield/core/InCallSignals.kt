package com.hackasol.scamshield.core

/**
 * Scam signals during a call that need no audio: what the scam makes the victim DO.
 * Pure Kotlin; the service feeds it notification text, window text and foreground-app package names.
 */
object InCallSignals {
    // Signal kinds cross the Kotlin -> Flutter event channel as strings. lib/api/signal_kinds.dart repeats them and
    // test/live_signals_test.dart compares both files, so rename here and there together.
    const val KIND_OTP = "otp_during_call"
    const val KIND_REMOTE_APP = "remote_app_during_call"
    const val KIND_PAYMENT_APP = "payment_app_during_call"
    const val KIND_SCREEN_SHARE = "screen_share_during_call"
    const val KIND_APP_INSTALLED = "app_installed_during_call"
    const val OTP_TRIGGER = "OTP"

    /** Signals that ask "Are you sure?" and keep the card open until the user answers (no 10 s auto-collapse). */
    val CRITICAL_KINDS = setOf(KIND_OTP, KIND_REMOTE_APP, KIND_SCREEN_SHARE, KIND_APP_INSTALLED)

    /** Signals where leaving the app on screen (Home) is the useful first step. */
    val LEAVE_APP_KINDS = setOf(KIND_REMOTE_APP, KIND_APP_INSTALLED, KIND_PAYMENT_APP)

    data class Signal(val kind: String, val label: Label, val confidence: Double, val reason: String, val trigger: String)

    /** The verdict the live pipeline records and shows for a signal. */
    fun toVerdict(s: Signal) = Verdict("[${s.trigger}] ${s.reason}", s.label, s.confidence, s.reason,
        listOf(s.trigger), "in-call signal", 0, Source.SIGNAL)

    val PAYMENT_APPS = mapOf(
        "com.phonepe.app" to "PhonePe",
        "net.one97.paytm" to "Paytm",
        "com.google.android.apps.nbu.paisa.user" to "Google Pay",
        "in.org.npci.upiapp" to "BHIM",
        "com.sbi.lotusintouch" to "SBI YONO",
        "com.sbi.upi" to "SBI Pay",
        "com.csam.icici.bank.imobile" to "ICICI iMobile",
        "com.snapwork.hdfc" to "HDFC Bank",
        "com.axis.mobile" to "Axis Mobile",
        "com.dreamplug.androidapp" to "CRED",
        "com.mobikwik_new" to "MobiKwik",
        "com.myairtelapp" to "Airtel Thanks",
        "com.freecharge.android" to "Freecharge",
    )

    // Play Store listings checked by fetch: chromeremotedesktop, teamviewer.host.market, sand.airdroid, sand.airmirror,
    // sand.airsos, anydeskandroid. Both RustDesk ids and Quick Assist did not resolve on the Play page when fetched,
    // so they are unconfirmed (carriez.flutter_hbb is the id from memory of RustDesk's own build config).
    val REMOTE_APPS = mapOf(
        "com.anydesk.anydeskandroid" to "AnyDesk",
        "com.teamviewer.quicksupport.market" to "TeamViewer QuickSupport",
        "com.teamviewer.teamviewer.market.mobile" to "TeamViewer",
        "com.teamviewer.host.market" to "TeamViewer Host",
        "com.rustdesk.rustdesk" to "RustDesk",
        "com.carriez.flutter_hbb" to "RustDesk",                // VERIFY package id
        "com.sand.airdroid" to "AirDroid",
        "com.sand.airdroidbiz" to "AirDroid Business",
        "com.sand.airmirror" to "AirMirror",
        "com.sand.airsos" to "AirDroid Remote Support",
        "com.google.chromeremotedesktop" to "Chrome Remote Desktop",
        "com.microsoft.quickassist" to "Microsoft Quick Assist",  // VERIFY package id
    )

    private val OTP_RE = UnicodeRegex.of(
        "\\b(otp|one[- ]time password|verification code|security code|ओटीपी)\\b|\\b\\d{4,8}\\b[^.]{0,40}\\b(code|otp|ओटीपी)\\b|\\b(code|otp)\\b[^.]{0,40}\\b\\d{4,8}\\b"
    )

    /** An OTP notification first, else a screen-share / cast notification. */
    fun fromNotification(text: String): Signal? {
        if (OTP_RE.containsMatchIn(text)) {
            // The trigger is a fixed word, never the match: the match can hold the code itself, and alerts show the trigger
            // (notification shade, live feed) where a caller watching a shared screen would read it.
            return Signal(KIND_OTP, Label.SCAM, 0.93,
                "OTP arrived during a call — never read it out to the caller", OTP_TRIGGER)
        }
        return ScreenShareMatcher.notificationMatch(text)?.let { screenShare(it) }
    }

    /** The screen-capture consent dialog: [pkg] is the window's package, [text] the text gathered from it. */
    fun fromWindowText(pkg: String, text: String): Signal? =
        if (ScreenShareMatcher.isDialog(pkg, text)) screenShare("screen sharing") else null

    private fun screenShare(trigger: String) = Signal(KIND_SCREEN_SHARE, Label.SCAM, 0.95,
        "Screen sharing started during a call — a scammer can now see your OTPs and PIN", trigger)

    fun fromForegroundApp(pkg: String): Signal? {
        REMOTE_APPS[pkg]?.let {
            return Signal(KIND_REMOTE_APP, Label.SCAM, 0.96,
                "$it opened during a call — screen sharing is the #1 bank-fraud trick", it)
        }
        PAYMENT_APPS[pkg]?.let {
            return Signal(KIND_PAYMENT_APP, Label.SUSPICIOUS, 0.85,
                "$it opened during a call — is the caller asking you to pay or 'verify'?", it)
        }
        return null
    }

    /**
     * A package was installed while the call is live. SCAM for a known remote-access app or when its requested
     * permissions score HIGH in [ApkRisk]; otherwise SUSPICIOUS. [permissions] null = unreadable (package visibility).
     */
    fun fromInstall(pkg: String, label: String?, permissions: List<String>?): Signal {
        val name = label?.takeIf { it.isNotBlank() } ?: REMOTE_APPS[pkg] ?: pkg
        if (pkg in REMOTE_APPS) return Signal(KIND_APP_INSTALLED, Label.SCAM, 0.96,
            "$name was installed during a call — scammers make you install a screen-sharing app", name)
        if (permissions != null && ApkRisk.assess(permissions).level == ApkRiskLevel.HIGH)
            return Signal(KIND_APP_INSTALLED, Label.SCAM, 0.9,
                "$name was installed during a call and asks for dangerous permissions", name)
        return Signal(KIND_APP_INSTALLED, Label.SUSPICIOUS, 0.8,
            "$name was installed during a call — did the caller ask you to install it?", name)
    }
}

/**
 * Per-call state for the live signals: one alert per kind per call, plus the call-start re-check. A remote app opened
 * just BEFORE the call produced its window event while no call was active, so it is evaluated once when the call starts.
 * Thread-safe: window events arrive on the scan thread, call state on the main thread.
 */
class SignalGate(private val freshMs: Long = 60_000) {
    private val fired = HashSet<String>()
    private var lastPkg: String? = null
    private var lastPkgMs = 0L

    companion object {
        /** Telephony / system windows that cover the app the user was in; never the "last app". */
        val IGNORED_FOREGROUND = setOf(
            "com.android.systemui", "android", "com.android.incallui", "com.google.android.dialer",
            "com.android.dialer", "com.samsung.android.incallui", "com.android.server.telecom",
        )
    }

    @Synchronized fun noteForeground(pkg: String, nowMs: Long) {
        if (pkg in IGNORED_FOREGROUND) return
        lastPkg = pkg; lastPkgMs = nowMs
    }

    /** Clears the per-call dedupe. Call when a call starts. */
    @Synchronized fun startCall() = fired.clear()

    /** Returns [s] the first time its kind is seen in this call, else null. */
    @Synchronized fun accept(s: InCallSignals.Signal?): InCallSignals.Signal? = s?.takeIf { fired.add(it.kind) }

    /** Call-start re-check: the app showing now ([activePkg], may be null) and the last one seen within [freshMs]. */
    @Synchronized fun callStartSignal(activePkg: String?, nowMs: Long): InCallSignals.Signal? {
        val recent = lastPkg?.takeIf { nowMs - lastPkgMs <= freshMs }
        return accept(listOfNotNull(activePkg, recent).firstNotNullOfOrNull { InCallSignals.fromForegroundApp(it) })
    }
}

/**
 * In-call signals from the notification listener alone, for when the accessibility service is not running (not granted,
 * or killed): an OTP or a screen-share notification while the dialer's call notification is up. The accessibility path
 * handles them when it runs, so this stays silent then (no double alert). One alert per kind per call ([callGeneration]).
 */
class ListenerCallSignals(private val gate: SignalGate = SignalGate()) {
    private var generation = -1L

    fun onNotification(text: String, inCall: Boolean, callGeneration: Long, accessibilityRunning: Boolean, enabled: Boolean): InCallSignals.Signal? {
        if (!enabled || !inCall || accessibilityRunning) return null
        synchronized(this) { if (callGeneration != generation) { generation = callGeneration; gate.startCall() } }
        return gate.accept(InCallSignals.fromNotification(text))
    }
}
