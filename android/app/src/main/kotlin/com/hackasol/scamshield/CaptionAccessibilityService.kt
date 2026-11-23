package com.hackasol.scamshield

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.hackasol.scamshield.core.CallRiskTracker
import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.InCallSignals
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.ScreenShareMatcher
import com.hackasol.scamshield.core.SignalGate
import com.hackasol.scamshield.core.Source
import com.hackasol.scamshield.core.StatementSegmenter
import com.hackasol.scamshield.core.Verdict

/**
 * Live pipeline:  caption window text -> StatementSegmenter -> TextApi (rules + Gemma)
 *                 -> CallRiskTracker -> AlertDispatcher (bubble + notification) (+ EventBus for the Flutter feed).
 * Also watches call state to OCR-fallback and best-effort auto-enable Live Caption.
 */
class CaptionAccessibilityService : AccessibilityService() {
    companion object {
        private const val TAG = "ScamShield/Service"
        private const val TICK_MS = 300L
        private const val SCAN_DEBOUNCE_MS = 150L
        private const val ENABLE_CHECK_AFTER_MS = 6000L
        @Volatile var instance: CaptionAccessibilityService? = null; private set
    }

    private val main = Handler(Looper.getMainLooper())
    // Reading other apps' node trees is slow binder IPC: never do it on the main thread (ANR -> Android disables us).
    private val scanThread = HandlerThread("scamshield-scan").apply { start() }
    private val bg = Handler(scanThread.looper)
    private lateinit var extractor: CaptionExtractor
    private lateinit var ocr: OcrCaptionReader
    private lateinit var overlay: OverlayController
    private lateinit var dispatcher: AlertDispatcher
    private lateinit var toggler: CaptionToggler
    private lateinit var micProbe: MicProbe
    private val gate = SignalGate()                   // one alert per signal kind per call + call-start re-check
    private var probeDoneThisCall = false
    private val segmenter = StatementSegmenter()
    private val tracker = CallRiskTracker()
    private val recent = ArrayDeque<String>()          // context for the LLM

    private var lastCaption = ""
    private var lastCaptionMs = 0L                     // last time caption text was seen (node or OCR)
    private var lastNodeCaptionMs = 0L
    private var lastOcrMs = 0L
    private val lastDiscovery = HashMap<String, String>()

    private var inCall = false
    private var callStartMs = 0L
    private var enableAttempted = false
    @Volatile private var scanPending = false

    /** Any exception inside an accessibility callback kills the process and Android then disables the service. */
    private inline fun safe(where: String, block: () -> Unit) {
        try { block() } catch (t: Throwable) {
            Log.e(TAG, "error in $where", t)
            EventBus.emit("error", mapOf("where" to where, "message" to "${t.javaClass.simpleName}: ${t.message}"))
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        AppSettings.init(this)
        extractor = CaptionExtractor(this)
        ocr = OcrCaptionReader(this)
        overlay = OverlayController(this)
        dispatcher = AlertDispatcher(this, overlay)
        toggler = CaptionToggler(this, main)
        micProbe = MicProbe(this)
        safe("init") { TextApi.init(this) }
        safe("installReceiver") {
            registerReceiver(installReceiver, IntentFilter(Intent.ACTION_PACKAGE_ADDED).apply { addDataScheme("package") }, null, bg)
        }
        main.post(tick)
        EventBus.emit("service", mapOf("connected" to true))
        Log.i(TAG, "connected")
    }

    override fun onDestroy() {
        instance = null
        main.removeCallbacksAndMessages(null)
        bg.removeCallbacksAndMessages(null)
        scanThread.quitSafely()
        safe("installReceiver") { unregisterReceiver(installReceiver) }
        if (::overlay.isInitialized) safe("hide") { overlay.hide() }
        EventBus.emit("service", mapOf("connected" to false))
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = safe("event") {
        if (event == null || event.packageName == packageName) return@safe
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED)
            event.packageName?.toString()?.let { pkg ->
                gate.noteForeground(pkg, SystemClock.elapsedRealtime())
                bg.post { safe("payGuard") { ForegroundHook.onForeground(this, pkg, System.currentTimeMillis()) } }
            }
        if (inCall && AppSettings.inCallSignals) checkSignals(event)
        if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) return@safe
        if (scanPending) return@safe
        scanPending = true
        bg.postDelayed({
            scanPending = false
            var windows: List<CaptionExtractor.WindowText> = emptyList()
            safe("collect") { windows = extractor.collect(captionOnly = !AppSettings.discoveryMode) }
            main.post { safe("scan") { scan(windows) } }
        }, SCAN_DEBOUNCE_MS)
    }

