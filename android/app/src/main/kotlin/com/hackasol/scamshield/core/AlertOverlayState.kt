package com.hackasol.scamshield.core

enum class OverlayMode { HIDDEN, CHIP, CARD }

/**
 * What the renderer must do after an event: [render] = redraw content/mode, [armCardTimer] = start the card->chip timer
 * (AlertPolicy.CARD_MS), [armChipTimer] = (re)start the chip auto-hide timer (AlertPolicy.CHIP_IDLE_MS), [speak] = the card
 * just auto-opened (the one moment TTS may read a line).
 */
data class OverlayStep(
    val mode: OverlayMode,
    val render: Boolean = false,
    val armCardTimer: Boolean = false,
    val armChipTimer: Boolean = false,
    val speak: Boolean = false,
)

/**
 * Pure HIDDEN / CHIP / CARD machine behind OverlayController (which only renders and runs timers). Principle 8: a card
 * auto-expands once per call-level escalation (or once per distinct signal [eventKey]); repeated verdicts at the same level
 * change nothing, and in particular do not extend the chip's 60 s life (principle 7: everything times out). Dismiss silences
 * that level until the risk rises or a new event arrives. The Live Caption prompt is not a verdict: it has its own
 * open/close that never touches the escalation history. Main thread only.
 */
class AlertOverlayState {
    var mode = OverlayMode.HIDDEN; private set
    /** Severity drawn right now (SAFE while hidden). */
    var level = Label.SAFE; private set
    private var maxLevel = -1        // highest non-preliminary level shown this call
    private var cardLevel = -1       // highest level a card auto-opened for this call
    private var dismissedLevel = -1  // user pressed Dismiss at this level
    private var promptOpen = false
    private val events = HashSet<String>()

    private fun step(m: OverlayMode, render: Boolean = false, card: Boolean = false, speak: Boolean = false, armChip: Boolean = m == OverlayMode.CHIP): OverlayStep {
        val modeChanged = m != mode
        mode = m
        return OverlayStep(m, render || modeChanged, armCardTimer = card, armChipTimer = armChip, speak = speak)
    }

    private fun idle() = OverlayStep(mode)

    fun show(surface: Surface, shown: Label, preliminary: Boolean, eventKey: String? = null): OverlayStep {
        if (surface != Surface.CHIP && surface != Surface.CARD) return idle()
        // A verdict replaces the prompt; if the verdict itself changes nothing, the prompt is still closed.
        val closed = if (promptOpen) closePrompt() else null
        val r = showVerdict(surface, shown, preliminary, eventKey)
        return if (closed != null && !r.render && r.mode == OverlayMode.HIDDEN) closed else r
    }

    private fun showVerdict(surface: Surface, shown: Label, preliminary: Boolean, eventKey: String?): OverlayStep {
        val lv = shown.ordinal
        if (preliminary) {
            // Never a card, never a redraw flash: only a first appearance or a rise in severity changes anything.
            if (mode == OverlayMode.HIDDEN) { level = shown; return step(OverlayMode.CHIP, render = true) }
            if (mode == OverlayMode.CHIP && lv > level.ordinal) { level = shown; return step(OverlayMode.CHIP, render = true) }
            return idle()
        }
        val newEvent = eventKey != null && eventKey !in events
        if (lv < maxLevel || (lv <= dismissedLevel && !newEvent)) return idle()
        if (eventKey != null) events += eventKey
        maxLevel = maxOf(maxLevel, lv)
        val openCard = surface == Surface.CARD && (lv > cardLevel || newEvent)
        val levelChanged = shown != level
        level = shown
        if (openCard) {
            cardLevel = maxOf(cardLevel, lv)
            return step(OverlayMode.CARD, render = levelChanged || newEvent, card = true, speak = true)
        }
        // Card already open: leave it alone (its own timer collapses it); otherwise keep/show the chip.
        if (mode == OverlayMode.CARD) return OverlayStep(mode, render = levelChanged)
        // Same level, same event: the chip's hide timer keeps running (re-arm only on a rise, a new event, or first appearance).
        return step(OverlayMode.CHIP, render = levelChanged, armChip = levelChanged || newEvent || mode != OverlayMode.CHIP)
    }

    /** Chip -> card; card -> chip. A user-opened card is never read aloud. */
    fun tap(): OverlayStep = when (mode) {
        OverlayMode.CHIP -> { cardLevel = maxOf(cardLevel, level.ordinal); step(OverlayMode.CARD, render = true, card = true) }
        OverlayMode.CARD -> if (promptOpen) idle() else step(OverlayMode.CHIP, render = true)
        OverlayMode.HIDDEN -> idle()
    }

    fun timerCardExpired(): OverlayStep = if (mode == OverlayMode.CARD && !promptOpen) step(OverlayMode.CHIP, render = true) else idle()

    fun timerChipExpired(): OverlayStep = if (mode == OverlayMode.CHIP) hide() else idle()

    fun dismiss(): OverlayStep {
        if (mode == OverlayMode.HIDDEN) return idle()
        if (promptOpen) return closePrompt()
        dismissedLevel = maxOf(dismissedLevel, level.ordinal)
        return hide()
    }

    /** The "turn on Live Caption" prompt as a card. Never replaces a warning that is already showing; leaves the history alone. */
    fun showPrompt(): OverlayStep {
        if (mode != OverlayMode.HIDDEN) return idle()
        promptOpen = true; level = Label.SUSPICIOUS
        return step(OverlayMode.CARD, render = true, card = true)
    }

    /** Close only the prompt (button, open-volume-panel or its timer): escalation history and dismissals stay intact. */
    fun closePrompt(): OverlayStep {
        if (!promptOpen) return idle()
        promptOpen = false
        return hide()
    }

    fun callEnded(): OverlayStep {
        val wasShowing = mode != OverlayMode.HIDDEN
        maxLevel = -1; cardLevel = -1; dismissedLevel = -1; events.clear(); promptOpen = false
        level = Label.SAFE; mode = OverlayMode.HIDDEN
        return OverlayStep(OverlayMode.HIDDEN, render = wasShowing)
    }

    private fun hide(): OverlayStep { level = Label.SAFE; return step(OverlayMode.HIDDEN) }
}
