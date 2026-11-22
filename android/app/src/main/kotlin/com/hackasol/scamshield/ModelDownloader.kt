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
import com.hackasol.scamshield.core.ModelConfig
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

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
    private const val NEEDED_BYTES = 700L * 1024 * 1024

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO +
        kotlinx.coroutines.CoroutineExceptionHandler { _, t -> Log.e(TAG, "uncaught", t) })
    private var pollJob: Job? = null

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("scamshield", Context.MODE_PRIVATE)
    private fun dm(ctx: Context) = ctx.getSystemService(DownloadManager::class.java)
    private fun modelsDir(ctx: Context) = File(ctx.getExternalFilesDir(null), "models").apply { mkdirs() }
    private fun partFile(ctx: Context) = File(modelsDir(ctx), "$FILE_NAME.download")

    private fun idOf(ctx: Context) = prefs(ctx).getLong("downloadId", -1L)
    private fun setId(ctx: Context, id: Long) = prefs(ctx).edit().putLong("downloadId", id).apply()

    /** Starts a download from the GitHub release. Returns a status map (or ERROR with a readable message). */
    suspend fun start(ctx: Context, wifiOnly: Boolean): Map<String, Any?> = withContext(Dispatchers.IO) {
        val app = ctx.applicationContext
        try {
            cancel(app)
            val free = StatFs(modelsDir(app).absolutePath).availableBytes
            if (free < NEEDED_BYTES) return@withContext err("Not enough storage: need ~700 MB free, have ${free / (1024 * 1024)} MB")
            reachability(DEFAULT_URL)?.let { return@withContext err(it) }
            partFile(app).delete()
            val req = DownloadManager.Request(Uri.parse(DEFAULT_URL))
                .setTitle("AI model")
                .setDescription("On-device model (~555 MB)")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setDestinationInExternalFilesDir(app, null, "models/$FILE_NAME.download")
                .setAllowedOverMetered(!wifiOnly)
                .setAllowedOverRoaming(false)
            val id = dm(app).enqueue(req)
            setId(app, id)
            Log.i(TAG, "enqueued id=$id wifiOnly=$wifiOnly")
            watch(app)
            status(app)
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
            code == 404 -> "Model not published yet on GitHub (404). Upload it to the v1 release first."
            else -> "GitHub returned $code. Try again later."
        }
    } catch (e: Exception) {
        "No internet connection (${e.javaClass.simpleName})"
    }

    fun status(ctx: Context): Map<String, Any?> {
        val id = idOf(ctx)
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
        val dest = File(modelsDir(ctx), FILE_NAME)
        setId(ctx, -1)
        if (!part.exists() || part.length() < 100L * 1024 * 1024) {
            part.delete()
            EventBus.emit("download", mapOf("status" to "FAILED", "message" to "Downloaded file is too small — wrong URL?"))
            return
        }
        dest.delete()
        part.renameTo(dest)
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

    private fun err(msg: String) = mapOf("status" to "ERROR", "message" to msg)
}
