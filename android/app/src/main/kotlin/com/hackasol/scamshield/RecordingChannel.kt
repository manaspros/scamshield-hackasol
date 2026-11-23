package com.hackasol.scamshield

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import com.hackasol.scamshield.core.CallReport
import com.hackasol.scamshield.core.ClassifyRequest
import com.hackasol.scamshield.core.RecordingPipeline
import com.hackasol.scamshield.core.StatementResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext

/**
 * Recorded-call flow: pick (or receive) an audio file -> [SttEngine] (decodes with [AudioDecoder]) ->
 * [RecordingPipeline] with [TextApi.classify] (Source.RECORDING) -> [CallReport], streamed to Dart.
 *
 * MethodChannel `scamshield/recording`:
 *   recording.status        -> {modelReady, busy, sttId}
 *   recording.list          -> {granted, items: [{uri, name, dateMs, durationMs}]} call recordings on the phone, newest first
 *   recording.requestAccess -> null; asks for audio read access (the screen re-lists on resume)
 *   recording.use {uri}     -> true; holds a listed recording as the pending Uri
 *   recording.pick          -> true if a file was chosen (held as the pending Uri), false if cancelled
 *   recording.pending       -> true if a Uri (picked or shared) is waiting
 *   recording.start         -> true; runs on the pending Uri, progress goes to the event channel
 *   recording.downloadModel {id?} -> true; Vosk model download, progress goes to the event channel
 *   recording.cancel        -> true; stops a running job and forgets the pending Uri
 * EventChannel `scamshield/recording/events`: maps
 *   {stage: download|decode|stt|classify|done|error|shared, pct: 0..100,
 *    segment?: {startMs, text}, statement?: {startMs, text, label, triggers, shown},
 *    ready?: true, report?: {overall, risk, statements, topTriggers}, code?: failed|noSpeech|download|cancelled}
 *
 * Privacy: the Uri is only held in memory until the job ends; no audio or transcript is written anywhere.
 * [TextApi.classify] still appends its usual verdict-log row (label, triggers, source; no text).
 * The Uri read grant comes from SAF or from the share intent, which lives as long as the activity task.
 */
class RecordingChannel(private val activity: Activity, private val scope: CoroutineScope) {
    private companion object {
        const val TAG = "ScamShield/Recording"
        const val REQ_PICK = 4204
        const val REQ_AUDIO = 4205
        /** Folder fragments OEM dialers save call recordings under (lower case, matched anywhere in the path). */
        val CALL_DIRS = listOf("call", "phonerecord", "call_rec", "callrecord")
    }

    @Volatile private var pending: Uri? = null
    private var pickResult: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null
    private var job: Job? = null
    private var downloadJob: Job? = null