    private fun scan(windows: List<CaptionExtractor.WindowText>) {
        if (AppSettings.discoveryMode) {
            for (w in windows) {
                if (lastDiscovery[w.pkg] == w.text) continue
                lastDiscovery[w.pkg] = w.text
                Log.i(TAG, "DISCOVERY pkg=${w.pkg} title=${w.title} text=${w.text.take(200)}")
                EventBus.emit("discovery", mapOf("pkg" to w.pkg, "title" to w.title, "text" to w.text.take(300)))
            }
        }
        val caption = extractor.captionText(windows) ?: return
        lastNodeCaptionMs = SystemClock.elapsedRealtime()
        feedSnapshot(caption.text, "node:${caption.pkg}")
    }

    private fun feedSnapshot(text: String, via: String) {
        val now = SystemClock.elapsedRealtime()
        lastCaptionMs = now
        if (text == lastCaption) return
        lastCaption = text
        EventBus.emit("caption", mapOf("text" to text.takeLast(300), "via" to via))
        handleStatements(segmenter.onSnapshot(text, now))
    }

    private val tick = object : Runnable {
        override fun run() {
            safe("tick") { onTick() }
            main.postDelayed(this, TICK_MS)
        }
    }

    private fun onTick() {
        val now = SystemClock.elapsedRealtime()
        handleStatements(segmenter.onTick(now))
        tracker.maybeExpire(now)

        val am = getSystemService(AudioManager::class.java)
        val callNow = am.mode == AudioManager.MODE_IN_CALL || am.mode == AudioManager.MODE_IN_COMMUNICATION
        if (callNow != inCall) {
            inCall = callNow
            EventBus.emit("call", mapOf("active" to callNow))
            if (callNow) {
                callStartMs = now; enableAttempted = false
                gate.startCall(); probeDoneThisCall = false
                segmenter.reset(); tracker.reset(); recent.clear(); lastCaption = ""
                if (AppSettings.inCallSignals) recheckForeground(now)
            }
        }
        if (!inCall) return

        // Experiment: can the mic hear the call on this phone? (once per call, 2 s in)
        if (AppSettings.micProbe && !probeDoneThisCall && now - callStartMs > 2000) {
            probeDoneThisCall = true
            AppSettings.micProbe = false          // one-shot: only the call right after "Test on next call"
            micProbe.start()
        }

        // OCR fallback: in a call, node tree gave no caption for 3 s.
        if (AppSettings.ocrFallback && now - lastNodeCaptionMs > 3000 && now - lastOcrMs > 1000) {
            lastOcrMs = now
            ocr.read { text -> main.post { safe("ocr") { feedSnapshot(text, "ocr") } } }
        }

        // Captions never appeared since the call started -> try to turn Live Caption on (once per call).
        if (!enableAttempted && AppSettings.autoEnableCaptions &&
            now - callStartMs > ENABLE_CHECK_AFTER_MS && lastCaptionMs < callStartMs) {
            enableAttempted = true
            EventBus.emit("captions_missing", emptyMap())
            toggler.tryEnable { ok ->
                safe("toggle") {
                    EventBus.emit("captions_enable", mapOf("ok" to ok))
                    if (!ok) overlay.showCaptionPrompt { toggler.openVolumePanel() }
                }
            }
        }
    }

