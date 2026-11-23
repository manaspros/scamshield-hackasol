package com.hackasol.scamshield.core

/** Single source of truth for the on-device model download. Pure: no Android deps. */
object ModelConfig {
    const val URL = "https://github.com/AB527/open-model/releases/download/v1/gemma3-1b-it-int4.task"
    const val FILENAME = "gemma3-1b-it-int4.task"
    // shortcut: no checksum pinned, so no integrity check on the download; pin one and verify it in ModelDownloader.finish before release.
    val SHA256: String? = null
}

/**
 * One downloadable on-device model. [url] null = not hosted yet ("coming soon" in the picker).
 * [minRamMb] is the total device RAM below which the model is too heavy to run comfortably.
 */
data class ModelSpec(
    val id: String,
    val name: String,
    val file: String,
    val url: String?,
    val sizeMb: Int,
    val minRamMb: Int,
    val tier: String, // "fast" | "balanced" | "best"
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id, "name" to name, "file" to file, "url" to url,
        "sizeMb" to sizeMb, "minRamMb" to minRamMb, "tier" to tier, "available" to (url != null),
    )
}

/** The models the picker offers, smallest first. Pure: no Android deps. */
object ModelCatalog {
    const val DEFAULT_ID = "gemma3-1b-int4"

    // TODO(host): upload the 270M and 3n-E2B .task files to the GitHub release and fill in their URLs.
    val all: List<ModelSpec> = listOf(
        ModelSpec("gemma3-270m", "Gemma 3 · 270M", "gemma3-270m-it-q8.task", null, 300, 3_000, "fast"),
        ModelSpec(DEFAULT_ID, "Gemma 3 · 1B", ModelConfig.FILENAME, ModelConfig.URL, 555, 4_000, "balanced"),
        ModelSpec("gemma3n-e2b", "Gemma 3n · E2B", "gemma-3n-E2B-it-int4.task", null, 3_100, 8_000, "best"),
    )

    fun byId(id: String?): ModelSpec? = all.firstOrNull { it.id == id }

    fun byFile(file: String?): ModelSpec? = all.firstOrNull { it.file == file }

    /** Space to keep free beyond the file itself (DownloadManager temp + app data). */
    const val HEADROOM_MB = 150

    fun fits(spec: ModelSpec, totalRamMb: Long, freeStorageMb: Long): Boolean =
        totalRamMb >= spec.minRamMb && freeStorageMb >= spec.sizeMb + HEADROOM_MB

    /**
     * Largest hosted model that fits this phone's RAM and free storage; the smallest hosted one when none fits
     * (an unknown RAM of 0 counts as "fits anything", so a failed probe never hides the default).
     */
    fun recommend(totalRamMb: Long, freeStorageMb: Long): ModelSpec {
        val hosted = all.filter { it.url != null }
        val ram = if (totalRamMb <= 0) Long.MAX_VALUE else totalRamMb
        val free = if (freeStorageMb <= 0) Long.MAX_VALUE else freeStorageMb
        return hosted.lastOrNull { fits(it, ram, free) } ?: hosted.first()
    }
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
