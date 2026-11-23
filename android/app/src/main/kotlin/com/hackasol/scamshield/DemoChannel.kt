package com.hackasol.scamshield

import android.app.Activity
import android.util.Log
import com.hackasol.scamshield.core.InMemoryVerdictLog
import com.hackasol.scamshield.core.VerdictLog
import com.hackasol.scamshield.core.demo.DemoClassify
import com.hackasol.scamshield.core.demo.DemoRunner
import com.hackasol.scamshield.core.demo.DemoScenarios
import com.hackasol.scamshield.core.graph.KnowledgeGraph
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * MethodChannel "scamshield/demo" (Demo Lab, T8.1):
 *  demo.scenarios -> List<Map>; demo.modelReady -> Boolean; demo.run {id, engine: "gemma"|"rules", coldStart} -> trace Map;
 *  demo.reset -> null.
 * Isolation: every run uses a fresh in-memory KnowledgeGraph and InMemoryVerdictLog. It never touches TextApi.verdictLog,
 * the listener's graph.db, or TrendChannel's export. Demo alerts are posted via AlertDispatcher titled "[DEMO] ...".
 */
object DemoChannel {
    private const val TAG = "ScamShield/Demo"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main +
        CoroutineExceptionHandler { _, t -> Log.e(TAG, "uncaught", t) })
    private val runLock = Mutex()

    /** The demo namespace is only this per-run state, so reset just drops it. */
    @Volatile private var lastLog: VerdictLog? = null

    fun register(activity: Activity, messenger: BinaryMessenger) {
        val dispatcher by lazy { AlertDispatcher(activity.applicationContext, null, "[DEMO] ") }
        MethodChannel(messenger, "scamshield/demo").setMethodCallHandler { call, result ->
            when (call.method) {
                "demo.scenarios" -> result.success(DemoScenarios.ALL.map { it.toChannelMap() })
                "demo.modelReady" -> {
                    GemmaClassifier.ensureLoaded(activity)   // idempotent; picks up a model downloaded after launch
                    result.success(GemmaClassifier.status == GemmaClassifier.Status.READY)
                }
                "demo.run" -> run(activity, call, result) { dispatcher }
                "demo.reset" -> { lastLog = null; result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    private fun run(activity: Activity, call: MethodCall, result: MethodChannel.Result, dispatcher: () -> AlertDispatcher) {
        val sc = DemoScenarios.byId(call.argument<String>("id").orEmpty())
            ?: return result.error("NO_SCENARIO", "unknown scenario", null)
        val wantGemma = call.argument<String>("engine") == "gemma"
        val cold = call.argument<Boolean>("coldStart") ?: sc.coldStartDefault
        scope.launch {
            try {
                if (wantGemma) GemmaClassifier.ensureLoaded(activity)
                val ready = GemmaClassifier.status == GemmaClassifier.Status.READY
                val note = when {
                    !wantGemma || ready -> null
                    GemmaClassifier.status == GemmaClassifier.Status.NOT_FOUND -> "Model not downloaded, rules only"
                    else -> "Model not ready (${GemmaClassifier.status.name.lowercase()}), rules only"
                }
                val classify: DemoClassify? = if (wantGemma && ready) { t, _, ctx, label -> GemmaClassifier.classify(t, ctx, label) } else null
                val graph = KnowledgeGraph()          // fresh per run: scenarios must not see each other's events
                val log = InMemoryVerdictLog()
                val res = runLock.withLock { withContext(Dispatchers.Default) { DemoRunner(graph, log, classify).run(sc, cold, note) } }
                lastLog = log
                // One notification id is reused by AlertDispatcher, so only the last alert would stay visible anyway.
                res.steps.lastOrNull { it.alert != null }?.let { dispatcher().dispatch(it.verdict, it.shown, it.shown, it.verdict.risk) }
                result.success(res.toMap())
            } catch (t: Throwable) {
                Log.e(TAG, "demo.run failed", t)
                result.error("DEMO", "${t.javaClass.simpleName}: ${t.message}", null)
            }
        }
    }
}
