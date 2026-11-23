package com.hackasol.scamshield

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.hackasol.scamshield.core.AlertOverlayState
import com.hackasol.scamshield.core.AlertPolicy
import com.hackasol.scamshield.core.InCallSignals
import com.hackasol.scamshield.core.L10n
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.OverlayMode
import com.hackasol.scamshield.core.OverlayStep
import com.hackasol.scamshield.core.Verdict
import java.util.Locale

/**
 * In-call warning drawn as TYPE_ACCESSIBILITY_OVERLAY (no "draw over apps" permission). A small chip parks at the right edge
 * about 35% down the screen; a SCAM / live-signal verdict opens ONE compact card for 10 s, then it folds back to the chip, which
 * hides after 60 s without new risk or when the call ends. It never covers the top of the screen and never takes touches outside
 * its own bounds. All decisions live in [AlertOverlayState]; this class renders and runs timers. Main thread only.
 */
class OverlayController(private val service: AccessibilityService) : BubbleSink {
    private companion object {
        // Card height budget at default font scale: 8 + 8 padding + title 1 line (~24) + why 1 line (~24) + buttons 48 = ~112 dp (cap ~120).
        // Advice must never be cut mid-sentence ("Hang up. Never let a caller…"): 3 lines, title 2.
        const val WHY_MAX_LINES = 3
        const val TITLE_MAX_LINES = 2
        const val CARD_MAX_WIDTH_DP = 320 // WIDTH cap (also at most 80% of the screen), not a height
    }

