package com.hackasol.scamshield.core

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PcmResamplerTest {
    @Test fun T2_5_downmixAndRate() {
        val frames = 48_000 // 1 s at 48 kHz stereo, 440 Hz sine; L peak 12000, R peak 8000
        val pcm = ShortArray(frames * 2)
        for (f in 0 until frames) {
            val v = sin(2 * PI * 440 * f / 48_000.0)
            pcm[2 * f] = (v * 12_000).toInt().toShort()
            pcm[2 * f + 1] = (v * 8_000).toInt().toShort()
        }
        val chunks = ArrayList<ShortArray>()
        val r = PcmResampler(48_000, 2) { chunks.add(it) }
        // Feed in odd-sized pieces (frame aligned) to exercise streaming state.
        var i = 0
        while (i < pcm.size) {
            val n = minOf(2 * 1_001, pcm.size - i)
            r.push(pcm.copyOfRange(i, i + n))
            i += n
        }
        r.flush()

        val all = chunks.flatMap { it.asList() }
        assertTrue("length ${all.size}", abs(all.size - 16_000) <= 2)
        assertTrue(chunks.dropLast(1).all { it.size == 8_000 })
        val peak = all.maxOf { abs(it.toInt()) }
        assertEquals(10_000.0, peak.toDouble(), 400.0) // mono = mean(12000, 8000)
    }
}
