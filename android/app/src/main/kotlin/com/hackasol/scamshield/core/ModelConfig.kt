package com.hackasol.scamshield.core

/** Single source of truth for the on-device model download. Pure: no Android deps. */
object ModelConfig {
    const val URL = "https://github.com/AB527/open-model/releases/download/v1/gemma3-1b-it-int4.task"
    const val FILENAME = "gemma3-1b-it-int4.task"
    // shortcut: no checksum pinned, so no integrity check on the download; pin one and verify it in ModelDownloader.finish before release.
    val SHA256: String? = null
}

/** Offline STT (Vosk Hindi) model download. Pure: no Android deps. */
object SttModelConfig {
    const val URL = "https://alphacephei.com/vosk/models/vosk-model-small-hi-0.22.zip"
    const val ZIP_NAME = "vosk-model-small-hi-0.22.zip"
    /** Zip is 44,458,845 bytes (~42 MB); unzipped it is roughly 2x that. */
    const val ZIP_BYTES = 44_458_845L
    /** Directory under filesDir the zip is extracted into. */
    const val DIR_NAME = "vosk-hi"
}
