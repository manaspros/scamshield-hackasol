package com.hackasol.scamshield.core

/**
 * Scam signals during a call that need no audio: what the scam makes the victim DO.
 * Pure Kotlin; the service feeds it notification text and foreground-app package names.
 */
object InCallSignals {
    data class Signal(val kind: String, val label: Label, val confidence: Double, val reason: String, val trigger: String)

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

    val REMOTE_APPS = mapOf(
        "com.anydesk.anydeskandroid" to "AnyDesk",
        "com.teamviewer.quicksupport.market" to "TeamViewer QuickSupport",
        "com.teamviewer.teamviewer.market.mobile" to "TeamViewer",
        "com.rustdesk.rustdesk" to "RustDesk",
        "com.sand.airdroid" to "AirDroid",
        "com.sand.airdroidbiz" to "AirDroid Business",
    )

    private val OTP_RE = UnicodeRegex.of(
        "\\b(otp|one[- ]time password|verification code|security code|ओटीपी)\\b|\\b\\d{4,8}\\b[^.]{0,40}\\b(code|otp|ओटीपी)\\b|\\b(code|otp)\\b[^.]{0,40}\\b\\d{4,8}\\b"
    )

    fun fromNotification(text: String): Signal? {
        val m = OTP_RE.find(text) ?: return null
        return Signal("otp_during_call", Label.SCAM, 0.93,
            "OTP arrived during a call — never read it out to the caller", m.value.trim())
    }

    fun fromForegroundApp(pkg: String): Signal? {
        REMOTE_APPS[pkg]?.let {
            return Signal("remote_app_during_call", Label.SCAM, 0.96,
                "$it opened during a call — screen sharing is the #1 bank-fraud trick", it)
        }
        PAYMENT_APPS[pkg]?.let {
            return Signal("payment_app_during_call", Label.SUSPICIOUS, 0.85,
                "$it opened during a call — is the caller asking you to pay or 'verify'?", it)
        }
        return null
    }
}
