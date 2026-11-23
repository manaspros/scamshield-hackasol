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
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.hackasol.scamshield.core.AlertOverlayState
import com.hackasol.scamshield.core.AlertPolicy
import com.hackasol.scamshield.core.L10n
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.OverlayMode
import com.hackasol.scamshield.core.OverlayStep
import com.hackasol.scamshield.core.Verdict
import java.util.Locale

/**
 * In-call warning drawn as TYPE_ACCESSIBILITY_OVERLAY (no "draw over apps" permission), styled as a "Live Alert":
 * a black pill at the top centre (shield, pulsing risk dot, risk word) that opens into a rounded card under it
 * (title, what to do, Call 1930 / Report / dismiss). A SCAM / live-signal verdict opens the card for 10 s, then it folds
 * back to the pill, which hides after 60 s without new risk or when the call ends. It never takes touches outside its own
 * bounds. All decisions live in [AlertOverlayState]; this class renders and runs timers. Main thread only.
 */
class OverlayController(private val service: AccessibilityService) : BubbleSink {
    private companion object {
        const val WHY_MAX_LINES = 2        // title is 2 lines max too; both ellipsize
        const val CARD_MAX_WIDTH_DP = 380  // WIDTH cap (also at most 92% of the screen), not a height
        const val PILL_BG = 0xFF000000.toInt()
        const val PILL_EDGE = 0xFF3A3A3C.toInt()
        const val BRAND = 0xFF0066CC.toInt()
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

    private lateinit var chip: LinearLayout       // the Live Alert pill
    private lateinit var chipDot: View
    private lateinit var chipText: TextView
    private lateinit var card: LinearLayout
    private lateinit var badge: TextView
    private lateinit var title: TextView
    private lateinit var why: TextView
    private lateinit var primaryBtn: Button
    private lateinit var reportBtn: Button
    private lateinit var dismissBtn: ImageButton

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var ttsPending: String? = null

    private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), service.resources.displayMetrics).toInt()

    /** Risk colour for the dot, badge and primary button (light / dark from values(-night)/colors.xml). */
    private fun riskColor(label: Label) = when (label) {
        Label.SCAM -> service.getColor(R.color.alert_scam)
        Label.SUSPICIOUS -> Color.parseColor("#FFB340")
        Label.SAFE -> Color.parseColor("#30D158")
    }

    /** Just under the status bar, read at every render so a rotation mid-call is picked up. */
    private fun pillY(): Int {
        val id = service.resources.getIdentifier("status_bar_height", "dimen", "android")
        return (if (id > 0) service.resources.getDimensionPixelSize(id) else dp(24)) + dp(6)
    }

    private fun pillBg(stroke: Boolean) = GradientDrawable().apply {
        cornerRadius = dp(999).toFloat(); setColor(PILL_BG); if (stroke) setStroke(dp(1), PILL_EDGE)
    }

    private fun ensureView(): LinearLayout {
        root?.let { return it }
        val ctx = service
        val dm = service.resources.displayMetrics
        val ink = ctx.getColor(R.color.alert_ink)
        val muted = ctx.getColor(R.color.alert_muted)
        val wrap = LinearLayout.LayoutParams.WRAP_CONTENT

        // --- pill: [shield on blue] [risk dot] risk word
        val shieldBadge = ImageView(ctx).apply {
            setImageResource(R.drawable.ic_stat_shield)
            setColorFilter(Color.WHITE)
            setPadding(dp(6), dp(5), dp(6), dp(6))
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(BRAND) }
        }
        chipDot = View(ctx).apply { background = GradientDrawable().apply { shape = GradientDrawable.OVAL } }
        chipText = TextView(ctx).apply {
            setTextColor(Color.WHITE); textSize = 14f; setTypeface(typeface, Typeface.BOLD); maxLines = 1
        }
        chip = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(48); setPadding(dp(6), dp(6), dp(16), dp(6))
            background = pillBg(stroke = true)
            elevation = dp(6).toFloat()
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            isClickable = true
            setOnClickListener { apply(state.tap()) }
            addView(shieldBadge, LinearLayout.LayoutParams(dp(30), dp(30)))
            addView(chipDot, LinearLayout.LayoutParams(dp(9), dp(9)).apply { marginStart = dp(10); marginEnd = dp(8) })
            addView(chipText, LinearLayout.LayoutParams(wrap, wrap))
        }

        // --- card: header (logo · ScamShield · badge), title, why, buttons
        val logo = ImageView(ctx).apply {
            setImageResource(R.drawable.ic_stat_shield); setColorFilter(BRAND)
        }
        val brand = TextView(ctx).apply { text = "ScamShield"; setTextColor(muted); textSize = 13f; setTypeface(typeface, Typeface.BOLD) }
        badge = TextView(ctx).apply {
            textSize = 12f; setTypeface(typeface, Typeface.BOLD); letterSpacing = 0.04f
            setPadding(dp(10), dp(4), dp(10), dp(4))
            background = GradientDrawable().apply { cornerRadius = dp(999).toFloat() }
        }
        val header = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            addView(logo, LinearLayout.LayoutParams(dp(20), dp(22)))
            addView(brand, LinearLayout.LayoutParams(0, wrap, 1f).apply { marginStart = dp(8) })
            addView(badge, LinearLayout.LayoutParams(wrap, wrap))
        }
        title = TextView(ctx).apply {
            setTextColor(ink); textSize = 20f; setTypeface(typeface, Typeface.BOLD)
            maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END
        }
        why = TextView(ctx).apply {
            setTextColor(ink); textSize = 15f; setLineSpacing(0f, 1.15f)
            maxLines = WHY_MAX_LINES; ellipsize = android.text.TextUtils.TruncateAt.END
        }
        fun pillBtn() = Button(ctx).apply {
            isAllCaps = false; textSize = 15f; maxLines = 1; setTypeface(typeface, Typeface.BOLD)
            minHeight = dp(48); minimumHeight = dp(48); minWidth = 0; minimumWidth = 0
            setPadding(dp(12), 0, dp(12), 0); stateListAnimator = null
            background = GradientDrawable().apply { cornerRadius = dp(999).toFloat() }
        }
        primaryBtn = pillBtn()
        reportBtn = pillBtn().apply {
            (background as GradientDrawable).setColor(ctx.getColor(R.color.alert_accent_tint))
            setTextColor(ctx.getColor(R.color.alert_accent))
            setOnClickListener { openReport(); closeOrDismiss() }
        }
        dismissBtn = ImageButton(ctx).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel); setColorFilter(ink)
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(ctx.getColor(R.color.alert_chip)) }
            setOnClickListener { closeOrDismiss() }
        }
        val buttons = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            addView(primaryBtn, LinearLayout.LayoutParams(0, dp(48), 1.3f))
            addView(reportBtn, LinearLayout.LayoutParams(0, dp(48), 1f).apply { marginStart = dp(8) })
            addView(dismissBtn, LinearLayout.LayoutParams(dp(48), dp(48)).apply { marginStart = dp(8) })
        }
        card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(16), dp(18), dp(18))
            background = GradientDrawable().apply { cornerRadius = dp(28).toFloat(); setColor(ctx.getColor(R.color.alert_card)) }
            elevation = dp(12).toFloat()
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            addView(header)
            addView(title, LinearLayout.LayoutParams(wrap, wrap).apply { topMargin = dp(10) })
            addView(why, LinearLayout.LayoutParams(wrap, wrap).apply { topMargin = dp(6) })
            addView(buttons, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, wrap).apply { topMargin = dp(14) })
        }
        val cardW = minOf((dm.widthPixels * 0.92f).toInt(), dp(CARD_MAX_WIDTH_DP))
        val layout = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(8), 0, dp(8), dp(12))   // room for the shadows
            clipToPadding = false; clipChildren = false
            addView(chip, LinearLayout.LayoutParams(wrap, wrap))
            addView(card, LinearLayout.LayoutParams(cardW, wrap).apply { topMargin = dp(10) })
        }
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            // NOT_TOUCH_MODAL: touches outside our own bounds reach the app underneath.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.CENTER_HORIZONTAL or Gravity.TOP; y = pillY() }
        wm.addView(layout, lp)
        root = layout
        return layout
    }

    /** Opens ScamShield's report screen (MainActivity reads the `route` extra). */
    private fun openReport() {
        val i = Intent(service, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("route", com.hackasol.scamshield.core.AlertNotificationMapper.ROUTE_REPORT)
        try { service.startActivity(i) } catch (_: Throwable) {}
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
        if (step.armCardTimer) {
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
            lp.y = pillY()
            try { wm.updateViewLayout(view, lp) } catch (_: Throwable) {}
        }
        val lang = AppSettings.lang
        val risk = riskColor(shown)
        val onRisk = if (Color.luminance(risk) > 0.4f) Color.BLACK else Color.WHITE
        (chipDot.background as GradientDrawable).apply { setColor(risk); setStroke(dp(3), Color.argb(70, Color.red(risk), Color.green(risk), Color.blue(risk))) }
        chipText.text = prefix + L10n.labelWord(shown, lang)
        chip.contentDescription = L10n.chipDescription(shown, lang)
        badge.text = L10n.labelWord(shown, lang).uppercase(Locale.ROOT)
        badge.setTextColor(risk)
        (badge.background as GradientDrawable).setColor(Color.argb(36, Color.red(risk), Color.green(risk), Color.blue(risk)))
        (primaryBtn.background as GradientDrawable).setColor(risk)
        primaryBtn.setTextColor(onRisk)
        val p = prompt
        if (p != null) {
            title.text = L10n.captionTitle(lang); why.text = L10n.captionLine(lang)
            primaryBtn.text = L10n.openVolumePanel(lang); primaryBtn.setOnClickListener { p() }
            reportBtn.visibility = View.GONE
        } else {
            val kind = signalKind
            title.text = prefix + (if (kind != null) L10n.signalTitle(kind, lang) else L10n.cardTitle(shown, lang))
            why.text = if (kind != null) L10n.signalAdvice(kind, lang) else L10n.cardWhy(shown, lang)
            primaryBtn.text = L10n.call1930(lang); primaryBtn.setOnClickListener { dial("1930") }
            reportBtn.text = L10n.reportAction(lang).substringBefore(" (")
            reportBtn.visibility = View.VISIBLE
        }
        dismissBtn.contentDescription = L10n.dismiss(lang)
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
