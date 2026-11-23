package com.hackasol.scamshield.core

/**
 * Where an alert shows. Intrusiveness follows severity and context, not declaration order (nothing uses the ordinal):
 * messages go NONE / SILENT_NOTIF / HEADS_UP, live calls go CHIP / CARD.
 */
enum class Surface {
    NONE, SILENT_NOTIF, HEADS_UP, CHIP, CARD;

    companion object {
        /** Legacy bubble/notify pair -> surface (a heads-up cannot be derived from two booleans; AlertPolicy sets it). */
        fun of(bubble: Boolean, notify: Boolean): Surface = when {
            bubble && notify -> CARD
            bubble -> CHIP
            notify -> SILENT_NOTIF
            else -> NONE
        }
    }
}

/**
 * What the UI layer should do for a verdict. Pure; AlertDispatcher executes it. [bubble] = an overlay (chip or card) is drawn,
 * [notify] = a notification is posted (silent unless [surface] is HEADS_UP; for CARD it is the silent record).
 */
data class AlertPlan(
    val bubble: Boolean,
    val notify: Boolean,
    val reportAction: Boolean,
    val surface: Surface = Surface.of(bubble, notify),
) {
    val headsUp: Boolean get() = surface == Surface.HEADS_UP

    companion object {
        fun of(s: Surface): AlertPlan {
            val bubble = s == Surface.CHIP || s == Surface.CARD
            val notify = s == Surface.SILENT_NOTIF || s == Surface.HEADS_UP || s == Surface.CARD
            return AlertPlan(bubble, notify, bubble || notify, s)
        }
    }
}

object AlertPolicy {
    /** Delay before a non-live SCAM heads-up so the original message's own peek (about 5 s) is gone. */
    const val HEADS_UP_DELAY_MS = 6_000L
    const val HEADS_UP_TIMEOUT_MS = 10 * 60_000L
    const val SILENT_TIMEOUT_MS = 30 * 60_000L
    /** An auto-expanded card collapses back to the chip after this long. */
    const val CARD_MS = 10_000L
    /** The chip hides after this long with no new risk. */
    const val CHIP_IDLE_MS = 60_000L

    /** CAPTION and SIGNAL are live (the user is mid-call); everything else is read at leisure or analysed after the fact. */
    private fun isLive(source: Source) = source == Source.CAPTION || source == Source.SIGNAL

    fun plan(v: Verdict, source: Source = v.source): AlertPlan = decide(v.label, source, preliminary = v.preliminary)

    /**
     * Same plan, but a payment-app signal is a silent notification until the whole call is already high risk
     * ([callLevel] SCAM): opening PhonePe on a call is often innocent, so it must not pop a card on its own.
     */
    fun plan(v: Verdict, signalKind: String?, callLevel: Label): AlertPlan =
        decide(v.label, v.source, callLevel, signalKind, v.preliminary)

    fun plan(label: Label, source: Source): AlertPlan = decide(label, source)

    /** The whole ladder in one pure function. */
    fun decide(
        label: Label,
        source: Source,
        callLevel: Label = Label.SAFE,
        signalKind: String? = null,
        preliminary: Boolean = false,
    ): AlertPlan {
        if (label == Label.SAFE) return AlertPlan.of(Surface.NONE)
        val live = isLive(source)
        // Rules-only verdicts: chip at most (a final verdict follows), never a card or a notification.
        if (preliminary) return AlertPlan.of(if (live) Surface.CHIP else Surface.NONE)
        if (signalKind == InCallSignals.KIND_PAYMENT_APP)
            return AlertPlan.of(if (callLevel == Label.SCAM) Surface.CARD else Surface.SILENT_NOTIF)
        return AlertPlan.of(when {
            !live -> if (label == Label.SCAM) Surface.HEADS_UP else Surface.SILENT_NOTIF
            label == Label.SCAM -> Surface.CARD
            else -> Surface.CHIP
        })
    }

    /** Sources whose original message may be peeking at the top right now. PASTE/SHARE/RECORDING are user-initiated in our app. */
    private fun isIncomingMessage(source: Source) =
        source == Source.SMS || source == Source.WHATSAPP || source == Source.NOTIFICATION

    /** 6 s for a SCAM heads-up on an incoming-message source, otherwise 0 (post now). */
    fun headsUpDelayMs(label: Label, source: Source): Long =
        if (label == Label.SCAM && isIncomingMessage(source)) HEADS_UP_DELAY_MS else 0L

    /** setTimeoutAfter for the notification of [plan]; 0 = none. */
    fun notificationTimeoutMs(plan: AlertPlan): Long = when (plan.surface) {
        Surface.HEADS_UP -> HEADS_UP_TIMEOUT_MS
        Surface.SILENT_NOTIF, Surface.CARD -> SILENT_TIMEOUT_MS
        else -> 0L
    }
}
