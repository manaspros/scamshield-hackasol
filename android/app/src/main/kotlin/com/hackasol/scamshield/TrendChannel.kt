package com.hackasol.scamshield

import android.app.Activity
import android.content.Intent
import android.util.Log
import androidx.core.content.FileProvider
import com.hackasol.scamshield.core.TrendExport
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * MethodChannel "scamshield/trend":
 *  trend.export {district: String} -> {count: Int}. Writes anonymised rows ({district, scam_type, date} only,
 *  SAFE skipped, no text) to cacheDir/evidence/trend_export.json and opens the share sheet (application/json).
 *  count == 0 means nothing to share: no file, no share sheet.
 *  Shares through the manifest FileProvider (authority "<applicationId>.fileprovider", res/xml/file_paths.xml
 *  cache-path evidence/); if that is missing the call fails with NO_FILEPROVIDER.
 */
object TrendChannel {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, "scamshield/trend").setMethodCallHandler { call, result ->
            if (call.method != "trend.export") return@setMethodCallHandler result.notImplemented()
            val district = call.argument<String>("district")?.trim()
            if (district.isNullOrEmpty() || district.length > 64) {
                return@setMethodCallHandler result.error("BAD_DISTRICT", "district required", null)
            }
            scope.launch {
                try {
                    val file = withContext(Dispatchers.IO) { writeExport(activity, district) }
                    if (file == null) return@launch result.success(mapOf("count" to 0))
                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", file)
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "application/json"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    activity.startActivity(Intent.createChooser(send, null))
                    result.success(mapOf("count" to rowCount(file)))
                } catch (e: IllegalArgumentException) {
                    // FileProvider missing from manifest or paths.
                    result.error("NO_FILEPROVIDER", e.message, null)
                } catch (t: Throwable) {
                    Log.e("ScamShield/Trend", "export failed", t)
                    result.error("TREND", t.message, null)
                }
            }
        }
    }

    /** Returns null when there are no non-SAFE typed events. */
    private fun writeExport(activity: Activity, district: String): File? {
        val events = TextApi.verdictLog?.since(0L).orEmpty()
        val json = TrendExport.export(events, district)
        if (json == "[]") return null
        val dir = File(activity.cacheDir, "evidence").apply { mkdirs() }
        return File(dir, "trend_export.json").also { it.writeText(json) }
    }

    // Rows are flat objects with no nested braces or text, so counting '{' is exact.
    private fun rowCount(f: File): Int = f.readText().count { it == '{' }
}
