package com.hackasol.scamshield

import android.Manifest
import android.content.ComponentName
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Flutter bridge.
 *  MethodChannel "scamshield/api": classify, upi.check {link, expectedName}, modelStatus, loadModel, importModel, getSettings,
 *    setSettings, serviceStatus, app.initialRoute, perm.notificationsGranted, perm.requestNotifications, perm.notificationAccessGranted, perm.openNotificationAccess, openAccessibilitySettings, openCaptionSettings, testOverlay
 *  EventChannel  "scamshield/events": caption / statement / verdict / discovery / call / model events
 */
class MainActivity : FlutterActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main +
        CoroutineExceptionHandler { _, t -> Log.e("ScamShield/Main", "uncaught", t) })
    private var pendingImport: MethodChannel.Result? = null
    private var player: MediaPlayer? = null
    private var recording: RecordingChannel? = null
    private var initialRoute: String? = null   // from the launching intent's `route` extra; consumed once by app.initialRoute

    companion object { private const val REQ_IMPORT = 4201
        private const val REQ_NOTIF = 4203
        private val PREF_KEYS = setOf("lesson_best_v1", "district", "lang_v1", "captions_ack_v1", "demo_mode") }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        initialRoute = intent?.getStringExtra("route")
        if (intent != null && recording?.handleShare(intent) == true) initialRoute = "recording"
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra("route")?.let { initialRoute = it }
        if (recording?.handleShare(intent) == true) initialRoute = "recording"
    }

    // FlutterActivity treats the intent extra "route" as its own initial route; pin it to "/" (app.initialRoute is the source).
    override fun getInitialRoute(): String = "/"

    private fun notificationsGranted() = android.os.Build.VERSION.SDK_INT < 33 ||
        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TextApi.init(this)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        FamilyChannel.register(messenger, this)
        QrChannel.register(messenger, this)
        HandoffChannel(this, scope).register(messenger)
        recording = RecordingChannel(this, scope).also { it.register(messenger) }

        MethodChannel(messenger, "scamshield/api").setMethodCallHandler { call, result ->
            when (call.method) {
                "classify" -> scope.launch {
                    val req = TextApi.requestFromMap(call.arguments as Map<*, *>)
                    try { result.success(TextApi.classify(req).toMap()) }
                    catch (t: Throwable) { result.error("CLASSIFY", "${t.javaClass.simpleName}: ${t.message} / cause: ${t.cause}", null) }
                }
                "upi.check" -> scope.launch {
                    try {
                        result.success(TextApi.upiCheck(call.argument<String>("link").orEmpty(), call.argument<String>("expectedName")))
                    } catch (t: Throwable) { result.error("UPI", t.message, null) }
                }
                "verdicts.recent" -> scope.launch {
                    try {
                        val since = (call.argument<Number>("sinceMs") ?: (call.arguments as? Number) ?: 0L).toLong()
                        val rows = withContext(Dispatchers.IO) {
                            TextApi.verdictLog?.since(since).orEmpty().map { VerdictRowMapper.toChannelMap(it) }
                        }
                        result.success(rows)
                    } catch (t: Throwable) { result.error("VERDICTS", t.message, null) }
                }
                "verdicts.counts" -> scope.launch {
                    try {
                        val counts = withContext(Dispatchers.IO) {
                            TextApi.verdictLog?.countsByType().orEmpty().mapKeys { it.key.name }
                        }
                        result.success(counts)
                    } catch (t: Throwable) { result.error("VERDICTS", t.message, null) }
                }
                "modelStatus" -> result.success(GemmaClassifier.statusMap(this))
                "loadModel" -> { GemmaClassifier.ensureLoaded(this, force = true); result.success(GemmaClassifier.statusMap(this)) }
                "importModel" -> startImport(result)
                "downloadModel" -> scope.launch {
                    result.success(ModelDownloader.start(this@MainActivity, AppSettings.wifiOnly))
                }
                "downloadStatus" -> result.success(ModelDownloader.status(this))
                "cancelDownload" -> { ModelDownloader.cancel(this); result.success(null) }
                "getSettings" -> result.success(AppSettings.toMap())
                "setSettings" -> {
                    AppSettings.update(call.arguments as Map<*, *>)
                    if (AppSettings.useLlm) GemmaClassifier.ensureLoaded(this)
                    result.success(AppSettings.toMap())
                }
                "serviceStatus" -> result.success(mapOf(
                    "enabled" to isServiceEnabled(),
                    "connected" to (CaptionAccessibilityService.instance != null),
                    "sdk" to android.os.Build.VERSION.SDK_INT,
                ))
                "openAccessibilitySettings" -> { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)); result.success(null) }
                "openCaptionSettings" -> { openCaptionSettings(); result.success(null) }
                "micPermission" -> result.success(
                    checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
                "requestMic" -> { requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4202); result.success(null) }
                "app.initialRoute" -> { result.success(initialRoute); initialRoute = null }
                "perm.notificationsGranted" -> result.success(notificationsGranted())
                "perm.requestNotifications" -> {
                    // Dart re-checks on app resume (Setup already does this for the mic).
                    if (!notificationsGranted()) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
                    result.success(notificationsGranted())
                }
                "perm.notificationAccessGranted" -> result.success(
                    androidx.core.app.NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName))
                "perm.openNotificationAccess" -> { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)); result.success(null) }
                "runMicProbe" -> { MicProbe(applicationContext).start(); result.success(null) }
                "playProbe" -> {
                    val path = call.argument<String>("path")
                    try {
                        player?.release()
                        player = MediaPlayer().apply { setDataSource(path); prepare(); start() }
                        result.success(true)
                    } catch (t: Throwable) { result.error("PLAY", t.message, null) }
                }
                "testOverlay" -> {
                    val svc = CaptionAccessibilityService.instance
                    if (svc == null) result.error("NO_SERVICE", "Accessibility service not running", null)
                    else { svc.demoOverlay(); result.success(true) }
                }
                else -> result.notImplemented()
            }
        }

        // Lessons best-score store: private prefs, allowlisted keys only.
        MethodChannel(messenger, "scamshield/prefs").setMethodCallHandler { call, result ->
            val key = call.argument<String>("key")
            val prefs = getSharedPreferences("scamshield_prefs", MODE_PRIVATE)
            when {
                key == null || key !in PREF_KEYS -> result.error("BAD_KEY", "key not allowed", null)
                call.method == "getString" -> result.success(prefs.getString(key, null))
                call.method == "setString" -> {
                    prefs.edit().putString(key, call.argument<String>("value")).apply(); result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "scamshield/events").setStreamHandler(object : EventChannel.StreamHandler {
            private var job: Job? = null
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                job = scope.launch { EventBus.events.collect { sink.success(it) } }
            }
            override fun onCancel(arguments: Any?) { job?.cancel(); job = null }
        })

        TrendChannel.register(this, messenger)
        DemoChannel.register(this, messenger)
    }

    private fun isServiceEnabled(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        val me = ComponentName(this, CaptionAccessibilityService::class.java).flattenToString()
        return enabled.split(':').any { it.equals(me, ignoreCase = true) }
    }

    private fun openCaptionSettings() {
        // No public intent for Live Caption; try known ones, fall back to Accessibility settings.
        val candidates = listOf(
            Intent("com.android.settings.action.live_caption"),
            Intent("android.settings.CAPTIONING_SETTINGS"),
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS),
        )
        for (i in candidates) {
            try { startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); return } catch (_: Throwable) {}
        }
    }

    private fun startImport(result: MethodChannel.Result) {
        pendingImport = result
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
        @Suppress("DEPRECATION")
        startActivityForResult(i, REQ_IMPORT)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (recording?.onActivityResult(requestCode, resultCode, data) == true) return
        if (requestCode != REQ_IMPORT) return
        val res = pendingImport ?: return
        pendingImport = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) { res.success(mapOf("status" to "CANCELLED")); return }
        scope.launch {
            try {
                val name = withContext(Dispatchers.IO) {
                    val dir = File(filesDir, "models").apply { mkdirs() }
                    val fname = uri.lastPathSegment?.substringAfterLast('/')?.substringAfterLast(':')
                        ?.takeIf { it.endsWith(".task") || it.endsWith(".litertlm") } ?: "model.task"
                    val tmp = File(dir, "$fname.part")
                    contentResolver.openInputStream(uri)!!.use { input -> tmp.outputStream().use { input.copyTo(it, 1 shl 20) } }
                    val dest = File(dir, fname)
                    dest.delete(); tmp.renameTo(dest)
                    fname
                }
                GemmaClassifier.ensureLoaded(this@MainActivity, force = true)
                res.success(GemmaClassifier.statusMap(this@MainActivity) + ("imported" to name))
            } catch (t: Throwable) {
                res.error("IMPORT", t.message, null)
            }
        }
    }

    override fun onDestroy() {
        player?.release(); player = null
        scope.cancel()
        super.onDestroy()
    }
}
