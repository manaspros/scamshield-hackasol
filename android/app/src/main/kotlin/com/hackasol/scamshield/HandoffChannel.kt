package com.hackasol.scamshield

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.hackasol.scamshield.core.CaseCard
import com.hackasol.scamshield.core.GoldenHour
import com.hackasol.scamshield.core.EvidenceMake
import com.hackasol.scamshield.core.EvidenceZip
import com.hackasol.scamshield.core.GraphSummary
import com.hackasol.scamshield.core.InMemoryVerdictLog
import com.hackasol.scamshield.core.Label
import com.hackasol.scamshield.core.ReportPack
import com.hackasol.scamshield.core.ReportTargets
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Report / golden-hour bridge. MethodChannel "scamshield/handoff":
 *  report.pack {moneyLost}     -> pack map (targets, evidence from the SQLite log, userFields)
 *  dial {number}               -> opens the dialer for an allowlisted number (1930, 181; never places the call)
 *  dial.contact {number}       -> opens the dialer for a family contact the user saved (digits only)
 *  attach.pick                 -> system picker (images, PDF, audio); copies into cacheDir/attachments -> [{path,name,mime,size}]
 *  open {url}                  -> ACTION_VIEW for an allowlisted https URL
 *  golden.status               -> {started:false} | {started:true,startMs,remainingMs,pack}
 *  golden.start {restart}      -> same as status; starts the 60-minute clock unless one is stored (restart=true overrides)
 *  golden.share {fields, attachments?} -> builds the evidence ZIP (attachments under attachments/, hashed in the manifest)
 *                                 in cacheDir/evidence and opens the share sheet
 *  evidence.make {id?}         -> builds the ZIP from flagged events (one event by id, else last 24 h); {count, items}
 *  evidence.share              -> share sheet for the ZIP evidence.make built
 *  graph.summary               -> readable summary of the live graph (brands, recent events, senders, contact counts)
 *  graph.delete {alerts}       -> {ok:true}; wipes the graph (memory + graph.db), and the verdict log when alerts=true
 *  feedback.mark {tsMs,verdict}-> bool; verdict "safe"|"scam" marks that past alert's sender/numbers/UPI ids; false if nothing recorded
 */
class HandoffChannel(private val activity: Activity, private val scope: CoroutineScope) {
    companion object {
        const val NAME = "scamshield/handoff"
        private const val PREFS = "scamshield_prefs"
        private const val KEY_GOLDEN_START = "golden_start_ms"
        private val ALLOWED_NUMBERS = setOf(ReportTargets.HELPLINE_1930, ReportTargets.WOMEN_HELPLINE_181)
        private val ALLOWED_URLS = setOf(ReportTargets.CYBERCRIME_URL, ReportTargets.CHAKSHU_URL)
        private const val FIELD_MAX = 500
        const val REQ_ATTACH = 4206
        private const val ATTACH_MAX_FILES = 10
        private const val ATTACH_MAX_BYTES = 15L * 1024 * 1024      // per file
        private const val ATTACH_TOTAL_BYTES = 40L * 1024 * 1024    // per evidence ZIP
        private val CONTACT_NUMBER = Regex("""^\+?\d{6,15}$""")
    }

