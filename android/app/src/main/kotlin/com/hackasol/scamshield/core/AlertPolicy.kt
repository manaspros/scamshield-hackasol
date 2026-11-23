package com.hackasol.scamshield.core

/** What the UI layer should do for a verdict. Pure; AlertDispatcher (T1.7) executes it. */
data class AlertPlan(val bubble: Boolean, val notify: Boolean, val reportAction: Boolean)

object AlertPolicy {
    /** CAPTION and SIGNAL are live (the user is mid-call, so the bubble shows); RECORDING is analysed after the fact. */
    private fun isLive(source: Source) = source == Source.CAPTION || source == Source.SIGNAL

    fun plan(v: Verdict, source: Source = v.source): AlertPlan = plan(v.label, source)

    /**
     * Same plan, but a payment-app signal is notification-only until the whole call is already high risk
     * ([callLevel] SCAM): opening PhonePe on a call is often innocent, so it must not pop a bubble on its own.
     */
    fun plan(v: Verdict, signalKind: String?, callLevel: Label): AlertPlan {
        val p = plan(v)
        if (signalKind != InCallSignals.KIND_PAYMENT_APP || v.label == Label.SAFE) return p
        return if (callLevel == Label.SCAM) AlertPlan(bubble = true, notify = true, reportAction = true)
        else AlertPlan(bubble = false, notify = true, reportAction = true)
    }

    fun plan(label: Label, source: Source): AlertPlan {
        val live = isLive(source)
        val bubble: Boolean
        val notify: Boolean
        when (label) {
            Label.SAFE -> { bubble = false; notify = false }
            Label.SCAM -> { bubble = live; notify = true }
            Label.SUSPICIOUS -> { bubble = live; notify = !live }
        }
        return AlertPlan(bubble, notify, reportAction = bubble || notify)
    }
}
