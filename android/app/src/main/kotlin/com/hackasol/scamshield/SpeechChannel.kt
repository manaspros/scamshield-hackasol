package com.hackasol.scamshield

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Voice typing for the report chat through the phone's default recogniser (Google on most Android phones).
 *  MethodChannel "scamshield/speech": start {locale} -> {mode:"live"} (events follow) | {mode:"intent", text}
 *    (no in-app recogniser: the system voice dialog ran instead); errors NO_PERMISSION / UNAVAILABLE / BUSY.
 *    stop -> finish and deliver the final text; cancel -> drop it.
 *  EventChannel "scamshield/speech/events": {type: ready|partial|rms|final|error|end, text?, level?, code?}
 * Main thread only. Audio never leaves the recogniser; nothing is stored by ScamShield.
 */
class SpeechChannel(private val activity: Activity) {
    companion object {
        const val REQ_VOICE = 4207
        private const val REQ_MIC = 4208
    }

    private var sink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var pendingIntent: MethodChannel.Result? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "scamshield/speech").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(call.argument<String>("locale") ?: "hi-IN", result)
                "stop" -> { recognizer?.stopListening(); result.success(null) }
                "cancel" -> { release(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "scamshield/speech/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
    }

    private fun emit(type: String, text: String? = null, level: Double? = null, code: String? = null) {
        sink?.success(buildMap {
            put("type", type)
            text?.let { put("text", it) }
            level?.let { put("level", it) }
            code?.let { put("code", it) }
        })
    }

    private fun intentFor(locale: String) = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
        .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        .putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, activity.packageName)
        // Let people pause mid-sentence (older people speak slowly); Dart also restarts after an early stop.
        .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 4000L)
        .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 3000L)
        .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 2000L)

    private fun start(locale: String, result: MethodChannel.Result) {
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_MIC)
            result.error("NO_PERMISSION", "microphone permission needed", null)
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) { startDialog(locale, result); return }
        // Quietly drop any previous recogniser: an "end" here would close the panel of the session we are starting.
        release(notify = false)
        val r = SpeechRecognizer.createSpeechRecognizer(activity)
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) = emit("ready")
            override fun onBeginningOfSpeech() {}
            // rmsdB runs roughly -2..10; map to 0..1 for the waveform.
            override fun onRmsChanged(rmsdB: Float) = emit("rms", level = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f).toDouble())
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partial: Bundle?) {
                best(partial)?.let { emit("partial", text = it) }
            }
            override fun onResults(results: Bundle?) {
                emit("final", text = best(results).orEmpty())
                release()
            }
            override fun onError(error: Int) {
                emit("error", code = when (error) {
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "NO_PERMISSION"
                    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "NO_MATCH"
                    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "NETWORK"
                    else -> "E$error"
                })
                release()
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        try {
            r.startListening(intentFor(locale))
            result.success(mapOf("mode" to "live"))
        } catch (t: Throwable) {
            release()
            result.error("UNAVAILABLE", t.message, null)
        }
    }

    private fun best(b: Bundle?): String? =
        b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.takeIf { it.isNotBlank() }

    /** No in-app recogniser service: the system voice-typing dialog instead (result arrives in onActivityResult). */
    private fun startDialog(locale: String, result: MethodChannel.Result) {
        pendingIntent?.error("BUSY", "replaced", null)
        pendingIntent = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intentFor(locale), REQ_VOICE)
        } catch (e: ActivityNotFoundException) {
            pendingIntent = null
            result.error("UNAVAILABLE", "no speech recogniser on this phone", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_VOICE) return false
        val res = pendingIntent ?: return true
        pendingIntent = null
        val text = if (resultCode == Activity.RESULT_OK)
            data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull().orEmpty() else ""
        res.success(mapOf("mode" to "intent", "text" to text))
        return true
    }

    /** Frees the recogniser; tells Dart ("end") only when a session was actually running. */
    fun release(notify: Boolean = true) {
        val r = recognizer ?: return
        recognizer = null
        try { r.cancel(); r.destroy() } catch (_: Throwable) {}
        if (notify) emit("end")
    }
}