    private var pendingPick: MethodChannel.Result? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "report.pack" -> io(result, "PACK") {
                    packMap(buildPack(call.argument<Boolean>("moneyLost") == true, System.currentTimeMillis()))
                }
                "dial" -> {
                    val n = call.argument<String>("number")
                    if (n == null || n !in ALLOWED_NUMBERS) result.error("BAD_NUMBER", "number not allowed", null)
                    else launch(result, Intent(Intent.ACTION_DIAL, Uri.parse("tel:$n")))
                }
                "dial.contact" -> {
                    // A family contact the user saved themselves; ACTION_DIAL only, so they still press call.
                    val n = call.argument<String>("number")?.replace(Regex("""[\s()-]"""), "")
                    if (n == null || !CONTACT_NUMBER.matches(n)) result.error("BAD_NUMBER", "not a phone number", null)
                    else launch(result, Intent(Intent.ACTION_DIAL, Uri.parse("tel:$n")))
                }
                "attach.pick" -> pickAttachments(result)
                "open" -> {
                    val u = call.argument<String>("url")
                    if (u == null || u !in ALLOWED_URLS) result.error("BAD_URL", "url not allowed", null)
                    else launch(result, Intent(Intent.ACTION_VIEW, Uri.parse(u)))
                }
                "golden.status" -> io(result, "GOLDEN") { goldenPayload(storedStart(), System.currentTimeMillis()) }
                "golden.start" -> io(result, "GOLDEN") {
                    val now = System.currentTimeMillis()
                    var start = storedStart()
                    if (start == null || call.argument<Boolean>("restart") == true) {
                        start = now
                        prefs().edit().putLong(KEY_GOLDEN_START, now).apply()
                    }
                    goldenPayload(start, now)
                }
                "golden.share" -> scope.launch {
                    try {
                        val fields = (call.argument<Map<String, Any?>>("fields") ?: emptyMap())
                            .mapValues { (it.value as? String).orEmpty().take(FIELD_MAX) }
                        val paths = (call.argument<List<Any?>>("attachments") ?: emptyList()).filterIsInstance<String>()
                        sendZip(withContext(Dispatchers.IO) { writeEvidenceZip(fields, readAttachments(paths)) })
                        result.success(true)
                    } catch (t: Throwable) { result.error("SHARE", t.message, null) }
                }
                "evidence.make" -> io(result, "EVIDENCE") { makeEvidence(call.argument<Number>("id")?.toLong()) }
                "evidence.share" -> scope.launch {
                    try {
                        val uri = withContext(Dispatchers.IO) { evidenceFile()?.let(::zipUri) } ?: error("no evidence made yet")
                        sendZip(uri)
                        result.success(true)
                    } catch (t: Throwable) { result.error("SHARE", t.message, null) }
                }
                "graph.summary" -> io(result, "GRAPH") { GraphSummary.build(TextApi.graph(activity).snapshot()) }   // the live copy, not a second DB handle
                "graph.delete" -> io(result, "GRAPH") {
                    val alerts = call.argument<Boolean>("alerts") == true
                    val ok = TextApi.deleteMyData(activity, alerts)
                    if (alerts) {   // evidence ZIPs and the golden-hour clock are derived from the alerts being deleted
                        File(activity.cacheDir, "evidence").listFiles()?.forEach { it.delete() }
                        attachDir().listFiles()?.forEach { it.delete() }
                        prefs().edit().remove(KEY_GOLDEN_START).apply()
                    }
                    mapOf("ok" to ok)
                }
                "feedback.mark" -> io(result, "FEEDBACK") {
                    val ts = call.argument<Number>("tsMs")?.toLong()
                    val verdict = call.argument<String>("verdict")
                    if (ts == null || (verdict != "safe" && verdict != "scam")) false
                    else TextApi.feedback(activity, ts, verdict == "scam")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun io(result: MethodChannel.Result, code: String, block: () -> Any?) {
        scope.launch {
            try { result.success(withContext(Dispatchers.IO) { block() }) }
            catch (t: Throwable) { result.error(code, t.message, null) }
        }
    }

    private fun launch(result: MethodChannel.Result, intent: Intent) {
        try { activity.startActivity(intent); result.success(true) }
        catch (e: ActivityNotFoundException) { result.error("NO_ACTIVITY", e.message, null) }
    }

    private fun prefs() = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun storedStart(): Long? = prefs().getLong(KEY_GOLDEN_START, -1L).takeIf { it > 0 }
    private fun log() = TextApi.verdictLog ?: InMemoryVerdictLog()

    private fun buildPack(moneyLost: Boolean, now: Long): ReportPack =
        ReportPack.build(log().since(now - ReportPack.DEFAULT_WINDOW_MS), moneyLost, now)

    private fun goldenPayload(start: Long?, now: Long): Map<String, Any?> {
        if (start == null) return mapOf("started" to false)
        val card = CaseCard.fromLog(log(), start, now)
        return mapOf(
            "started" to true,
            "startMs" to start,
            "remainingMs" to card.goldenHour.remainingMs(now),
            "pack" to packMap(card.pack),
        )
    }

    private fun writeEvidenceZip(fields: Map<String, String>, attachments: Map<String, ByteArray>): Uri {
        val start = storedStart() ?: error("no golden-hour case started")
        val now = System.currentTimeMillis()
        val card = CaseCard.fromLog(log(), start, now)
        val filled = card.pack.userFields.map { it.copy(value = fields[it.key].orEmpty()) }
        val events = log().since(now - ReportPack.DEFAULT_WINDOW_MS).filter { it.label != Label.SAFE }
        val bytes = EvidenceZip.build(card.copy(pack = card.pack.copy(userFields = filled)), events, attachments)
        return zipUri(saveZip("scamshield-evidence-$start.zip", bytes))
    }

    // ---- report-chat attachments -------------------------------------------------------------------------------

    private fun attachDir() = File(activity.cacheDir, "attachments")

    /** System picker for screenshots, PDFs and recordings; the result arrives in [onActivityResult]. */
    private fun pickAttachments(result: MethodChannel.Result) {
        pendingPick?.success(emptyList<Any>())   // a second tap replaces a picker that never returned
        pendingPick = result
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
            .putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "application/pdf", "audio/*"))
            .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(i, REQ_ATTACH)
        } catch (e: ActivityNotFoundException) {
            pendingPick = null
            result.error("NO_ACTIVITY", e.message, null)
        }
    }

    /** Called from MainActivity.onActivityResult; true if the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_ATTACH) return false
        val res = pendingPick ?: return true
        pendingPick = null
        val uris = buildList {
            data?.clipData?.let { c -> for (k in 0 until c.itemCount) add(c.getItemAt(k).uri) }
            if (isEmpty()) data?.data?.let(::add)
        }
        if (resultCode != Activity.RESULT_OK || uris.isEmpty()) { res.success(emptyList<Any>()); return true }
        scope.launch {
            try { res.success(withContext(Dispatchers.IO) { uris.take(ATTACH_MAX_FILES).mapNotNull(::copyIn) }) }
            catch (t: Throwable) { res.error("ATTACH", t.message, null) }
        }
        return true
    }

    /** Copies a picked document into cacheDir/attachments (so no long-lived URI grant is needed); null if too big. */
    private fun copyIn(uri: Uri): Map<String, Any?>? {
        val cr = activity.contentResolver
        var name = "file"
        var size = -1L
        cr.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME, android.provider.OpenableColumns.SIZE), null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getString(0)?.let { name = it }
                if (!c.isNull(1)) size = c.getLong(1)
            }
        }
        if (size > ATTACH_MAX_BYTES) return null
        val safe = name.substringAfterLast('/').replace(Regex("""[^\p{L}\p{N}._ -]"""), "_").take(80).ifEmpty { "file" }
        val dir = attachDir().apply { mkdirs() }
        val out = File(dir, "${System.currentTimeMillis()}-${(0..9999).random()}-$safe")
        var copied = 0L
        cr.openInputStream(uri)?.use { input ->
            out.outputStream().use { o ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf); if (n < 0) break
                    copied += n
                    if (copied > ATTACH_MAX_BYTES) { o.close(); out.delete(); return null }
                    o.write(buf, 0, n)
                }
            }
        } ?: return null
        return mapOf("path" to out.absolutePath, "name" to safe, "mime" to (cr.getType(uri) ?: ""), "size" to copied)
    }

    /** Files Dart asked to include: only ones inside cacheDir/attachments, within the size budget. */
    private fun readAttachments(paths: List<String>): Map<String, ByteArray> {
        val root = attachDir().canonicalFile
        var total = 0L
        val out = linkedMapOf<String, ByteArray>()
        for (p in paths.take(ATTACH_MAX_FILES)) {
            val f = File(p).canonicalFile
            if (f.parentFile != root || !f.isFile) continue
            if (total + f.length() > ATTACH_TOTAL_BYTES) break
            total += f.length()
            val original = f.name.split('-', limit = 3).getOrElse(2) { f.name }
            out[EvidenceZip.attachmentName(out.size, original)] = f.readBytes()
        }
        return out
    }

    private fun saveZip(name: String, bytes: ByteArray): File {
        val dir = File(activity.cacheDir, "evidence").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }   // one case at a time; drop stale ZIPs
        return File(dir, name).apply { writeBytes(bytes) }
    }

    private fun evidenceFile(): File? = File(activity.cacheDir, "evidence").listFiles()?.firstOrNull { it.extension == "zip" }

    private fun zipUri(f: File): Uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", f)

    private fun sendZip(uri: Uri) {
        val send = Intent(Intent.ACTION_SEND).setType("application/zip")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        send.clipData = ClipData.newRawUri("evidence", uri)
        activity.startActivity(Intent.createChooser(send, null))
    }

    /** One-tap evidence: builds the ZIP from flagged events (one event if [id], else the last 24 h). No golden-hour clock is started. */
    private fun makeEvidence(id: Long?): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val events = EvidenceMake.select(log().since(0), id, now)
        if (events.isEmpty()) return mapOf("count" to 0, "items" to emptyList<Any>())
        saveZip("scamshield-evidence-$now.zip", EvidenceZip.build(EvidenceMake.card(events, now), events))
        return mapOf(
            "count" to events.size,
            "items" to events.map {
                mapOf("id" to it.id, "tsMs" to it.tsMs, "label" to it.label.name, "scamType" to it.scamType?.name,
                    "source" to it.source.name.lowercase(), "triggers" to it.triggers)
            },
        )
    }

    private fun packMap(p: ReportPack): Map<String, Any?> = mapOf(
        "moneyLost" to p.moneyLost,
        "targets" to p.targets.map { mapOf("name" to it.name, "phone" to it.phone, "url" to it.url) },
        "evidence" to p.evidence.map {
            mapOf("tsMs" to it.tsMs, "time" to it.time, "scamType" to it.scamType?.name,
                "source" to it.source.name.lowercase(), "triggers" to it.triggers)
        },
        "userFields" to p.userFields.map { mapOf("key" to it.key, "label" to it.label, "value" to it.value) },
    )
}