    private val wm = service.getSystemService(WindowManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val state = AlertOverlayState()
    private var root: LinearLayout? = null
    private var cardTimer: Runnable? = null
    private var chipTimer: Runnable? = null

    // What the card currently shows: a verdict, or the "turn on Live Caption" prompt.
    private var prompt: (() -> Unit)? = null
    private var shown = Label.SAFE
    private var signalKind: String? = null
    private var prefix = ""

    private lateinit var chip: TextView
    private lateinit var card: LinearLayout
    private lateinit var title: TextView
    private lateinit var why: TextView
    private lateinit var primaryBtn: Button
    private lateinit var dismissBtn: Button

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var ttsPending: String? = null

    private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), service.resources.displayMetrics).toInt()

    private fun color(label: Label) = when (label) {
        Label.SAFE -> Color.parseColor("#E61B5E20")
        Label.SUSPICIOUS -> Color.parseColor("#F0B45309")
        Label.SCAM -> Color.parseColor("#F5B71C1C")
    }

    /** 35% of the CURRENT screen height: read at every render so a rotation mid-call is picked up. */
    private fun chipY() = (service.resources.displayMetrics.heightPixels * 0.35f).toInt()

    private fun ensureView(): LinearLayout {
        root?.let { return it }
        val ctx = service
        val dm = service.resources.displayMetrics
        chip = TextView(ctx).apply {
            setTextColor(Color.WHITE); textSize = 16f; setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER; minHeight = dp(48); setPadding(dp(14), dp(8), dp(14), dp(8))
            background = GradientDrawable().apply { cornerRadius = dp(24).toFloat() }
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            setOnClickListener { apply(state.tap()) }
        }
        title = TextView(ctx).apply { setTextColor(Color.WHITE); textSize = 16f; setTypeface(typeface, Typeface.BOLD); maxLines = TITLE_MAX_LINES; ellipsize = android.text.TextUtils.TruncateAt.END }
        why = TextView(ctx).apply { setTextColor(Color.WHITE); textSize = 16f; maxLines = WHY_MAX_LINES; ellipsize = android.text.TextUtils.TruncateAt.END }
        fun btn() = Button(ctx).apply {
            isAllCaps = false; textSize = 14f; maxLines = 1; minHeight = dp(48); minimumHeight = dp(48); setPadding(dp(8), 0, dp(8), 0)
        }
        primaryBtn = btn()
        dismissBtn = btn().apply { setOnClickListener { closeOrDismiss() } }
        val buttons = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(primaryBtn, LinearLayout.LayoutParams(0, dp(48), 1f))
            addView(dismissBtn, LinearLayout.LayoutParams(0, dp(48), 1f))
        }
        card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(8), dp(12), dp(8))
            background = GradientDrawable().apply { cornerRadius = dp(18).toFloat() }
            elevation = dp(8).toFloat()
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            addView(title); addView(why); addView(buttons)
        }
        // Card width: at most 80% of the screen (and 320 dp), same edge as the chip.
        val cardW = minOf((dm.widthPixels * 0.8f).toInt(), dp(CARD_MAX_WIDTH_DP))
        val layout = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.END
            addView(chip, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT))
            addView(card, LinearLayout.LayoutParams(cardW, LinearLayout.LayoutParams.WRAP_CONTENT))
        }
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            // NOT_TOUCH_MODAL: touches outside our own bounds reach the app underneath.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.END or Gravity.TOP; y = chipY() }
        wm.addView(layout, lp)
        root = layout
        return layout
    }

    /** [signalKind] non-null = an in-call signal: the texts come from the language layer, not from the verdict. */
    override fun showVerdict(v: Verdict, shown: Label, callLevel: Label, callRisk: Double, signalKind: String?, titlePrefix: String) {
        if (!AppSettings.overlayEnabled) { closeOrDismiss(); return }   // shortcut: switched-off overlay is hidden on the next event, no settings listener; add one if instant hide is needed
        val plan = AlertPolicy.plan(v.copy(label = shown), signalKind, callLevel)
        if (!plan.bubble) return
        val step = state.show(plan.surface, shown, v.preliminary, signalKind)
        if (step.render) { prompt = null; this.shown = shown; this.signalKind = signalKind; prefix = titlePrefix }
        apply(step)
    }

    fun showCaptionPrompt(onOpen: () -> Unit) {
        if (!AppSettings.overlayEnabled) { closeOrDismiss(); return }
        val step = state.showPrompt()
        if (!step.render) return   // a warning is already showing: never replace it with the prompt
        prompt = { onOpen(); closeOrDismiss() }; shown = Label.SUSPICIOUS; signalKind = null; prefix = ""
        apply(step)
    }

    /** Dismiss. The caption prompt closes through its own path so a dismissed warning's history is never wiped. */
    private fun closeOrDismiss() { if (prompt != null) { prompt = null; apply(state.closePrompt()) } else apply(state.dismiss()) }

    /** The call ended: hide at once and forget this call's escalation history. */
    fun callEnded() { prompt = null; apply(state.callEnded()) }

    private fun apply(step: OverlayStep) {
        if (step.mode == OverlayMode.HIDDEN) {
            cancelTimers(); stopTts()
            if (step.render) removeView()
            return
        }
        if (step.render && !AppSettings.overlayEnabled) { closeOrDismiss(); return }   // switched off mid-call: hide instead of re-rendering
        if (step.render) render(step.mode)
        // A critical in-call signal ("AnyDesk opened", OTP, screen share) waits for an answer instead of folding away.
        val sticky = prompt == null && signalKind in InCallSignals.CRITICAL_KINDS
        if (step.armCardTimer && !sticky) {
            cardTimer?.let(handler::removeCallbacks)
            cardTimer = Runnable { if (prompt != null) closeOrDismiss() else apply(state.timerCardExpired()) }.also { handler.postDelayed(it, AlertPolicy.CARD_MS) }
        }
        if (step.mode != OverlayMode.CARD) cardTimer?.let(handler::removeCallbacks)
        if (step.armChipTimer) {
            chipTimer?.let(handler::removeCallbacks)
            chipTimer = Runnable { apply(state.timerChipExpired()) }.also { handler.postDelayed(it, AlertPolicy.CHIP_IDLE_MS) }
        } else if (step.mode == OverlayMode.CARD) chipTimer?.let(handler::removeCallbacks)
        if (step.speak && prompt == null && step.mode == OverlayMode.CARD) cue()
    }

    private fun render(mode: OverlayMode) {
        val view = ensureView()
        (view.layoutParams as? WindowManager.LayoutParams)?.let { lp ->
            lp.y = chipY()
            try { wm.updateViewLayout(view, lp) } catch (_: Throwable) {}
        }
        val lang = AppSettings.lang
        (chip.background as GradientDrawable).setColor(color(shown))
        (card.background as GradientDrawable).setColor(color(shown))
        chip.text = prefix + L10n.chipText(shown, lang)
        chip.contentDescription = L10n.chipDescription(shown, lang)
        val p = prompt
        if (p != null) {
            title.text = L10n.captionTitle(lang); why.text = L10n.captionLine(lang)
            primaryBtn.text = L10n.openVolumePanel(lang); primaryBtn.setOnClickListener { p() }
        } else {
            val kind = signalKind
            val icon = L10n.labelIcon(shown)
            title.text = prefix + icon + " " + (if (kind != null) L10n.signalTitle(kind, lang) else L10n.cardTitle(shown, lang))
            why.text = if (kind != null) L10n.areYouSure(lang) + " " + L10n.signalAdvice(kind, lang) else L10n.cardWhy(shown, lang)
            if (kind in InCallSignals.LEAVE_APP_KINDS) {
                primaryBtn.text = L10n.leaveApp(lang)
                primaryBtn.setOnClickListener { service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME); closeOrDismiss() }
            } else {
                primaryBtn.text = L10n.call1930(lang); primaryBtn.setOnClickListener { dial("1930") }
            }
        }
        dismissBtn.text = if (prompt == null && signalKind != null) L10n.imSure(lang) else L10n.dismiss(lang)
        card.contentDescription = title.text.toString() + ". " + why.text
        card.visibility = if (mode == OverlayMode.CARD) View.VISIBLE else View.GONE
        chip.visibility = if (mode == OverlayMode.CARD) View.GONE else View.VISIBLE
        view.requestLayout()
    }

    /** Short haptic, plus (if the user kept the setting on) ONE spoken line. SCAM cards only, auto-opened only. */
    private fun cue() {
        card.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)   // honours the user's touch-feedback setting
        if (AppSettings.readAloud && shown == Label.SCAM) speak(L10n.ttsLine(signalKind, AppSettings.lang))
    }

    private fun speak(line: String) {
        if (ttsReady) { say(line); return }
        ttsPending = line
        if (tts != null) return
        tts = try {
            TextToSpeech(service) { status ->
                ttsReady = status == TextToSpeech.SUCCESS
                if (ttsReady) {
                    tts?.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                    ttsPending?.let { say(it) }
                }
                ttsPending = null
            }
        } catch (_: Throwable) { null }
    }

    private fun say(line: String) {
        val t = tts ?: return
        try {
            val r = t.setLanguage(Locale.forLanguageTag(L10n.ttsLanguageTag(AppSettings.lang)))
            // No voice for this language: stay silent rather than read Devanagari with the wrong voice.
            if (r == TextToSpeech.LANG_MISSING_DATA || r == TextToSpeech.LANG_NOT_SUPPORTED) return
            t.speak(line, TextToSpeech.QUEUE_FLUSH, null, "scamshield-warning")
        } catch (_: Throwable) {}
    }

    private fun stopTts() {
        ttsPending = null   // a line queued while the engine was still starting must not be spoken after dismiss / call end
        try { tts?.stop() } catch (_: Throwable) {}
    }

    private fun dial(number: String) {
        val i = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try { service.startActivity(i) } catch (_: Throwable) {}
    }

    private fun cancelTimers() {
        cardTimer?.let(handler::removeCallbacks); chipTimer?.let(handler::removeCallbacks)
    }

    private fun removeView() {
        root?.let { try { wm.removeView(it) } catch (_: Throwable) {} }
        root = null
    }

    /** Service shutdown: drop the view, timers and the speech engine. */
    fun hide() {
        apply(state.callEnded().copy(render = true))
    }

    fun release() {
        hide()
        try { tts?.shutdown() } catch (_: Throwable) {}
        tts = null; ttsReady = false
    }
}