    private fun checkSignals(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        when (event.eventType) {
            AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED -> {
                val n = event.parcelableData as? Notification
                val text = buildString {
                    event.text.forEach { append(it).append(' ') }
                    n?.extras?.let { e ->
                        append(e.getCharSequence(Notification.EXTRA_TITLE) ?: "").append(' ')
                        append(e.getCharSequence(Notification.EXTRA_TEXT) ?: "").append(' ')
                        append(e.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: "")
                    }
                }
                emitSignal(InCallSignals.fromNotification(text), pkg)
            }
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                emitSignal(InCallSignals.fromForegroundApp(pkg), pkg)
                if (pkg in ScreenShareMatcher.DIALOG_PACKAGES) {
                    val eventText = event.text.joinToString(" ")
                    // Node-tree reads are binder IPC: scan thread only.
                    bg.post { safe("screenShareDialog") {
                        emitSignal(InCallSignals.fromWindowText(pkg, eventText + " " + activeWindowText(pkg)), pkg)
                    } }
                }
            }
        }
    }

    /** Text of the active window if it belongs to [pkg] (bounded walk). Scan thread only. */
    private fun activeWindowText(pkg: String): String {
        val root = rootInActiveWindow ?: return ""
        if (root.packageName?.toString() != pkg) return ""
        val sb = StringBuilder()
        var budget = 300
        fun walk(n: AccessibilityNodeInfo, depth: Int) {
            if (depth > 25 || --budget < 0) return
            n.text?.let { sb.append(it).append(' ') }
            for (i in 0 until n.childCount) n.getChild(i)?.let { walk(it, depth + 1) }
        }
        walk(root, 0)
        return sb.toString()
    }

    /** Call just started: the app that is showing (or was showing a moment ago) may already be a remote-access app. Scan thread. */
    private fun recheckForeground(now: Long) {
        bg.post { safe("callStartRecheck") {
            val active = rootInActiveWindow?.packageName?.toString()
            gate.callStartSignal(active, now)?.let { emitAccepted(it, active.orEmpty()) }
        } }
    }

    private fun emitSignal(signal: InCallSignals.Signal?, pkg: String) {
        gate.accept(signal)?.let { emitAccepted(it, pkg) }
    }

    /** [s] already passed the per-call dedupe. */
    private fun emitAccepted(s: InCallSignals.Signal, pkg: String) {
        EventBus.emit("signal", mapOf("kind" to s.kind, "pkg" to pkg, "trigger" to s.trigger))
        main.post { safe("signal") { onVerdict(InCallSignals.toVerdict(s), s.kind) } }
    }

    /** Package installed while a call is live (dynamic receiver: no manifest entry, no new permission). Runs on the scan thread. */
    private val installReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) = safe("installReceiver") {
            if (!inCall || !AppSettings.inCallSignals || intent == null) return@safe
            if (intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) return@safe   // an update, not a new app
            val pkg = intent.data?.schemeSpecificPart ?: return@safe
            if (pkg == packageName) return@safe
            // Package visibility (API 30+) can hide the new package: then permissions and label stay unknown.
            val info = try { packageManager.getPackageInfo(pkg, PackageManager.GET_PERMISSIONS) } catch (_: Throwable) { null }
            val label = try { packageManager.getApplicationInfo(pkg, 0).loadLabel(packageManager).toString() } catch (_: Throwable) { null }
            emitSignal(InCallSignals.fromInstall(pkg, label, info?.requestedPermissions?.toList()), pkg)
        }
    }

    private fun handleStatements(statements: List<String>) {
        for (s in statements) {
            val ctx = recent.toList()
            recent.addLast(s); if (recent.size > 3) recent.removeFirst()
            EventBus.emit("statement", mapOf("text" to s))
            TextApi.submitCaption(ClassifyRequest(s, ctx, Source.CAPTION)) { v -> main.post { safe("verdict") { onVerdict(v) } } }
        }
    }

    private fun onVerdict(v: Verdict, signalKind: String? = null) {
        val now = SystemClock.elapsedRealtime()
        val shown = if (v.preliminary) {
            if (v.label == Label.SCAM) Label.SUSPICIOUS else v.label   // never go red on rules alone before LLM
        } else tracker.record(v, now)
        dispatcher.dispatch(v, shown, tracker.level(), tracker.risk, signalKind)
        EventBus.emit("verdict", v.toMap() + mapOf(
            "shownLabel" to shown.name, "callLevel" to tracker.level().name, "callRisk" to tracker.risk,
        ))
    }

    /** Demo Lab draws its bubble through the running service's overlay (null before onServiceConnected). */
    fun bubbleSink(): BubbleSink? = if (::overlay.isInitialized) overlay else null

    /** Called from the Flutter "Test overlay" button. */
    fun demoOverlay() = main.post { safe("demo") { demoOverlayNow() } }

    private fun demoOverlayNow() {
        val v = Verdict("Sir aapka parcel customs mein ruka hai, OTP bata dijiye warna digital arrest hoga",
            Label.SCAM, 0.94, "Fake customs + OTP + arrest threat", listOf("OTP bata dijiye", "digital arrest"),
            "demo", 0, Source.CAPTION)
        dispatcher.dispatch(v, Label.SCAM, Label.SCAM, 0.82)
    }
}
