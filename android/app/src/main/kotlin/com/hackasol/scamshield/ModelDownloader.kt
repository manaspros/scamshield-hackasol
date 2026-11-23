package com.hackasol.scamshield

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.StatFs
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.hackasol.scamshield.core.ModelCatalog
import com.hackasol.scamshield.core.ModelConfig
import com.hackasol.scamshield.core.ModelSpec
import com.hackasol.scamshield.core.SttModelConfig
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.ZipInputStream

/**
 * In-app model download via Android's DownloadManager (background, resumable, notification,
 * survives app kill). Writes to models/<name>.download and renames on success, so a half-finished
 * file is never picked up by GemmaClassifier.findModel().
 *
 * Source: public GitHub release (no login/token needed).
 */
object ModelDownloader {
    private const val TAG = "ScamShield/Download"
    const val DEFAULT_URL = ModelConfig.URL
    const val FILE_NAME = ModelConfig.FILENAME

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO +
        kotlinx.coroutines.CoroutineExceptionHandler { _, t -> Log.e(TAG, "uncaught", t) })
    private var pollJob: Job? = null
    private var voskJob: Job? = null

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("scamshield", Context.MODE_PRIVATE)
    private fun dm(ctx: Context) = ctx.getSystemService(DownloadManager::class.java)
    private fun modelsDir(ctx: Context) = File(ctx.getExternalFilesDir(null), "models").apply { mkdirs() }
    /** File name of the model being downloaded (the default until a download picks another). */
    private fun fileOf(ctx: Context) = prefs(ctx).getString("downloadFile", null) ?: FILE_NAME
    private fun partFile(ctx: Context) = File(modelsDir(ctx), "${fileOf(ctx)}.download")

    private fun idOf(ctx: Context) = prefs(ctx).getLong("downloadId", -1L)
    private fun setId(ctx: Context, id: Long) = prefs(ctx).edit().putLong("downloadId", id).apply()

    /** Starts a download of [modelId] (null = the default) from its release URL. Returns a status map (or ERROR with a readable message). */
    suspend fun start(ctx: Context, wifiOnly: Boolean, modelId: String? = null): Map<String, Any?> = withContext(Dispatchers.IO) {
        val app = ctx.applicationContext
        try {
            val spec: ModelSpec = ModelCatalog.byId(modelId) ?: ModelCatalog.byId(ModelCatalog.DEFAULT_ID)!!
            val url = spec.url ?: return@withContext err("${spec.name} is not available to download yet")
            cancel(app)
            val needMb = spec.sizeMb + ModelCatalog.HEADROOM_MB
            val free = StatFs(modelsDir(app).absolutePath).availableBytes
            if (free < needMb * 1024L * 1024L) return@withContext err("Not enough storage: need ~$needMb MB free, have ${free / (1024 * 1024)} MB")
            reachability(url)?.let { return@withContext err(it) }
            prefs(app).edit().putString("downloadFile", spec.file).apply()
            partFile(app).delete()
            val req = DownloadManager.Request(Uri.parse(url))
                .setTitle("AI model")
                .setDescription("${spec.name} (~${spec.sizeMb} MB)")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalFilesDir(app, null, "models/${spec.file}.download")
                .setAllowedOverMetered(!wifiOnly)
                .setAllowedOverRoaming(false)
            val id = dm(app).enqueue(req)
            setId(app, id)
            Log.i(TAG, "enqueued id=$id model=${spec.id} wifiOnly=$wifiOnly")
            watch(app)
            status(app) + ("modelId" to spec.id)
        } catch (t: Throwable) {
            Log.e(TAG, "start failed", t)
            err("Could not start download: ${t.message}")
        }
    }

    /** Quick reachability check so the user gets a clear message instead of a silent failure. */
    private fun reachability(url: String): String? = try {
        val c = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "HEAD"; instanceFollowRedirects = true
            connectTimeout = 15000; readTimeout = 15000
        }
        val code = c.responseCode
        c.disconnect()
        when {
            code in 200..299 -> null
            code == 404 -> "Model not found (404). Check the model URL."
            else -> "Server returned $code. Try again later."
        }
    } catch (e: Exception) {
        "No internet connection (${e.javaClass.simpleName})"
    }

    fun status(ctx: Context): Map<String, Any?> = statusFor(ctx, idOf(ctx))

    private fun statusFor(ctx: Context, id: Long): Map<String, Any?> {
        if (id < 0) return mapOf("status" to "IDLE")
        dm(ctx).query(DownloadManager.Query().setFilterById(id)).use { c ->
            if (c == null || !c.moveToFirst()) return mapOf("status" to "IDLE")
            val st = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val done = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            val reason = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
            val name = when (st) {
                DownloadManager.STATUS_PENDING -> "PENDING"
                DownloadManager.STATUS_RUNNING -> "RUNNING"
                DownloadManager.STATUS_PAUSED -> "PAUSED"
                DownloadManager.STATUS_SUCCESSFUL -> "SUCCESSFUL"
                DownloadManager.STATUS_FAILED -> "FAILED"
                else -> "UNKNOWN"
            }
            val msg = when {
                st == DownloadManager.STATUS_PAUSED && reason == DownloadManager.PAUSED_QUEUED_FOR_WIFI -> "Waiting for Wi-Fi"
                st == DownloadManager.STATUS_PAUSED && reason == DownloadManager.PAUSED_WAITING_FOR_NETWORK -> "Waiting for network"
                st == DownloadManager.STATUS_PAUSED && reason == DownloadManager.PAUSED_WAITING_TO_RETRY -> "Retrying…"
                st == DownloadManager.STATUS_FAILED && reason == DownloadManager.ERROR_INSUFFICIENT_SPACE -> "Not enough storage"
                st == DownloadManager.STATUS_FAILED && reason in 400..599 -> "Server error $reason (link expired? tap Download again)"
                st == DownloadManager.STATUS_FAILED -> "Download failed ($reason)"
                else -> ""
            }
            return mapOf("status" to name, "done" to done, "total" to total, "message" to msg)
        }
    }

    /** Polls progress -> EventBus, finalizes on success. Safe to call repeatedly (e.g. on app start). */
    fun watch(ctx: Context) {
        val app = ctx.applicationContext
        if (idOf(app) < 0 || pollJob?.isActive == true) return
        pollJob = scope.launch {
            while (isActive) {
                val s = try { status(app) } catch (t: Throwable) { Log.e(TAG, "status", t); mapOf("status" to "IDLE") }
                EventBus.emit("download", s)
                when (s["status"]) {
                    "SUCCESSFUL" -> { finish(app); return@launch }
                    "FAILED", "IDLE" -> { setId(app, -1); partFile(app).delete(); return@launch }
                }
                delay(1000)
            }
        }
    }

    private fun finish(ctx: Context) {
        val part = partFile(ctx)
        val name = fileOf(ctx)
        val dest = File(modelsDir(ctx), name)
        setId(ctx, -1)
        if (!part.exists() || part.length() < 100L * 1024 * 1024) {
            part.delete()
            EventBus.emit("download", mapOf("status" to "FAILED", "message" to "Downloaded file is too small — wrong URL?"))
            return
        }
        dest.delete()
        part.renameTo(dest)
        GemmaClassifier.setPreferred(ctx, name)
        EventBus.emit("download", mapOf("status" to "INSTALLED", "message" to "Model downloaded — loading…"))
        GemmaClassifier.ensureLoaded(ctx, force = true)
    }

    fun cancel(ctx: Context) {
        val id = idOf(ctx)
        if (id >= 0) dm(ctx).remove(id)
        setId(ctx, -1)
        pollJob?.cancel(); pollJob = null
        partFile(ctx).delete()
    }

    // ---- Vosk Hindi STT model: DownloadManager zip -> unzip to filesDir/vosk-hi (same flow as the Gemma model) ----

    fun voskDir(ctx: Context) = File(ctx.filesDir, SttModelConfig.DIR_NAME)
    /** The dir only appears after a full, successful unzip (extracted to a .tmp dir first, then renamed). */
    fun voskReady(ctx: Context) = voskDir(ctx).isDirectory
    private fun voskZip(ctx: Context) = File(modelsDir(ctx), "${SttModelConfig.ZIP_NAME}.download")
    private fun voskId(ctx: Context) = prefs(ctx).getLong("voskDownloadId", -1L)
    private fun setVoskId(ctx: Context, id: Long) = prefs(ctx).edit().putLong("voskDownloadId", id).apply()

    /** Starts the Vosk model download. Progress/result events go to EventBus "sttDownload" (same payload as "download"). */
    suspend fun startVosk(ctx: Context, wifiOnly: Boolean): Map<String, Any?> = withContext(Dispatchers.IO) {
        val app = ctx.applicationContext
        try {
            cancelVosk(app)
            val needed = SttModelConfig.ZIP_BYTES * 4 // zip + extracted copy + headroom
            val free = StatFs(modelsDir(app).absolutePath).availableBytes
            if (free < needed) return@withContext err("Not enough storage: need ~${needed / (1024 * 1024)} MB free, have ${free / (1024 * 1024)} MB")
            reachability(SttModelConfig.URL)?.let { return@withContext err(it) }
            voskZip(app).delete()
            val req = DownloadManager.Request(Uri.parse(SttModelConfig.URL))
                .setTitle("Speech model")
                .setDescription("Offline Hindi speech recognition (~42 MB)")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalFilesDir(app, null, "models/${SttModelConfig.ZIP_NAME}.download")
                .setAllowedOverMetered(!wifiOnly)
                .setAllowedOverRoaming(false)
            setVoskId(app, dm(app).enqueue(req))
            watchVosk(app)
            statusFor(app, voskId(app))
        } catch (t: Throwable) {
            Log.e(TAG, "startVosk failed", t)
            err("Could not start download: ${t.message}")
        }
    }

    /** Polls the Vosk download and unzips on success. Safe to call repeatedly (e.g. on app start). */
    fun watchVosk(ctx: Context) {
        val app = ctx.applicationContext
        if (voskId(app) < 0 || voskJob?.isActive == true) return
        voskJob = scope.launch {
            while (isActive) {
                val s = try { statusFor(app, voskId(app)) } catch (t: Throwable) { Log.e(TAG, "vosk status", t); mapOf("status" to "IDLE") }
                EventBus.emit("sttDownload", s)
                when (s["status"]) {
                    "SUCCESSFUL" -> { finishVosk(app); return@launch }
                    "FAILED", "IDLE" -> { setVoskId(app, -1); voskZip(app).delete(); return@launch }
                }
                delay(1000)
            }
        }
    }

    private fun finishVosk(ctx: Context) {
        val zip = voskZip(ctx)
        val tmp = File(ctx.filesDir, "${SttModelConfig.DIR_NAME}.tmp")
        setVoskId(ctx, -1)
        try {
            if (!zip.exists() || zip.length() < SttModelConfig.ZIP_BYTES / 2) throw IllegalStateException("Downloaded file is too small — wrong URL?")
            unzip(zip, tmp)
            voskDir(ctx).deleteRecursively()
            if (!tmp.renameTo(voskDir(ctx))) throw IllegalStateException("Could not install model")
            EventBus.emit("sttDownload", mapOf("status" to "INSTALLED", "message" to "Speech model ready"))
        } catch (t: Throwable) {
            Log.e(TAG, "finishVosk failed", t)
            tmp.deleteRecursively()
            EventBus.emit("sttDownload", mapOf("status" to "FAILED", "message" to "Speech model install failed: ${t.message}"))
        } finally {
            zip.delete()
        }
    }

    fun cancelVosk(ctx: Context) {
        val id = voskId(ctx)
        if (id >= 0) dm(ctx).remove(id)
        setVoskId(ctx, -1)
        voskJob?.cancel(); voskJob = null
        voskZip(ctx).delete()
    }

    /**
     * Extracts [zip] into [target], dropping the archive's single top-level dir. Zip-slip guard: any
     * entry whose canonical path is outside [target] aborts the install.
     * shortcut: no decompressed-size cap (source is the pinned alphacephei URL), add one if the URL becomes user-supplied.
     */
    private fun unzip(zip: File, target: File) {
        target.deleteRecursively()
        target.mkdirs()
        val root = target.canonicalFile
        ZipInputStream(zip.inputStream().buffered()).use { zin ->
            while (true) {
                val e = zin.nextEntry ?: break
                val rel = e.name.substringAfter('/', "")
                if (rel.isEmpty()) continue
                val out = File(root, rel).canonicalFile
                if (!out.path.startsWith(root.path + File.separator)) throw SecurityException("zip entry escapes target: ${e.name}")
                if (e.isDirectory) out.mkdirs() else {
                    out.parentFile?.mkdirs()
                    out.outputStream().use { zin.copyTo(it) }
                }
            }
        }
    }

    private fun err(msg: String) = mapOf("status" to "ERROR", "message" to msg)
}
