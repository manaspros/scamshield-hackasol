package com.hackasol.scamshield

import android.content.Context
import android.net.Uri
import com.hackasol.scamshield.core.SttResultParser
import com.hackasol.scamshield.core.SttSegment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.vosk.Model
import org.vosk.Recognizer

/**
 * Offline Hindi STT: [AudioDecoder] 16 kHz mono PCM16 chunks -> Vosk -> [SttSegment]s.
 * Needs the model extracted by [ModelDownloader.startVosk]; see [ModelDownloader.voskReady].
 * Loads the model per call (small-hi is ~42 MB) and closes it; one transcription at a time.
 */
object SttEngine {
    private const val RATE = 16_000f

    /** Decodes [uri] and transcribes it on Dispatchers.IO. Throws IllegalStateException if the model is missing. */
    suspend fun transcribe(
        ctx: Context,
        uri: Uri,
        isCancelled: () -> Boolean = { false },
        onSegment: (SttSegment) -> Unit = {},
    ): List<SttSegment> = withContext(Dispatchers.IO) {
        check(ModelDownloader.voskReady(ctx)) { "Vosk model not downloaded" }
        val out = mutableListOf<SttSegment>()
        fun add(json: String) { SttResultParser.parse(json)?.let { out += it; onSegment(it) } }
        Model(ModelDownloader.voskDir(ctx).absolutePath).use { model ->
            Recognizer(model, RATE).use { rec ->
                rec.setWords(true)
                AudioDecoder.decode(ctx, uri, isCancelled) { pcm ->
                    if (rec.acceptWaveForm(pcm, pcm.size)) add(rec.result)
                }
                if (!isCancelled()) add(rec.finalResult)
            }
        }
        out
    }
}
