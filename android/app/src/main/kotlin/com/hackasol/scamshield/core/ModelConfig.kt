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

    const val URL_270M = "https://github.com/AB527/open-model/releases/download/v1/gemma3-270m-it-q8.task"

    /** ScamShield's own model, release ScamShieldLLM-v1. For now the Gemma 3 1B file under its own name; the
     *  fine-tuned file replaces it later under a new release, with no app change beyond this entry. */
    const val SCAMSHIELD_LLM_ID = "scamshield-llm-v1"
    const val URL_SCAMSHIELD_LLM = "https://github.com/AB527/open-model/releases/download/ScamShieldLLM-v1/scamshield-llm-v1.task"

    // TODO(host): 3n-E2B (3.1 GB) is over GitHub's 2 GB asset limit; host it elsewhere and fill in its URL.
    val all: List<ModelSpec> = listOf(
        ModelSpec("gemma3-270m", "Gemma 3 · 270M", "gemma3-270m-it-q8.task", URL_270M, 304, 3_000, "fast"),
        // Before the 1B on purpose: recommend() takes the last model that fits, so the default stays Gemma 3 1B.
        ModelSpec(SCAMSHIELD_LLM_ID, "ScamShield LLM · v1", "scamshield-llm-v1.task", URL_SCAMSHIELD_LLM, 528, 4_000, "balanced"),
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

/** One offline speech (Vosk) model the user can pick in Settings › Speech model. */
data class SttSpec(val id: String, val name: String, val url: String, val zipName: String, val zipBytes: Long, val minRamMb: Long)

/** Offline STT (Vosk) model downloads. Pure: no Android deps. */
object SttModelConfig {
    val all = listOf(
        SttSpec("vosk-small-hi", "Hindi · Small", "https://alphacephei.com/vosk/models/vosk-model-small-hi-0.22.zip",
            "vosk-model-small-hi-0.22.zip", 44_458_845L, 0),
        SttSpec("vosk-small-en-in", "Indian English · Small", "https://alphacephei.com/vosk/models/vosk-model-small-en-in-0.4.zip",
            "vosk-model-small-en-in-0.4.zip", 36_000_000L, 0),
        SttSpec("vosk-hi", "Hindi · Large", "https://alphacephei.com/vosk/models/vosk-model-hi-0.22.zip",
            "vosk-model-hi-0.22.zip", 1_500_000_000L, 8000),
    )
    val default = all.first()
    fun byId(id: String?): SttSpec = all.firstOrNull { it.id == id } ?: default

    // Kept for older callers: the default model.
    val URL = default.url
    val ZIP_NAME = default.zipName
    val ZIP_BYTES = default.zipBytes
    /** Directory under filesDir the active model is extracted into (one model installed at a time). */
    const val DIR_NAME = "vosk-hi"
}
