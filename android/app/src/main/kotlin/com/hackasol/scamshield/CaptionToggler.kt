package com.hackasol.scamshield

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Handler
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Best-effort "turn Live Caption on". There is no public API, so in order:
 *  1. If WRITE_SECURE_SETTINGS was granted via adb (demo phone), write the secure setting.
 *  2. Open Quick Settings, find the "Live Caption" tile and click it ONLY if it reports OFF
 *     (clicking a tile whose state we can't read could turn captions off).
 *  3. Otherwise report failure -> caller shows the "turn on captions" bubble.
 */
class CaptionToggler(private val service: AccessibilityService, private val handler: Handler) {
    companion object {
        private const val TAG = "ScamShield/Toggle"
        const val SECURE_KEY = "odi_captions_enabled"   // Pixel; verify with: adb shell settings list secure | grep -i caption
        private val TILE_RE = Regex("(?i)live ?caption|instant caption|लाइव कैप्शन")
        private val OFF_RE = Regex("(?i)\\boff\\b|बंद")
    }

    fun tryEnable(onDone: (Boolean) -> Unit) {
        if (trySecureSetting()) { onDone(true); return }
        if (!service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS)) { onDone(false); return }
        handler.postDelayed({
            var ok = false
            try {
                val tile = service.windows.mapNotNull { it.root }.firstNotNullOfOrNull { find(it, 0) }
                if (tile != null && isOff(tile)) ok = click(tile)
                Log.i(TAG, "tile=${tile?.contentDescription ?: tile?.text} off=${tile?.let(::isOff)} clicked=$ok")
            } catch (t: Throwable) { Log.w(TAG, "tile search failed", t) }
            handler.postDelayed({
                service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
                onDone(ok)
            }, 500)
        }, 900)
    }

    /** Shows the system volume panel, which has a captions button on Pixel/Samsung. */
    fun openVolumePanel() {
        val am = service.getSystemService(AudioManager::class.java)
        am.adjustStreamVolume(AudioManager.STREAM_VOICE_CALL, AudioManager.ADJUST_SAME, AudioManager.FLAG_SHOW_UI)
    }

    private fun trySecureSetting(): Boolean {
        if (service.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) != PackageManager.PERMISSION_GRANTED) return false
        return try {
            Settings.Secure.putInt(service.contentResolver, SECURE_KEY, 1)
        } catch (t: Throwable) { Log.w(TAG, "secure write failed", t); false }
    }

    private fun label(n: AccessibilityNodeInfo) =
        listOfNotNull(n.text, n.contentDescription).joinToString(" ")

    private fun find(n: AccessibilityNodeInfo, depth: Int): AccessibilityNodeInfo? {
        if (depth > 25) return null
        if (TILE_RE.containsMatchIn(label(n))) return n
        for (i in 0 until n.childCount) n.getChild(i)?.let { c -> find(c, depth + 1)?.let { return it } }
        return null
    }

    private fun isOff(n: AccessibilityNodeInfo): Boolean {
        var cur: AccessibilityNodeInfo? = n
        repeat(3) {
            val c = cur ?: return false
            if (c.isCheckable) return !c.isChecked
            val stateDesc = if (android.os.Build.VERSION.SDK_INT >= 30) c.stateDescription else null
            val state = listOfNotNull(stateDesc, c.contentDescription).joinToString(" ")
            if (OFF_RE.containsMatchIn(state)) return true
            cur = c.parent
        }
        return false
    }

    private fun click(n: AccessibilityNodeInfo): Boolean {
        var cur: AccessibilityNodeInfo? = n
        while (cur != null) {
            if (cur.isClickable) return cur.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            cur = cur.parent
        }
        return false
    }
}
