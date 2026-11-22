package com.hackasol.scamshield.core

/** What the UI layer should do for a verdict. Pure; AlertDispatcher (T1.7) executes it. */
data class AlertPlan(val bubble: Boolean, val notify: Boolean, val reportAction: Boolean)

object AlertPolicy {
    /** CAPTION is the only live source (user is mid-call); RECORDING is analysed after the fact. */
    private fun isLive(source: Source) = source == Source.CAPTION

    fun plan(v: Verdict, source: Source = v.source): AlertPlan = plan(v.label, source)

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
