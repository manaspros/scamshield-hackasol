package com.hackasol.scamshield.core

/** Pure mapping of an incoming share intent to the text to classify (no Android imports). */
object ShareIntentMapper {
    const val MAX_CHARS = 2000
    private const val ACTION_SEND = "android.intent.action.SEND"

    /** Null unless this is a SEND of text/plain with non-blank text; trimmed and capped at [MAX_CHARS]. */
    fun map(action: String?, type: String?, text: CharSequence?): String? {
        if (action != ACTION_SEND || type?.trim()?.lowercase()?.startsWith("text/plain") != true) return null
        return text?.toString()?.trim()?.take(MAX_CHARS)?.trim()?.ifEmpty { null }
    }
}
