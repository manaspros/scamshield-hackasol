package com.hackasol.scamshield

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import java.io.File
import java.io.RandomAccessFile
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Experiment: can this phone give a third-party app call audio through the mic while the call is
 * on speaker? Records 3 s from each audio source, reports RMS/peak and saves a WAV you can play.
 * Silence (peak ≈ 0) means Android is blocking the mic during calls on this phone.
 */
class MicProbe(private val ctx: Context) {
    companion object {
        private const val TAG = "ScamShield/MicProbe"
        private const val RATE = 16000
        private const val SECONDS = 3
        val SOURCES = listOf(
            "MIC" to MediaRecorder.AudioSource.MIC,
            "VOICE_RECOGNITION" to MediaRecorder.AudioSource.VOICE_RECOGNITION,
            "UNPROCESSED" to MediaRecorder.AudioSource.UNPROCESSED,
            "VOICE_COMMUNICATION" to MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            "CAMCORDER" to MediaRecorder.AudioSource.CAMCORDER,
        )
        fun dir(ctx: Context) = File(ctx.getExternalFilesDir(null) ?: ctx.filesDir, "probe").apply { mkdirs() }
    }

    @Volatile var running = false; private set

    fun start() {
        if (running) return
        if (ctx.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            EventBus.emit("mic_probe", mapOf("source" to "-", "status" to "NO_PERMISSION",
                "detail" to "Allow microphone in ScamShield Setup first"))
            return
        }
        running = true
        Thread({
            try { for ((name, src) in SOURCES) probe(name, src) }
            finally { running = false; EventBus.emit("mic_probe_done", emptyMap()) }
        }, "mic-probe").start()
    }

    @Suppress("MissingPermission")
    private fun probe(name: String, source: Int) {
        val minBuf = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        var rec: AudioRecord? = null
        try {
            rec = AudioRecord(source, RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minBuf, RATE))
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                emit(name, "INIT_FAILED", 0.0, 0, null); return
            }
            val samples = ShortArray(RATE * SECONDS)
            rec.startRecording()
            var off = 0
            while (off < samples.size) {
                val n = rec.read(samples, off, minOf(4096, samples.size - off))
                if (n <= 0) break
                off += n
            }
            rec.stop()
            var sum = 0.0; var peak = 0
            for (i in 0 until off) { val s = samples[i].toInt(); sum += s.toDouble() * s; peak = maxOf(peak, abs(s)) }
            val rms = if (off > 0) sqrt(sum / off) else 0.0
            val dbfs = if (rms > 0) 20 * log10(rms / 32768.0) else -120.0
            val file = File(dir(ctx), "probe_$name.wav")
            writeWav(file, samples, off)
            val status = when { off == 0 -> "NO_DATA"; peak < 30 -> "SILENT"; dbfs < -55 -> "VERY_QUIET"; else -> "HAS_AUDIO" }
            emit(name, status, dbfs, peak, file.absolutePath)
        } catch (t: Throwable) {
            Log.w(TAG, "probe $name failed", t)
            emit(name, "ERROR", 0.0, 0, null, t.message)
        } finally {
            try { rec?.release() } catch (_: Throwable) {}
        }
    }

    private fun emit(name: String, status: String, dbfs: Double, peak: Int, path: String?, detail: String? = null) {
        Log.i(TAG, "$name -> $status dbfs=$dbfs peak=$peak")
        EventBus.emit("mic_probe", mapOf("source" to name, "status" to status,
            "dbfs" to dbfs, "peak" to peak, "path" to path, "detail" to detail))
    }

    private fun writeWav(f: File, s: ShortArray, n: Int) {
        RandomAccessFile(f, "rw").use { raf ->
            raf.setLength(0)
            val dataLen = n * 2
            fun le32(v: Int) = byteArrayOf(v.toByte(), (v shr 8).toByte(), (v shr 16).toByte(), (v shr 24).toByte())
            fun le16(v: Int) = byteArrayOf(v.toByte(), (v shr 8).toByte())
            raf.write("RIFF".toByteArray()); raf.write(le32(36 + dataLen)); raf.write("WAVE".toByteArray())
            raf.write("fmt ".toByteArray()); raf.write(le32(16)); raf.write(le16(1)); raf.write(le16(1))
            raf.write(le32(RATE)); raf.write(le32(RATE * 2)); raf.write(le16(2)); raf.write(le16(16))
            raf.write("data".toByteArray()); raf.write(le32(dataLen))
            val buf = ByteArray(dataLen)
            for (i in 0 until n) { buf[2 * i] = s[i].toByte(); buf[2 * i + 1] = (s[i].toInt() shr 8).toByte() }
            raf.write(buf)
        }
    }
}
