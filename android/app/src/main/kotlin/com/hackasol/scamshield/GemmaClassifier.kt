package com.hackasol.scamshield

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import com.hackasol.scamshield.core.GemmaPrompt
import com.hackasol.scamshield.core.LlmOutputParser
import com.hackasol.scamshield.core.LlmResult
import com.hackasol.scamshield.core.ModelCatalog
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

    private const val PREFERRED = "preferredModelFile"

    /** Remember the model file the user picked (or just downloaded); [findModel] uses it while it exists. */
    fun setPreferred(ctx: Context, fileName: String) {
        prefs(ctx.applicationContext).edit().putString(PREFERRED, fileName).apply()
    }

    fun findModel(ctx: Context): File? {
        val all = modelDirs(ctx)
            .flatMap { d -> d.listFiles()?.toList().orEmpty() }
            .filter { it.isFile && it.name.endsWith(".task") }
        val want = prefs(ctx).getString(PREFERRED, null)
        return all.firstOrNull { it.name == want } ?: all.maxByOrNull { it.lastModified() }
    }

    /** File names of every .task model on this phone (Dart maps them to the live catalog). */
    fun installedFiles(ctx: Context): List<String> = modelDirs(ctx)
        .flatMap { d -> d.listFiles()?.toList().orEmpty() }
        .filter { it.isFile && it.name.endsWith(".task") }
        .map { it.name }
        .distinct()

    /** Catalog ids of the models present on this phone. */
    fun installedIds(ctx: Context): List<String> = modelDirs(ctx)
        .flatMap { d -> d.listFiles()?.toList().orEmpty() }
        .mapNotNull { f -> ModelCatalog.byFile(f.name)?.id }
        .distinct()

    fun statusMap(ctx: Context): Map<String, Any?> {
        val f = modelPath?.let(::File) ?: findModel(ctx)
        return mapOf(
            "status" to status.name,
            "message" to message,
            "path" to f?.absolutePath,
            "sizeMb" to (f?.length()?.div(1024 * 1024)),
            "modelId" to ModelCatalog.byFile(f?.name)?.id,
            "installed" to installedIds(ctx),
            "file" to f?.name,
            "files" to installedFiles(ctx),
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
                        .setMaxTokens(2048)       // prompt + answer (quiz prompts are longer than the classifier's)
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
    suspend fun classify(text: String, context: List<String>, contextLabel: String = GemmaPrompt.CALL_CONTEXT_LABEL): LlmResult? {
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
                    session.addQueryChunk(GemmaPrompt.build(text, context, contextLabel))
                    val raw = session.generateResponse()
                    Log.d(TAG, "rawLen=${raw.length}")   // the raw reply can echo the message text
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

    /**
     * Free-form generation for the Learn tab (quiz questions, flashcards). [prompt] is plain text;
     * it is wrapped in Gemma's chat turn. Returns null if the model isn't ready or inference fails.
     */
    suspend fun generate(prompt: String, temperature: Float = 0.8f, topK: Int = 40): String? {
        val engine = llm ?: return null
        if (status != Status.READY) return null
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                var session: LlmInferenceSession? = null
                try {
                    val sOpts = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                        .setTopK(topK)
                        .setTemperature(temperature)
                        .setRandomSeed((System.nanoTime() and 0x7fffffff).toInt())
                        .build()
                    session = LlmInferenceSession.createFromOptions(engine, sOpts)
                    session.addQueryChunk("<start_of_turn>user\n$prompt<end_of_turn>\n<start_of_turn>model\n")
                    session.generateResponse()
                } catch (t: Throwable) {
                    Log.e(TAG, "generate failed", t)
                    null
                } finally {
                    try { session?.close() } catch (_: Throwable) {}
                }
            }
        }
    }
}
