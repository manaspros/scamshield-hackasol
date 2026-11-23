package com.hackasol.scamshield

import android.content.Context
import android.content.SharedPreferences
import com.hackasol.scamshield.core.normalizeLang
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

/** Settings shared by the accessibility service and the Flutter bridge (same process). */
object AppSettings {
    private lateinit var prefs: SharedPreferences
    private lateinit var appCtx: Context

    val DEFAULT_CAPTION_PACKAGES = listOf(
        "com.google.android.as",            // Pixel / GMS "Android System Intelligence" (Live Caption)
    )

    fun init(ctx: Context) {
        appCtx = ctx.applicationContext
        if (!::prefs.isInitialized) prefs = ctx.applicationContext.getSharedPreferences("scamshield", Context.MODE_PRIVATE)
    }

    /** App language written by Flutter under pref `lang_v1` (en|hi|hne); unset or unknown = hi. Read-only here. */
    val lang: String
        get() = if (::prefs.isInitialized) normalizeLang(langPrefs().getString("lang_v1", null)) else "hi"

    private fun langPrefs() = appCtx.getSharedPreferences("scamshield_prefs", Context.MODE_PRIVATE)

    var discoveryMode: Boolean
        get() = prefs.getBoolean("discoveryMode", false)
        set(v) = prefs.edit().putBoolean("discoveryMode", v).apply()

    var overlayEnabled: Boolean
        get() = prefs.getBoolean("overlayEnabled", true)
        set(v) = prefs.edit().putBoolean("overlayEnabled", v).apply()

    var autoEnableCaptions: Boolean
        get() = prefs.getBoolean("autoEnableCaptions", false)
        set(v) = prefs.edit().putBoolean("autoEnableCaptions", v).apply()

    var ocrFallback: Boolean
        get() = prefs.getBoolean("ocrFallback", false)
        set(v) = prefs.edit().putBoolean("ocrFallback", v).apply()

    var micProbe: Boolean
        get() = prefs.getBoolean("micProbe", false)
        set(v) = prefs.edit().putBoolean("micProbe", v).apply()

    var inCallSignals: Boolean
        get() = prefs.getBoolean("inCallSignals", true)
        set(v) = prefs.edit().putBoolean("inCallSignals", v).apply()

    var wifiOnly: Boolean
        get() = prefs.getBoolean("wifiOnly", true)
        set(v) = prefs.edit().putBoolean("wifiOnly", v).apply()

    var useLlm: Boolean
        get() = prefs.getBoolean("useLlm", true)
        set(v) = prefs.edit().putBoolean("useLlm", v).apply()

    /** Extra caption packages found with discovery mode (comma separated). */
    var captionPackages: List<String>
        get() = prefs.getString("captionPackages", null)?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
            ?: DEFAULT_CAPTION_PACKAGES
        set(v) = prefs.edit().putString("captionPackages", v.joinToString(",")).apply()

    /** True if this window package looks like a caption source. */
    fun isCaptionPackage(pkg: String): Boolean =
        pkg in captionPackages || pkg.contains("caption", true) || pkg.contains("interpreter", true)

    fun toMap(): Map<String, Any?> = mapOf(
        "discoveryMode" to discoveryMode,
        "overlayEnabled" to overlayEnabled,
        "autoEnableCaptions" to autoEnableCaptions,
        "ocrFallback" to ocrFallback,
        "useLlm" to useLlm,
        "micProbe" to micProbe,
        "inCallSignals" to inCallSignals,
        "wifiOnly" to wifiOnly,
        "captionPackages" to captionPackages.joinToString(","),
    )

    fun update(m: Map<*, *>) {
        (m["discoveryMode"] as? Boolean)?.let { discoveryMode = it }
        (m["overlayEnabled"] as? Boolean)?.let { overlayEnabled = it }
        (m["autoEnableCaptions"] as? Boolean)?.let { autoEnableCaptions = it }
        (m["ocrFallback"] as? Boolean)?.let { ocrFallback = it }
        (m["useLlm"] as? Boolean)?.let { useLlm = it }
        (m["micProbe"] as? Boolean)?.let { micProbe = it }
        (m["inCallSignals"] as? Boolean)?.let { inCallSignals = it }
        (m["wifiOnly"] as? Boolean)?.let { wifiOnly = it }
        (m["captionPackages"] as? String)?.let { s -> captionPackages = s.split(",").map { it.trim() }.filter { it.isNotEmpty() } }
    }
}

/** Process-local event stream: service -> Flutter live feed. */
object EventBus {
    private val _events = MutableSharedFlow<Map<String, Any?>>(
        extraBufferCapacity = 128, onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val events: SharedFlow<Map<String, Any?>> = _events
    fun emit(type: String, data: Map<String, Any?> = emptyMap()) {
        _events.tryEmit(data + ("type" to type) + ("ts" to System.currentTimeMillis()))
    }
}
