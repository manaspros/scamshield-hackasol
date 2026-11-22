package com.hackasol.scamshield.core

/** Single source of truth for the on-device model download. Pure: no Android deps. */
object ModelConfig {
    const val URL = "https://github.com/AB527/open-model/releases/download/v1/gemma3-1b-it-int4.task"
    const val FILENAME = "gemma3-1b-it-int4.task"
    // shortcut: no known checksum for the release asset, so no integrity check; set it and verify in ModelDownloader.finish when one is published.
    val SHA256: String? = null
}
