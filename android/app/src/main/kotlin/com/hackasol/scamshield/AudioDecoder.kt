package com.hackasol.scamshield

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import com.hackasol.scamshield.core.PcmResampler
import java.io.FileDescriptor
import java.nio.ByteOrder

/**
 * Decodes a recorded call (m4a/aac, amr, mp3, ogg/opus, wav) to 16 kHz mono PCM16 chunks (~0.5 s)
 * for the STT engine.
 *
 * Blocking: the caller must run [decode] on a background thread/coroutine (Dispatchers.IO), never the main thread.
 * [isCancelled] is polled between codec buffers so the caller can abort.
 */
object AudioDecoder {
    private const val TIMEOUT_US = 10_000L

    fun decode(context: Context, uri: Uri, isCancelled: () -> Boolean = { false }, onChunk: (ShortArray) -> Unit) =
        decode({ it.setDataSource(context, uri, null) }, isCancelled, onChunk)

    fun decode(fd: FileDescriptor, isCancelled: () -> Boolean = { false }, onChunk: (ShortArray) -> Unit) =
        decode({ it.setDataSource(fd) }, isCancelled, onChunk)

    private fun decode(open: (MediaExtractor) -> Unit, isCancelled: () -> Boolean, onChunk: (ShortArray) -> Unit) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var resampler: PcmResampler? = null
        try {
            open(extractor)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: throw IllegalArgumentException("no audio track")
            extractor.selectTrack(track)
            val inFormat = extractor.getTrackFormat(track)
            codec = MediaCodec.createDecoderByType(inFormat.getString(MediaFormat.KEY_MIME)!!)
            codec.configure(inFormat, null, null, 0)
            codec.start()

            var rate = inFormat.intOr(MediaFormat.KEY_SAMPLE_RATE, 16_000)
            var channels = inFormat.intOr(MediaFormat.KEY_CHANNEL_COUNT, 1)
            var float = false
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            while (!outputDone && !isCancelled()) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (i >= 0) {
                        val size = extractor.readSampleData(codec.getInputBuffer(i)!!, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                when {
                    o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = codec.outputFormat
                        rate = f.intOr(MediaFormat.KEY_SAMPLE_RATE, rate)
                        channels = f.intOr(MediaFormat.KEY_CHANNEL_COUNT, channels)
                        float = f.intOr(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT) ==
                            AudioFormat.ENCODING_PCM_FLOAT
                        resampler?.flush()
                        resampler = null // rebuilt below with the new rate/channels
                    }
                    o >= 0 -> {
                        if (info.size > 0) {
                            val r = resampler ?: PcmResampler(rate, channels, onChunk = onChunk).also { resampler = it }
                            val buf = codec.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder())
                            buf.position(info.offset).limit(info.offset + info.size)
                            val pcm: ShortArray
                            if (float) {
                                val fb = buf.asFloatBuffer()
                                pcm = ShortArray(fb.remaining()) { (fb.get() * 32768f).toInt().coerceIn(-32768, 32767).toShort() }
                            } else {
                                val sb = buf.asShortBuffer()
                                pcm = ShortArray(sb.remaining()).also { sb.get(it) }
                            }
                            r.push(pcm)
                        }
                        outputDone = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        codec.releaseOutputBuffer(o, false)
                    }
                }
            }
            resampler?.flush()
        } finally {
            try { codec?.stop() } catch (_: IllegalStateException) {}
            codec?.release()
            extractor.release()
        }
    }

    private fun MediaFormat.intOr(key: String, default: Int): Int =
        if (containsKey(key)) getInteger(key) else default
}