    fun register(messenger: BinaryMessenger) {
        EventChannel(messenger, "scamshield/recording/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        MethodChannel(messenger, "scamshield/recording").setMethodCallHandler { call, result ->
            when (call.method) {
                "recording.status" -> {
                    ModelDownloader.watchVosk(activity) // resume progress tracking of an earlier download
                    result.success(mapOf("modelReady" to ModelDownloader.voskReady(activity), "busy" to busy(),
                        "sttId" to ModelDownloader.sttId(activity)))
                }
                "recording.list" -> scope.launch {
                    val granted = audioGranted()
                    val items = if (granted) withContext(Dispatchers.IO) { listCallRecordings() } else emptyList()
                    result.success(mapOf("granted" to granted, "items" to items))
                }
                "recording.requestAccess" -> { activity.requestPermissions(arrayOf(audioPermission()), REQ_AUDIO); result.success(null) }
                "recording.use" -> {
                    val u = call.argument<String>("uri")
                    if (u == null || !u.startsWith("content://")) result.error("BAD_URI", "content uri expected", null)
                    else { pending = Uri.parse(u); result.success(true) }
                }
                "recording.pending" -> result.success(pending != null)
                "recording.pick" -> pick(result)
                "recording.start" -> start(result)
                "recording.downloadModel" -> download(result, call.argument<String>("id"))
                "recording.cancel" -> {
                    job?.cancel()
                    if (downloadJob?.isActive == true) ModelDownloader.cancelVosk(activity)
                    downloadJob?.cancel()
                    pending = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun busy() = job?.isActive == true || downloadJob?.isActive == true

    private fun emit(m: Map<String, Any?>) = activity.runOnUiThread { sink?.success(m) }

    // ---- file in: SAF picker or share sheet ----

    private fun pick(result: MethodChannel.Result) {
        if (pickResult != null) { result.error("BUSY", "picker already open", null); return }
        pickResult = result
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("audio/*")
        @Suppress("DEPRECATION")
        activity.startActivityForResult(i, REQ_PICK)
    }

    /** Called from MainActivity.onActivityResult; true if the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK) return false
        val res = pickResult
        pickResult = null
        val uri = data?.data
        if (resultCode == Activity.RESULT_OK && uri != null) pending = uri
        res?.success(resultCode == Activity.RESULT_OK && uri != null)
        return true
    }

    /**
     * Called from MainActivity.onCreate / onNewIntent. Accepts ACTION_SEND with an audio stream (any audio subtype)
     * (manifest filter on MainActivity, singleTop). Holds the Uri and tells Dart ("shared"); a cold-started
     * Dart screen asks `recording.pending` instead. Returns true if the intent was an audio share.
     */
    fun handleShare(intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_SEND || intent.type?.startsWith("audio/") != true) return false
        @Suppress("DEPRECATION")
        val uri = if (android.os.Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (uri == null) return false
        pending = uri
        emit(mapOf("stage" to "shared", "pct" to 0))
        return true
    }

    // ---- call recordings already on the phone ----

    private fun audioPermission() =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE

    private fun audioGranted() = activity.checkSelfPermission(audioPermission()) == PackageManager.PERMISSION_GRANTED

    /** Audio files under a call-recording folder (OEM dialers differ), newest first, at most 30. */
    private fun listCallRecordings(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val pathCol = if (Build.VERSION.SDK_INT >= 29) MediaStore.Audio.Media.RELATIVE_PATH else @Suppress("DEPRECATION") MediaStore.Audio.Media.DATA
        val cols = arrayOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.DISPLAY_NAME, MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DURATION, pathCol)
        try {
            activity.contentResolver.query(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, cols, null, null,
                "${MediaStore.Audio.Media.DATE_ADDED} DESC")?.use { c ->
                while (c.moveToNext() && out.size < 30) {
                    val path = (c.getString(4) ?: "").lowercase()
                    if (CALL_DIRS.none { path.contains(it) }) continue
                    val id = c.getLong(0)
                    out += mapOf(
                        "uri" to ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id).toString(),
                        "name" to (c.getString(1) ?: "").substringBeforeLast('.'),
                        "dateMs" to c.getLong(2) * 1000,
                        "durationMs" to c.getLong(3),
                    )
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "listing call recordings failed", t)
        }
        return out
    }

    // ---- Vosk model download ----

    private fun download(result: MethodChannel.Result, id: String?) {
        if (busy()) { result.error("BUSY", "already working", null); return }
        downloadJob = scope.launch {
            // Subscribe before startVosk so no early "sttDownload" event is missed (the bus has no replay).
            val collector = launch(start = CoroutineStart.UNDISPATCHED) {
                // takeWhile ends the collection on the first terminal status.
                EventBus.events.filter { it["type"] == "sttDownload" }.takeWhile { e ->
                    when (e["status"]) {
                        "INSTALLED" -> { emit(mapOf("stage" to "download", "pct" to 100, "ready" to true)); false }
                        "FAILED", "IDLE" -> { emit(error("download")); false }
                        else -> {
                            val done = (e["done"] as? Number)?.toLong() ?: 0L
                            val total = (e["total"] as? Number)?.toLong() ?: 0L
                            val pct = if (total > 0) (done * 100 / total).toInt().coerceIn(0, 99) else 0
                            emit(mapOf("stage" to "download", "pct" to pct))
                            true
                        }
                    }
                }.collect()
            }
            val started = ModelDownloader.startVosk(activity, AppSettings.wifiOnly, id)
            if (started["status"] == "ERROR") { emit(error("download")); collector.cancel(); return@launch }
            collector.join()
        }
        result.success(true)
    }

    // ---- decode -> STT -> classify -> report ----

    private fun start(result: MethodChannel.Result) {
        val uri = pending
        when {
            uri == null -> result.error("NO_FILE", "no recording selected", null)
            busy() -> result.error("BUSY", "already working", null)
            !ModelDownloader.voskReady(activity) -> result.error("NO_MODEL", "speech model missing", null)
            else -> {
                job = scope.launch(Dispatchers.Default) { run(uri) }
                result.success(true)
            }
        }
    }

    private suspend fun run(uri: Uri) {
        val j = coroutineContext.job
        try {
            emit(mapOf("stage" to "decode", "pct" to 0))
            val durationMs = durationOf(uri)
            // SttEngine pulls PCM from AudioDecoder itself, so decode and stt run interleaved: one "stt" stream.
            val segments = SttEngine.transcribe(activity, uri, isCancelled = { !j.isActive }) { seg ->
                val pct = if (durationMs > 0) (seg.startMs * 100 / durationMs).toInt().coerceIn(0, 99) else 0
                emit(mapOf("stage" to "stt", "pct" to pct,
                    "segment" to mapOf("startMs" to seg.startMs, "text" to seg.text)))
            }
            if (!j.isActive) return
            if (segments.none { it.text.isNotBlank() }) { emit(error("noSpeech")); return }

            // shortcut: runBlocking on a Default thread because the pipeline's classify is non-suspend;
            // fine for a one-off file, revisit if T4.x streams recordings live.
            val pipeline = RecordingPipeline(classify = { text, source ->
                runBlocking { TextApi.classify(ClassifyRequest(text = text, source = source)) }
            })
            var sent = 0
            segments.forEachIndexed { i, seg ->
                if (!j.isActive) return
                pipeline.onSegment(seg).forEach { emit(statementEvent(it, (i + 1) * 100 / segments.size)); sent++ }
            }
            val report = pipeline.finish()
            report.perStatement.drop(sent).forEach { emit(statementEvent(it, 100)) }
            emit(mapOf("stage" to "done", "pct" to 100, "report" to reportMap(report)))
        } catch (c: CancellationException) {
            emit(error("cancelled"))
            throw c
        } catch (t: Throwable) {
            Log.e(TAG, "recording failed", t)
            emit(error("failed"))
        } finally {
            pending = null // nothing from this session is kept
        }
    }

    private suspend fun durationOf(uri: Uri): Long = withContext(Dispatchers.IO) {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(activity, uri)
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        } catch (_: Throwable) { 0L } finally { r.release() }
    }

    private fun error(code: String) = mapOf("stage" to "error", "pct" to 0, "code" to code)

    private fun statementMap(s: StatementResult) = mapOf(
        "startMs" to s.startMs,
        "text" to s.verdict.text,
        "label" to s.verdict.label.name,
        "triggers" to s.verdict.triggers,
        "shown" to s.shown.name,
    )

    private fun statementEvent(s: StatementResult, pct: Int) =
        mapOf("stage" to "classify", "pct" to pct, "statement" to statementMap(s))

    private fun reportMap(r: CallReport) = mapOf(
        "overall" to r.overall.name,
        "risk" to r.risk,
        "statements" to r.perStatement.map { statementMap(it) },
        "topTriggers" to r.topTriggers,
    )
}
