package com.hackasol.scamshield

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import com.hackasol.scamshield.core.LlmOutputParser
import com.hackasol.scamshield.core.LlmResult
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

/**
 * On-device Gemma 3 1B (MediaPipe LLM Inference, .task bundle). Loaded once per process and shared
 * by the accessibility service and the Flutter bridge. Calls are serialized by a mutex.
 *
 * Model lookup (first *.task found):
 *   1. filesDir/models/          (filled by the in-app "Import model" picker)
 *   2. getExternalFilesDir/models (adb push … /sdcard/Android/data/com.hackasol.scamshield/files/models/)
 */
object GemmaClassifier {
    private const val TAG = "ScamShield/Gemma"

    enum class Status { NOT_FOUND, LOADING, READY, ERROR }

    @Volatile var status = Status.NOT_FOUND; private set
    @Volatile var message: String = ""; private set
    @Volatile var modelPath: String? = null; private set

    private var llm: LlmInference? = null
    private val mutex = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO +
        CoroutineExceptionHandler { _, t -> Log.e(TAG, "uncaught", t) })
    private const val MARKER = "gemmaLoadingPath"   // set while loading; still set on next start = native crash

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("scamshield", Context.MODE_PRIVATE)

    fun modelDirs(ctx: Context): List<File> = listOfNotNull(
        File(ctx.filesDir, "models"),
        ctx.getExternalFilesDir(null)?.let { File(it, "models") },
    )

    fun findModel(ctx: Context): File? = modelDirs(ctx)
        .flatMap { d -> d.listFiles()?.toList().orEmpty() }
        .filter { it.isFile && it.name.endsWith(".task") }
        .maxByOrNull { it.lastModified() }

    fun statusMap(ctx: Context): Map<String, Any?> {
        val f = modelPath?.let(::File) ?: findModel(ctx)
        return mapOf(
            "status" to status.name,
            "message" to message,
            "path" to f?.absolutePath,
            "sizeMb" to (f?.length()?.div(1024 * 1024)),
            "searchDirs" to modelDirs(ctx).map { it.absolutePath },
        )
    }

    /** Idempotent: loads the model in the background if present and not loaded yet. */
    fun ensureLoaded(ctx: Context, force: Boolean = false) {
        if (!force && (status == Status.READY || status == Status.LOADING)) return
        val appCtx = ctx.applicationContext
        val file = findModel(appCtx)
        if (file == null) {
            status = Status.NOT_FOUND; message = "No .task model found"; return
        }
        if (file.length() < 100L * 1024 * 1024) {
            status = Status.ERROR; message = "${file.name} is too small (${file.length() / 1024} KB) — not a valid model. Download it again."
            return
        }
        // A native crash inside MediaPipe can't be caught. If the marker from the last attempt is still
        // there, that attempt killed the app: don't auto-retry (that is how a crash loop disables the service).
        val crashed = prefs(appCtx).getString(MARKER, null)
        if (crashed != null && !force) {
            status = Status.ERROR
            message = "Model crashed the app while loading last time (${File(crashed).name}). Tap Reload to try again, or download it again."
            return
        }
        prefs(appCtx).edit().putString(MARKER, file.absolutePath).commit()
        status = Status.LOADING; message = "Loading ${file.name}…"
        EventBus.emit("model", mapOf("status" to status.name, "message" to message))
        scope.launch {
            mutex.withLock {
                try {
                    llm?.close(); llm = null
                    val t0 = System.currentTimeMillis()
                    val opts = LlmInference.LlmInferenceOptions.builder()
                        .setModelPath(file.absolutePath)
                        .setMaxTokens(1024)       // prompt + answer
                        .setMaxTopK(40)
                        .build()
                    llm = LlmInference.createFromOptions(appCtx, opts)
                    modelPath = file.absolutePath
                    status = Status.READY
                    message = "${file.name} loaded in ${System.currentTimeMillis() - t0} ms"
                } catch (t: Throwable) {
                    Log.e(TAG, "load failed", t)
                    status = Status.ERROR; message = "Load failed: ${t.message}"
                } finally {
                    prefs(appCtx).edit().remove(MARKER).commit()
                }
            }
            EventBus.emit("model", mapOf("status" to status.name, "message" to message))
        }
    }

    /** Returns null if the model isn't ready or the output couldn't be parsed. */
    suspend fun classify(text: String, context: List<String>): LlmResult? {
        val engine = llm ?: return null
        if (status != Status.READY) return null
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                var session: LlmInferenceSession? = null
                try {
                    val sOpts = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                        .setTopK(1)
                        .setTemperature(0.0f)
                        .setRandomSeed(0)
                        .build()
                    session = LlmInferenceSession.createFromOptions(engine, sOpts)
                    session.addQueryChunk(Prompt.build(text, context))
                    val raw = session.generateResponse()
                    Log.d(TAG, "raw=$raw")
                    LlmOutputParser.parse(raw)
                } catch (t: Throwable) {
                    Log.e(TAG, "inference failed", t)
                    null
                } finally {
                    try { session?.close() } catch (_: Throwable) {}
                }
            }
        }
    }
}

/** Few-shot prompt. Kept short: every prompt token costs latency on a phone. */
object Prompt {
    private const val HEADER = """You are a fraud detector for Indian phone calls. Classify the caller's STATEMENT as SAFE, SUSPICIOUS or SCAM. Text may be English, Hindi (Devanagari) or Hinglish.
SCAM: asks for OTP/PIN/CVV/password, threatens arrest or "digital arrest", says police/CBI/customs/courier has a case against you, asks to move money to a "safe account", install AnyDesk/an app, or keep the call secret.
SUSPICIOUS: unsolicited bank/KYC/prize/loan/refund claims, urgency, asks for personal details, but no direct demand yet.
SAFE: normal conversation.
Answer with ONLY one line of JSON: {"label":"SAFE|SUSPICIOUS|SCAM","confidence":0.0-1.0,"reason":"max 10 words"}

STATEMENT: "Sir aapke phone pe ek OTP aaya hoga, woh jaldi bata dijiye"
{"label":"SCAM","confidence":0.97,"reason":"Asks you to share OTP"}
STATEMENT: "मैं सीबीआई ऑफिस से बोल रहा हूं, आप डिजिटल अरेस्ट में हैं"
{"label":"SCAM","confidence":0.98,"reason":"Fake CBI digital arrest threat"}
STATEMENT: "Your parcel to Taiwan has drugs, press 1 to talk to customs officer"
{"label":"SCAM","confidence":0.93,"reason":"Fake customs parcel story"}
STATEMENT: "Main SBI bank se bol raha hoon, aapka KYC pending hai"
{"label":"SUSPICIOUS","confidence":0.75,"reason":"Unsolicited bank KYC claim"}
STATEMENT: "Beta khana kha liya? Kal shaam ko milte hain"
{"label":"SAFE","confidence":0.95,"reason":"Normal family conversation"}
STATEMENT: "Your order will be delivered tomorrow between 10 and 12"
{"label":"SAFE","confidence":0.85,"reason":"Routine delivery update"}
"""

    fun build(text: String, context: List<String>): String {
        val sb = StringBuilder(HEADER)
        val ctx = context.takeLast(2).filter { it.isNotBlank() }
        if (ctx.isNotEmpty()) sb.append("\nEarlier in this call: ").append(ctx.joinToString(" | ") { "\"${it.take(150)}\"" }).append('\n')
        sb.append("STATEMENT: \"").append(text.take(300).replace("\"", "'")).append("\"\n")
        return sb.toString()
    }
}
