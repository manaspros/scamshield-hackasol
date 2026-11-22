package com.hackasol.scamshield.core

/**
 * Streaming downmix-to-mono + resample of interleaved PCM16 to [OUT_RATE] Hz, emitted in
 * [chunkSamples]-sized ShortArrays (default 0.5 s) via [onChunk]. Not thread-safe.
 *
 * shortcut: linear interpolation with no low-pass, so downsampling aliases content above 8 kHz;
 * fine for speech STT at 16 kHz, upgrade to a windowed-sinc/polyphase filter if recognition quality suffers.
 */
class PcmResampler(
    private val inRate: Int,
    private val channels: Int,
    private val chunkSamples: Int = OUT_RATE / 2,
    private val onChunk: (ShortArray) -> Unit,
) {
    private val step = inRate.toDouble() / OUT_RATE // input frames per output sample
    private val out = ShortArray(chunkSamples)
    private var outLen = 0
    private var n = 0L          // global index of the next mono input frame
    private var t = 0.0         // position of the next output sample, in input-frame units
    private var prev = 0.0

    init {
        require(inRate > 0 && channels > 0 && chunkSamples > 0) { "bad rate/channels/chunk" }
    }

    /** Feed [length] interleaved shorts (a trailing partial frame is ignored). */
    fun push(pcm: ShortArray, length: Int = pcm.size) {
        var i = 0
        while (i + channels <= length) {
            var sum = 0
            for (c in 0 until channels) sum += pcm[i + c]
            i += channels
            val x = sum.toDouble() / channels
            if (n == 0L) prev = x
            while (t <= n) {
                val frac = (t - (n - 1)).coerceIn(0.0, 1.0)
                emit((prev + (x - prev) * frac).toInt())
                t += step
            }
            prev = x
            n++
        }
    }

    /** Emit the final partial chunk, if any. */
    fun flush() {
        if (outLen > 0) {
            onChunk(out.copyOf(outLen))
            outLen = 0
        }
    }

    private fun emit(v: Int) {
        out[outLen++] = v.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        if (outLen == chunkSamples) {
            onChunk(out.copyOf())
            outLen = 0
        }
    }

    companion object {
        const val OUT_RATE = 16_000
    }
}
