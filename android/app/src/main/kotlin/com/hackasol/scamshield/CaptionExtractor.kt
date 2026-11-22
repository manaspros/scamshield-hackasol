package com.hackasol.scamshield

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.view.Display
import android.view.accessibility.AccessibilityNodeInfo
import android.annotation.TargetApi
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import java.util.concurrent.Executors

/** Reads caption text from on-screen windows via the accessibility node tree. */
class CaptionExtractor(private val service: AccessibilityService) {

    data class WindowText(val pkg: String, val title: String, val text: String)

    /**
     * Text of windows except our own overlay. captionOnly = only walk windows from caption packages
     * (cheap); false = every window (discovery mode). Each window walk is capped at MAX_NODES.
     */
    fun collect(captionOnly: Boolean = true): List<WindowText> {
        val out = mutableListOf<WindowText>()
        val windows = try { service.windows } catch (_: Throwable) { emptyList() }
        for (w in windows) {
            val root = try { w.root } catch (_: Throwable) { null } ?: continue
            val pkg = root.packageName?.toString() ?: continue
            if (pkg == service.packageName) continue
            if (captionOnly && !AppSettings.isCaptionPackage(pkg)) continue
            val sb = StringBuilder()
            budget = MAX_NODES
            gather(root, sb, 0)
            val text = sb.toString().trim()
            if (text.isNotEmpty()) out += WindowText(pkg, w.title?.toString().orEmpty(), text)
        }
        return out
    }

    /** Caption text from the first window that looks like a caption source, or null. */
    fun captionText(all: List<WindowText>): WindowText? = all.firstOrNull { AppSettings.isCaptionPackage(it.pkg) }

    private var budget = 0
    private companion object { const val MAX_NODES = 400 }

    private fun gather(n: AccessibilityNodeInfo, sb: StringBuilder, depth: Int) {
        if (depth > 30 || --budget < 0) return
        if (!n.isEditable) {
            n.text?.toString()?.takeIf { it.isNotBlank() }?.let { sb.append(it).append(' ') }
        }
        for (i in 0 until n.childCount) n.getChild(i)?.let { gather(it, sb, depth + 1) }
    }
}

/**
 * Fallback when the caption window hides its text from accessibility: screenshot (API 30+) of the
 * lower part of the screen -> ML Kit OCR (Devanagari model also reads Latin script).
 */
class OcrCaptionReader(private val service: AccessibilityService) {
    private val executor = Executors.newSingleThreadExecutor()
    private val recognizer = TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
    @Volatile private var busy = false

    /** Region as fractions of screen height. Live Caption usually sits in the lower half. */
    var topFrac = 0.45f
    var bottomFrac = 0.92f

    fun read(onText: (String) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || busy) return
        busy = true
        shot(onText)
    }

    @TargetApi(Build.VERSION_CODES.R)
    private fun shot(onText: (String) -> Unit) {
        service.takeScreenshot(Display.DEFAULT_DISPLAY, executor, object : AccessibilityService.TakeScreenshotCallback {
            override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                try {
                    val hb = result.hardwareBuffer
                    val full = Bitmap.wrapHardwareBuffer(hb, result.colorSpace)?.copy(Bitmap.Config.ARGB_8888, false)
                    hb.close()
                    if (full == null) { busy = false; return }
                    val r = Rect(0, (full.height * topFrac).toInt(), full.width, (full.height * bottomFrac).toInt())
                    val crop = Bitmap.createBitmap(full, r.left, r.top, r.width(), r.height())
                    recognizer.process(InputImage.fromBitmap(crop, 0))
                        .addOnSuccessListener { t ->
                            // Keep only sentence-like blocks (>= 3 words) to skip buttons/labels of the call UI.
                            val text = t.textBlocks.map { it.text.replace('\n', ' ') }
                                .filter { it.split(' ').size >= 3 }
                                .joinToString(" ")
                            if (text.isNotBlank()) onText(text)
                        }
                        .addOnCompleteListener { busy = false }
                } catch (_: Throwable) { busy = false }
            }
            override fun onFailure(errorCode: Int) { busy = false }
        })
    }
}
