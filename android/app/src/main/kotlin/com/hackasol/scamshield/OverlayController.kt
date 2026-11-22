package com.hackasol.scamshield

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.Verdict

/**
 * Floating verdict bubble drawn as TYPE_ACCESSIBILITY_OVERLAY (no "draw over apps" permission
 * needed). Collapsed = one line "This statement is SCAM · 87%"; tap to expand. Main thread only.
 */
class OverlayController(private val service: AccessibilityService) {
    private val wm = service.getSystemService(WindowManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private var root: LinearLayout? = null
    private var expanded = false
    private var autoCollapse: Runnable? = null

    private lateinit var title: TextView
    private lateinit var hindi: TextView
    private lateinit var quote: TextView
    private lateinit var detail: TextView
    private lateinit var callLine: TextView
    private lateinit var buttons: LinearLayout
    private lateinit var primaryBtn: Button

    private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), service.resources.displayMetrics).toInt()

    private fun color(label: Label) = when (label) {
        Label.SAFE -> Color.parseColor("#E61B5E20")
        Label.SUSPICIOUS -> Color.parseColor("#F0B45309")
        Label.SCAM -> Color.parseColor("#F5B71C1C")
    }

    private fun ensureView(): LinearLayout {
        root?.let { return it }
        val ctx = service
        fun tv(size: Float, bold: Boolean = false) = TextView(ctx).apply {
            setTextColor(Color.WHITE); textSize = size
            if (bold) setTypeface(typeface, Typeface.BOLD)
        }
        title = tv(16f, bold = true)
        hindi = tv(14f)
        quote = tv(13f).apply { setTypeface(typeface, Typeface.ITALIC); maxLines = 3 }
        detail = tv(13f)
        callLine = tv(12f).apply { alpha = 0.9f }
        primaryBtn = Button(ctx).apply { text = "Call 1930"; isAllCaps = false }
        val dismiss = Button(ctx).apply { text = "Dismiss"; isAllCaps = false; setOnClickListener { hide() } }
        buttons = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.END
            addView(primaryBtn); addView(dismiss)
        }
        val layout = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            background = GradientDrawable().apply { cornerRadius = dp(18).toFloat() }
            elevation = dp(8).toFloat()
            listOf(title, hindi, quote, detail, callLine, buttons).forEach { addView(it) }
            setOnClickListener { setExpanded(!expanded); scheduleCollapse() }
        }
        val lp = WindowManager.LayoutParams(
            service.resources.displayMetrics.widthPixels - dp(24),
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL; y = dp(56) }
        wm.addView(layout, lp)
        root = layout
        return layout
    }

    private fun setExpanded(e: Boolean) {
        expanded = e
        val vis = if (e) View.VISIBLE else View.GONE
        quote.visibility = vis; detail.visibility = vis; callLine.visibility = vis; buttons.visibility = vis
    }

    private fun scheduleCollapse() {
        autoCollapse?.let(handler::removeCallbacks)
        autoCollapse = Runnable { setExpanded(false) }.also { handler.postDelayed(it, 8000) }
    }

    fun showVerdict(v: Verdict, shown: Label, callLevel: Label, callRisk: Double) {
        if (!AppSettings.overlayEnabled) return
        val view = ensureView()
        (view.background as GradientDrawable).setColor(color(shown))
        val icon = when (shown) { Label.SAFE -> "🟢"; Label.SUSPICIOUS -> "🟡"; Label.SCAM -> "🔴" }
        val pct = (v.confidence * 100).toInt()
        title.text = "$icon This statement is ${shown.name} · $pct%" + if (v.preliminary) " …" else ""
        hindi.text = when (shown) {
            Label.SCAM -> "यह धोखाधड़ी हो सकती है — OTP / PIN / पैसे न दें"
            Label.SUSPICIOUS -> "सावधान रहें — कोई निजी जानकारी न दें"
            Label.SAFE -> "सामान्य बातचीत"
        }
        quote.text = "“${v.text}”"
        detail.text = buildString {
            append("Why: ").append(v.reason)
            if (v.triggers.isNotEmpty()) append("\nHeard: ").append(v.triggers.take(4).joinToString(", ") { "\"$it\"" })
            append("\nEngine: ").append(v.engine)
        }
        callLine.text = "Overall call: ${callLevel.name} risk ${(callRisk * 100).toInt()}%"
        primaryBtn.text = "Call 1930"
        primaryBtn.setOnClickListener { dial("1930") }
        setExpanded(shown != Label.SAFE)
        scheduleCollapse()
    }

    fun showCaptionPrompt(onOpen: () -> Unit) {
        val view = ensureView()
        (view.background as GradientDrawable).setColor(Color.parseColor("#F01E3A8A"))
        title.text = "🛡️ Turn on Live Caption for protection"
        hindi.text = "कॉल सुरक्षा के लिए Live Caption चालू करें"
        quote.text = "Tap below, then press the captions button in the volume panel."
        detail.text = ""; callLine.text = ""
        primaryBtn.text = "Open volume panel"
        primaryBtn.setOnClickListener { onOpen(); hide() }
        setExpanded(true)
        scheduleCollapse()
    }

    private fun dial(number: String) {
        val i = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try { service.startActivity(i) } catch (_: Throwable) {}
    }

    fun hide() {
        autoCollapse?.let(handler::removeCallbacks)
        root?.let { try { wm.removeView(it) } catch (_: Throwable) {} }
        root = null
    }
}
